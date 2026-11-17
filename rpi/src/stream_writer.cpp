#include "stream_writer.hpp"

#include <iomanip>
#include <ostream>

#include <opencv2/imgproc.hpp>

bool writeStreamHeader(std::ostream& out, const mapping::Config& config,
                       cv::Size image_size) {
    const auto& c = config.camera;
    const auto& p = config.initial_pose;
    const auto& v = config.initial_velocity;
    const auto& g = config.gravity;
    out << std::setprecision(17)
        << "FVIO_STREAM 1 " << image_size.width << ' ' << image_size.height
        << ' ' << c.fx << ' ' << c.fy << ' ' << c.cx << ' ' << c.cy
        << ' ' << c.baseline
        << ' ' << g[0] << ' ' << g[1] << ' ' << g[2]
        << ' ' << p.position[0] << ' ' << p.position[1] << ' ' << p.position[2]
        << ' ' << p.quaternion[0] << ' ' << p.quaternion[1]
        << ' ' << p.quaternion[2] << ' ' << p.quaternion[3]
        << ' ' << v[0] << ' ' << v[1] << ' ' << v[2]
        << ' ' << config.initial_time << ' ' << config.max_depth_m
        << ' ' << config.disparities << ' ' << config.block_size
        << ' ' << static_cast<int>(config.matcher) << '\n';
    return static_cast<bool>(out);
}

bool writeStreamEvent(std::ostream& out, const mapping::StreamEvent& event) {
    out << std::setprecision(17);
    if (event.kind == mapping::StreamEvent::Kind::Imu) {
        const auto& s = event.imu;
        out << "I " << s.time
            << ' ' << s.acceleration[0] << ' ' << s.acceleration[1]
            << ' ' << s.acceleration[2]
            << ' ' << s.angular_velocity[0] << ' ' << s.angular_velocity[1]
            << ' ' << s.angular_velocity[2] << '\n';
        return static_cast<bool>(out);
    }

    const auto& frame = event.frame;
    if (frame.left.empty() || frame.left.type() != CV_8UC3 ||
        frame.right.empty() || frame.right.size() != frame.left.size() ||
        (frame.right.type() != CV_8UC1 && frame.right.type() != CV_8UC3)) {
        return false;
    }
    cv::Mat right_gray;
    if (frame.right.type() == CV_8UC1) {
        right_gray = frame.right;
    } else {
        cv::cvtColor(frame.right, right_gray, cv::COLOR_BGR2GRAY);
    }
    const cv::Mat left = frame.left.isContinuous() ? frame.left
                                                  : frame.left.clone();
    if (!right_gray.isContinuous()) right_gray = right_gray.clone();
    out << "F " << event.frame_number << ' ' << frame.time << '\n';
    out.write(reinterpret_cast<const char*>(left.data),
              static_cast<std::streamsize>(left.total() * left.elemSize()));
    out.write(reinterpret_cast<const char*>(right_gray.data),
              static_cast<std::streamsize>(right_gray.total()));
    return static_cast<bool>(out);
}
