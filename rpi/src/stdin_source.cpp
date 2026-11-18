#include "stdin_source.hpp"

#include <cerrno>
#include <cmath>
#include <cstring>
#include <sstream>

#include <fcntl.h>
#include <unistd.h>

namespace {

bool noMoreFields(std::istringstream& input) {
    std::string extra;
    return !(input >> extra);
}

}  // namespace

StdinSource::~StdinSource() {
    if (original_flags_ >= 0) {
        fcntl(STDIN_FILENO, F_SETFL, original_flags_);
    }
}

bool StdinSource::open(mapping::Config& config, std::string& error) {
    if (isatty(STDIN_FILENO)) {
        error = "stdin source requires a piped data stream";
        return false;
    }

    std::string line;
    char ch;
    while (line.size() < 4096) {
        const ssize_t count = ::read(STDIN_FILENO, &ch, 1);
        if (count == 1) {
            if (ch == '\n') break;
            line.push_back(ch);
        } else if (count == 0) {
            error = "Stream ended before its header";
            return false;
        } else if (errno != EINTR) {
            error = std::string("Cannot read stream header: ") +
                    std::strerror(errno);
            return false;
        }
    }
    if (line.size() == 4096) {
        error = "Stream header is too long";
        return false;
    }

    std::istringstream input(line);
    std::string magic;
    int version, matcher;
    auto& c = config.camera;
    auto& p = config.initial_pose;
    auto& v = config.initial_velocity;
    auto& g = config.gravity;
    if (!(input >> magic >> version)) {
        error = "Invalid stream header";
        return false;
    }
    if (magic == "FVIO_IMU") {
        config.stationary_start = version == 2;
        const bool supplied = version == 1 && (input >> g[0] >> g[1] >> g[2]) && cv::checkRange(g);
        if ((!supplied && !config.stationary_start) || !noMoreFields(input)) {
            error = "Invalid IMU stream header";
            return false;
        }
    } else {
        if (!(input >> width_ >> height_
              >> c.fx >> c.fy >> c.cx >> c.cy >> c.baseline
              >> g[0] >> g[1] >> g[2]
              >> p.position[0] >> p.position[1] >> p.position[2]
              >> p.quaternion[0] >> p.quaternion[1] >> p.quaternion[2]
              >> p.quaternion[3]
              >> v[0] >> v[1] >> v[2]
              >> config.initial_time >> config.max_depth_m
              >> config.disparities >> config.block_size >> matcher)) {
            error = "Invalid stream header";
            return false;
        }
        if (!noMoreFields(input) || magic != "FVIO_STREAM" || version != 1 ||
            width_ <= 0 || height_ <= 0 || width_ > 4096 || height_ > 4096 ||
            !std::isfinite(c.fx) || !std::isfinite(c.fy) ||
            !std::isfinite(c.cx) || !std::isfinite(c.cy) ||
            !std::isfinite(c.baseline) || c.fx <= 0 || c.fy <= 0 ||
            c.baseline <= 0 || config.max_depth_m <= 0 ||
            config.disparities <= 0 || config.block_size <= 0 ||
            (matcher != static_cast<int>(stereo::MatcherAlgorithm::Bm) &&
             matcher != static_cast<int>(stereo::MatcherAlgorithm::Sgbm))) {
            error = "Invalid stream header";
            return false;
        }
        config.matcher = static_cast<stereo::MatcherAlgorithm>(matcher);
    }
    config.imu_pose = true;
    image_bytes_ = static_cast<std::size_t>(width_) * height_ * 4;

    original_flags_ = fcntl(STDIN_FILENO, F_GETFL);
    if (original_flags_ < 0 ||
        fcntl(STDIN_FILENO, F_SETFL, original_flags_ | O_NONBLOCK) < 0) {
        error = std::string("Cannot make stream nonblocking: ") +
                std::strerror(errno);
        original_flags_ = -1;
        return false;
    }
    return true;
}

StdinSource::Poll StdinSource::poll(
    mapping::StreamEvent& event, std::string& error) {
    for (;;) {
        if (frame_pending_) {
            if (buffer_.size() >= image_bytes_) {
                const std::size_t pixels =
                    static_cast<std::size_t>(width_) * height_;
                event = {};
                event.kind = mapping::StreamEvent::Kind::Frame;
                event.frame_number = pending_frame_number_;
                event.frame.time = pending_frame_time_;
                event.frame.left.create(height_, width_, CV_8UC3);
                event.frame.right.create(height_, width_, CV_8UC1);
                std::memcpy(event.frame.left.data, buffer_.data(), pixels * 3);
                std::memcpy(event.frame.right.data,
                            buffer_.data() + pixels * 3, pixels);
                buffer_.erase(0, image_bytes_);
                frame_pending_ = false;
                return Poll::Ready;
            }
        } else {
            const auto end = buffer_.find('\n');
            if (end != std::string::npos) {
                const std::string line = buffer_.substr(0, end);
                buffer_.erase(0, end + 1);
                std::istringstream input(line);
                char kind;
                if (!(input >> kind)) {
                    error = "Empty stream record";
                    return Poll::Error;
                }
                if (kind == 'I') {
                    event = {};
                    event.kind = mapping::StreamEvent::Kind::Imu;
                    auto& s = event.imu;
                    if (!(input >> s.time
                          >> s.acceleration[0] >> s.acceleration[1]
                          >> s.acceleration[2]
                          >> s.angular_velocity[0] >> s.angular_velocity[1]
                          >> s.angular_velocity[2]) ||
                        !noMoreFields(input) || !std::isfinite(s.time)) {
                        error = "Invalid IMU record";
                        return Poll::Error;
                    }
                    return Poll::Ready;
                }
                if (kind == 'F' && !imuOnly()) {
                    if (!(input >> pending_frame_number_ >> pending_frame_time_) ||
                        !noMoreFields(input) || pending_frame_number_ < 0 ||
                        !std::isfinite(pending_frame_time_)) {
                        error = "Invalid frame record";
                        return Poll::Error;
                    }
                    frame_pending_ = true;
                    continue;
                }
                error = "Unknown stream record";
                return Poll::Error;
            }
            if (buffer_.size() > 4096) {
                error = "Stream record header is too long";
                return Poll::Error;
            }
        }

        if (eof_) {
            if (buffer_.empty() && !frame_pending_) return Poll::Finished;
            error = "Truncated stream record";
            return Poll::Error;
        }
        char chunk[65536];
        const ssize_t count = ::read(STDIN_FILENO, chunk, sizeof(chunk));
        if (count > 0) {
            buffer_.append(chunk, static_cast<std::size_t>(count));
        } else if (count == 0) {
            eof_ = true;
        } else if (errno == EAGAIN || errno == EWOULDBLOCK) {
            return Poll::Waiting;
        } else if (errno != EINTR) {
            error = std::string("Cannot read stream: ") + std::strerror(errno);
            return Poll::Error;
        }
    }
}
