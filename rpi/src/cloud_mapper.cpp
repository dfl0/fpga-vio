#include "cloud_mapper.hpp"

#include <algorithm>
#include <cmath>
#include <stdexcept>
#include <utility>

#include <opencv2/imgproc.hpp>

namespace mapping {
namespace {

cv::Vec3d rotate(const cv::Vec4d& q, const cv::Vec3d& v) {
    const cv::Vec3d xyz(q[0], q[1], q[2]);
    const cv::Vec3d t = 2.0 * xyz.cross(v);
    return v + q[3] * t + xyz.cross(t);
}

cv::Vec4d multiply(const cv::Vec4d& a, const cv::Vec4d& b) {
    return {a[3] * b[0] + a[0] * b[3] + a[1] * b[2] - a[2] * b[1],
            a[3] * b[1] - a[0] * b[2] + a[1] * b[3] + a[2] * b[0],
            a[3] * b[2] + a[0] * b[1] - a[1] * b[0] + a[2] * b[3],
            a[3] * b[3] - a[0] * b[0] - a[1] * b[1] - a[2] * b[2]};
}

cv::Vec4d rotationStep(const cv::Vec3d& omega, double dt) {
    const double angle = cv::norm(omega) * dt;
    if (angle < 1e-12) {
        return {0.5 * omega[0] * dt, 0.5 * omega[1] * dt,
                0.5 * omega[2] * dt, 1.0};
    }
    const double scale = std::sin(angle / 2.0) * dt / angle;
    return {omega[0] * scale, omega[1] * scale, omega[2] * scale,
            std::cos(angle / 2.0)};
}

cv::Vec3d viewerCoordinates(const cv::Vec3d& local) {
    return {local[1], -local[2], -local[0]};
}

}  // namespace

std::array<float, 3> viewerPosition(const Pose& pose, const Pose& reference) {
    const cv::Vec4d inverse(-reference.quaternion[0], -reference.quaternion[1],
                             -reference.quaternion[2], reference.quaternion[3]);
    const cv::Vec3d point = viewerCoordinates(
        rotate(inverse, pose.position - reference.position));
    return {static_cast<float>(point[0]), static_cast<float>(point[1]),
            static_cast<float>(point[2])};
}

CloudMapper::CloudMapper(Config config)
    : config_(std::move(config)), pose_(config_.initial_pose),
      velocity_(config_.initial_velocity), time_(config_.initial_time) {}

void CloudMapper::integrate(const cv::Vec3d& first_acceleration,
                            const cv::Vec3d& last_acceleration,
                            const cv::Vec3d& first_gyro,
                            const cv::Vec3d& last_gyro, double dt) {
    if (dt <= 0.0) {
        return;
    }
    const cv::Vec3d mean_gyro = (first_gyro + last_gyro) * 0.5;
    cv::Vec4d next_quaternion = multiply(pose_.quaternion,
                                         rotationStep(mean_gyro, dt));
    next_quaternion /= cv::norm(next_quaternion);
    const cv::Vec3d first_world =
        rotate(pose_.quaternion, first_acceleration) + config_.gravity;
    const cv::Vec3d last_world =
        rotate(next_quaternion, last_acceleration) + config_.gravity;
    const cv::Vec3d mean_world = (first_world + last_world) * 0.5;
    pose_.position += velocity_ * dt + mean_world * (0.5 * dt * dt);
    velocity_ += mean_world * dt;
    pose_.quaternion = next_quaternion;
    time_ += dt;
}

void CloudMapper::processImu(ImuSample sample) {
    if (have_previous_ && sample.time <= previous_.time) {
        throw std::runtime_error("IMU timestamps must increase");
    }
    if (initializing()) {
        accel_sum_ += sample.acceleration;
        gyro_bias_ += sample.angular_velocity;
        ++startup_count_;
        previous_ = sample;
        have_previous_ = true;
        if (initializing()) return;
        config_.gravity = -rotate(pose_.quaternion, accel_sum_ / stationary_samples);
        gyro_bias_ /= stationary_samples;
        time_ = sample.time;
    }
    sample.angular_velocity -= gyro_bias_;
    if (config_.imu_pose && have_previous_ && sample.time > time_) {
        const double start = std::max(time_, previous_.time);
        const double fraction = (start - previous_.time) /
                                (sample.time - previous_.time);
        const cv::Vec3d acceleration = previous_.acceleration * (1.0 - fraction) +
                                       sample.acceleration * fraction;
        const cv::Vec3d gyro = previous_.angular_velocity * (1.0 - fraction) +
                               sample.angular_velocity * fraction;
        integrate(acceleration, sample.acceleration, gyro,
                  sample.angular_velocity, sample.time - start);
    }
    previous_ = sample;
    have_previous_ = true;
}

FrameResult CloudMapper::processFrame(const Frame& frame) {
    if (frame.left.empty() || frame.left.type() != CV_8UC3) {
        throw std::runtime_error("Frame requires an 8-bit color left image");
    }
    if (config_.imu_pose) {
        if (frame.time < time_ - 1e-9) {
            throw std::runtime_error("Frame timestamp precedes the current IMU pose");
        }
        if (frame.time > time_) {
            if (!have_previous_) {
                throw std::runtime_error("No IMU sample before frame timestamp");
            }
            integrate(previous_.acceleration, previous_.acceleration,
                      previous_.angular_velocity, previous_.angular_velocity,
                      frame.time - time_);
        }
    }

    FrameResult result;
    if (!config_.imu_pose && !frame.truth_pose) {
        throw std::runtime_error("Frame requires ground-truth pose in truth mode");
    }
    result.pose = config_.imu_pose ? pose_ : *frame.truth_pose;
    result.point_begin = points_.size();
    const int depth_sources = static_cast<int>(!frame.right.empty()) +
        static_cast<int>(!frame.disparity.empty()) +
        static_cast<int>(!frame.depth.empty());
    if (depth_sources != 1) {
        throw std::runtime_error("Frame requires exactly one depth source");
    }
    if (!frame.disparity.empty() || !frame.right.empty()) {
        if (!frame.disparity.empty()) {
            if (frame.disparity.type() != CV_32F ||
                frame.disparity.size() != frame.left.size()) {
                throw std::runtime_error("Frame requires matching float disparity");
            }
            result.disparity.pixels = frame.disparity;
            cv::compare(frame.disparity, 0.0, result.disparity.invalidMask,
                        cv::CMP_LE);
        } else {
            if (frame.right.size() != frame.left.size() ||
                (frame.right.type() != CV_8UC1 &&
                 frame.right.type() != CV_8UC3)) {
                throw std::runtime_error("Frame requires a matching right image");
            }
            cv::Mat left_gray, right_gray;
            cv::cvtColor(frame.left, left_gray, cv::COLOR_BGR2GRAY);
            if (frame.right.type() == CV_8UC1) {
                right_gray = frame.right;
            } else {
                cv::cvtColor(frame.right, right_gray, cv::COLOR_BGR2GRAY);
            }
            result.disparity = stereo::computeDisparity(
                left_gray, right_gray, stereo::ReferenceView::Left,
                config_.matcher, config_.disparities, config_.block_size);
        }
        result.depth = cv::Mat::zeros(frame.left.size(), CV_32F);
        for (int y = 0; y < result.depth.rows; ++y) {
            for (int x = 0; x < result.depth.cols; ++x) {
                if (result.disparity.invalidMask.at<unsigned char>(y, x)) {
                    continue;
                }
                const float disparity = result.disparity.pixels.at<float>(y, x);
                if (std::isfinite(disparity) && disparity > 0.0f) {
                    result.depth.at<float>(y, x) =
                        static_cast<float>(config_.camera.fx *
                                           config_.camera.baseline / disparity);
                }
            }
        }
    } else {
        if (frame.depth.type() != CV_32F ||
            frame.depth.size() != frame.left.size()) {
            throw std::runtime_error("Frame requires matching float depth");
        }
        result.depth = frame.depth;
    }

    const Pose& reference = config_.initial_pose;
    const cv::Vec4d inverse(-reference.quaternion[0], -reference.quaternion[1],
                             -reference.quaternion[2], reference.quaternion[3]);
    for (int y = 0; y < frame.left.rows; ++y) {
        for (int x = 0; x < frame.left.cols; ++x) {
            const float depth = result.depth.at<float>(y, x);
            if (!std::isfinite(depth) || depth <= 0.0f ||
                depth > config_.max_depth_m) {
                continue;
            }
            const cv::Vec3d camera(depth,
                (x - config_.camera.cx) * depth / config_.camera.fx,
                (y - config_.camera.cy) * depth / config_.camera.fy);
            const cv::Vec3d world =
                rotate(result.pose.quaternion, camera) + result.pose.position;
            const cv::Vec3d point = viewerCoordinates(
                rotate(inverse, world - reference.position));
            const cv::Vec3b bgr = frame.left.at<cv::Vec3b>(y, x);
            points_.push_back({static_cast<float>(point[0]),
                               static_cast<float>(point[1]),
                               static_cast<float>(point[2]),
                               bgr[2], bgr[1], bgr[0]});
        }
    }
    result.point_count = points_.size() - result.point_begin;
    return result;
}

}  // namespace mapping
