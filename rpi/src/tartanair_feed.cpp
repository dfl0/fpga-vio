#include <algorithm>
#include <chrono>
#include <cmath>
#include <exception>
#include <filesystem>
#include <iostream>
#include <string>
#include <thread>
#include <utility>
#include <vector>

#include <opencv2/imgproc.hpp>

#include "stream_writer.hpp"
#include "tartanair_source.hpp"

namespace {

struct ReplayOptions {
    int first = 0, last = 100, step = 1;
    cv::Size size{160, 120};
    stereo::MatcherAlgorithm matcher = stereo::MatcherAlgorithm::Bm;
};

cv::Rect centeredRegion(cv::Size source, cv::Size target) {
    cv::Size region = source;
    if (static_cast<double>(source.width) / source.height >
        static_cast<double>(target.width) / target.height) {
        region.width = static_cast<int>(static_cast<double>(source.height) *
                                        target.width / target.height);
    } else {
        region.height = static_cast<int>(static_cast<double>(source.width) *
                                         target.height / target.width);
    }
    return {(source.width - region.width) / 2,
            (source.height - region.height) / 2, region.width, region.height};
}

int blockSize(double scaled, int minimum) {
    int value = std::max(minimum, static_cast<int>(std::lround(scaled)));
    return value % 2 == 0 ? value + 1 : value;
}

void resize(cv::Mat& image, const cv::Rect& region, cv::Size size,
            int interpolation) {
    if (image.empty()) return;
    cv::Mat output;
    cv::resize(image(region), output, size, 0, 0, interpolation);
    image = std::move(output);
}

class TartanAirReplay {
public:
    enum class Poll { Ready, Waiting, Finished, Error };

    TartanAirReplay(std::filesystem::path trajectory, ReplayOptions options)
        : source_(std::move(trajectory)), options_(options) {}

    bool open(mapping::Config& config, std::string& error) {
        if (options_.first < 0 || options_.last < options_.first ||
            options_.step <= 0 || options_.size.width <= 0 ||
            options_.size.height <= 0) {
            error = "Invalid frame range, step, or image size";
            return false;
        }
        if (!source_.open(true, error)) return false;
        if (static_cast<std::size_t>(options_.last) >= source_.poses().size()) {
            error = "Frame number exceeds the dataset trajectory";
            return false;
        }
        mapping::Frame first_frame;
        if (!source_.readFrame(options_.first, false, false, first_frame, error)) {
            return false;
        }
        const cv::Size source_size = first_frame.left.size();
        region_ = centeredRegion(source_size, options_.size);
        if (options_.size.width > region_.width ||
            options_.size.height > region_.height) {
            error = "Output size exceeds the source image region";
            return false;
        }
        const double sx = static_cast<double>(options_.size.width) / region_.width;
        const double sy = static_cast<double>(options_.size.height) / region_.height;
        const int disparities = std::min(
            16 * static_cast<int>(std::ceil(
                (source_size.width * 0.5 * sx * 0.25 / 1.25) / 16.0)),
            16 * ((options_.size.width / 2) / 16));
        const int block_size = options_.matcher == stereo::MatcherAlgorithm::Bm
            ? blockSize(15.0 * sx, 5) : blockSize(5.0 * sx, 3);
        if (disparities < 16 ||
            options_.size.width <= disparities + block_size ||
            options_.size.height < block_size) {
            error = "Image size is too small for the stereo matcher";
            return false;
        }

        for (int index = options_.first; index <= options_.last;
             index += options_.step) {
            frames_.push_back(index);
        }
        first_time_ = source_.frameTime(options_.first);
        const auto& samples = source_.imuSamples();
        const double interval = samples.back().time -
                                samples[samples.size() - 2].time;
        if (first_time_ < samples.front().time ||
            source_.frameTime(frames_.back()) >
                samples.back().time + interval + 1e-6) {
            error = "Selected frames are outside the IMU time range";
            return false;
        }

        config.camera = {source_size.width * 0.5 * sx,
                         source_size.height * 0.5 * sy,
                         (source_size.width * 0.5 - region_.x) * sx,
                         (source_size.height * 0.5 - region_.y) * sy, 0.25};
        config.imu_pose = true;
        config.matcher = options_.matcher;
        config.disparities = disparities;
        config.block_size = block_size;
        config.max_depth_m = 20.0f;
        config.gravity = {0.0, 0.0, 9.8};  // world Z points down in TartanAir
        config.initial_pose = source_.poses()[options_.first];
        config.initial_velocity = source_.initialVelocity(first_time_);
        config.initial_time = first_time_;
        started_ = std::chrono::steady_clock::now();
        opened_ = true;
        return true;
    }

