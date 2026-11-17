#pragma once

#include <array>
#include <cstddef>
#include <optional>
#include <vector>

#include <opencv2/core.hpp>

#include "stereo_matcher.hpp"

namespace mapping {

struct Pose {
    cv::Vec3d position{0.0, 0.0, 0.0};
    cv::Vec4d quaternion{0.0, 0.0, 0.0, 1.0};  // x, y, z, w; camera-to-world
};

struct ImuSample {
    double time;  // sample time in seconds on the shared acquisition clock
    cv::Vec3d acceleration;
    cv::Vec3d angular_velocity;
};

struct Frame {
    double time;  // stereo capture time in seconds on the shared acquisition clock
    cv::Mat left;
    // supply one depth source: right image, disparity, or depth map
    cv::Mat right;
    cv::Mat disparity;
    cv::Mat depth;
    std::optional<Pose> truth_pose;
};

struct StereoGeometry {
    double fx, fy, cx, cy;
    double baseline;
};

struct CloudPoint {
    float x, y, z;
    unsigned char red, green, blue;
};

struct Config {
    StereoGeometry camera;
    bool imu_pose = false;
    stereo::MatcherAlgorithm matcher = stereo::MatcherAlgorithm::Bm;
    int disparities = 64;
    int block_size = 15;
    float max_depth_m = 20.0f;
    cv::Vec3d gravity{0.0, 0.0, 0.0};  // m/s² in fixed map axes
    Pose initial_pose;
    cv::Vec3d initial_velocity;
    double initial_time = 0.0;
};

struct FrameResult {
    Pose pose;
    cv::Mat depth;
    stereo::DisparityResult disparity;
    std::size_t point_begin = 0;
    std::size_t point_count = 0;
};

std::array<float, 3> viewerPosition(const Pose& pose, const Pose& reference);

class CloudMapper {
public:
    explicit CloudMapper(Config config);

    void processImu(const ImuSample& sample);
    FrameResult processFrame(const Frame& frame);
    const std::vector<CloudPoint>& points() const { return points_; }

private:
    void integrate(const cv::Vec3d& first_acceleration,
                   const cv::Vec3d& last_acceleration,
                   const cv::Vec3d& first_gyro,
                   const cv::Vec3d& last_gyro, double dt);

    Config config_;
    Pose pose_;
    cv::Vec3d velocity_;
    double time_;
    ImuSample previous_{};
    bool have_previous_ = false;
    std::vector<CloudPoint> points_;
};

}  // namespace mapping