    Poll poll(mapping::StreamEvent& event, std::string& error) {
        if (!opened_) {
            error = "TartanAir replay is not open";
            return Poll::Error;
        }
        if (frame_index_ == frames_.size()) return Poll::Finished;
        const int frame_number = frames_[frame_index_];
        const double frame_time = source_.frameTime(frame_number);
        const auto& samples = source_.imuSamples();
        const bool next_is_imu = imu_index_ < samples.size() &&
                                 samples[imu_index_].time <= frame_time;
        const double next_time = next_is_imu ? samples[imu_index_].time : frame_time;
        const double elapsed = std::chrono::duration<double>(
            std::chrono::steady_clock::now() - started_).count();
        if (next_time - first_time_ > elapsed) return Poll::Waiting;
        if (next_is_imu) {
            event.kind = mapping::StreamEvent::Kind::Imu;
            event.imu = samples[imu_index_++];
        } else {
            event.kind = mapping::StreamEvent::Kind::Frame;
            event.frame_number = frame_number;
            event.frame = {};
            if (!source_.readFrame(frame_number, true, false,
                                   event.frame, error)) {
                return Poll::Error;
            }
            resize(event.frame.left, region_, options_.size, cv::INTER_AREA);
            resize(event.frame.right, region_, options_.size, cv::INTER_AREA);
            ++frame_index_;
        }
        return Poll::Ready;
    }

private:
    TartanAirSource source_;
    ReplayOptions options_;
    std::vector<int> frames_;
    cv::Rect region_;
    std::size_t frame_index_ = 0;
    std::size_t imu_index_ = 0;
    double first_time_ = 0.0;
    std::chrono::steady_clock::time_point started_;
    bool opened_ = false;
};

bool parseNumber(const char* text, int& value) {
    try {
        std::size_t end = 0;
        value = std::stoi(text, &end);
        return text[end] == '\0' && value >= 0;
    } catch (const std::exception&) {
        return false;
    }
}

bool parseSize(const std::string& text, cv::Size& size) {
    const auto separator = text.find('x');
    if (separator == std::string::npos) return false;
    int width, height;
    const std::string first = text.substr(0, separator);
    const std::string second = text.substr(separator + 1);
    if (!parseNumber(first.c_str(), width) ||
        !parseNumber(second.c_str(), height) || width == 0 || height == 0) {
        return false;
    }
    size = {width, height};
    return true;
}

bool parseArgs(int argc, char* argv[], std::filesystem::path& trajectory,
               ReplayOptions& options, std::string& error) {
    if (argc < 2 || argv[1][0] == '-') {
        error = "TartanAir feeder requires a trajectory directory";
        return false;
    }
    trajectory = argv[1];
    std::vector<const char*> frame_args;
    for (int i = 2; i < argc; ++i) {
        const std::string arg = argv[i];
        if (arg == "--size" && i + 1 < argc) {
            if (!parseSize(argv[++i], options.size)) {
                error = "--size requires positive WIDTHxHEIGHT";
                return false;
            }
        } else if (arg == "--matcher" && i + 1 < argc) {
            const std::string value = argv[++i];
            if (value != "bm" && value != "sgbm") {
                error = "--matcher requires bm or sgbm";
                return false;
            }
            options.matcher = value == "bm" ? stereo::MatcherAlgorithm::Bm
                                            : stereo::MatcherAlgorithm::Sgbm;
        } else if (arg.rfind("--", 0) == 0 || frame_args.size() == 3) {
            error = "Unexpected argument: " + arg;
            return false;
        } else {
            frame_args.push_back(argv[i]);
        }
    }
    if ((!frame_args.empty() && !parseNumber(frame_args[0], options.first)) ||
        (frame_args.size() > 1 && !parseNumber(frame_args[1], options.last)) ||
        (frame_args.size() > 2 && !parseNumber(frame_args[2], options.step))) {
        error = "Invalid frame range or step";
        return false;
    }
    if (frame_args.size() == 1) options.last = options.first;
    if (options.last < options.first || options.step == 0) {
        error = "Invalid frame range or step";
        return false;
    }
    return true;
}

}  // namespace

int main(int argc, char* argv[]) {
    ReplayOptions options;
    std::filesystem::path trajectory;
    std::string error;
    if (!parseArgs(argc, argv, trajectory, options, error)) {
        std::cerr << error << '\n';
        std::cerr << "Usage: " << argv[0]
                  << " <trajectory-directory> [first [last [step]]]"
                  << " [--size WIDTHxHEIGHT] [--matcher bm|sgbm]\n";
        return 1;
    }

    TartanAirReplay source(trajectory, options);
    mapping::Config config;
    if (!source.open(config, error)) {
        std::cerr << error << '\n';
        return 1;
    }
    if (!writeStreamHeader(std::cout, config, options.size)) {
        std::cerr << "Cannot write stream header\n";
        return 1;
    }
    std::cout.flush();

    mapping::StreamEvent event;
    for (;;) {
        const auto status = source.poll(event, error);
        if (status == TartanAirReplay::Poll::Finished) return 0;
        if (status == TartanAirReplay::Poll::Error) {
            std::cerr << error << '\n';
            return 1;
        }
        if (status == TartanAirReplay::Poll::Waiting) {
            std::this_thread::sleep_for(std::chrono::milliseconds(1));
            continue;
        }
        if (!writeStreamEvent(std::cout, event)) {
            std::cerr << "Cannot write stream event\n";
            return 1;
        }
        std::cout.flush();
        if (!std::cout) {
            std::cerr << "Cannot flush stream event\n";
            return 1;
        }
    }
}
