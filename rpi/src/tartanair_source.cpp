#include "tartanair_source.hpp"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <limits>
#include <sstream>
#include <utility>

#include <opencv2/imgcodecs.hpp>

namespace {

template <typename T>
bool readValues(const std::filesystem::path& path, std::vector<T>& values) {
    std::ifstream input(path);
    T value;
    while (input >> value) {
        values.push_back(value);
    }
    return input.eof() && !values.empty();
}

bool readVectors(const std::filesystem::path& path,
                 std::vector<cv::Vec3d>& values) {
    std::ifstream input(path);
    cv::Vec3d value;
    while (input >> value[0] >> value[1] >> value[2]) {
        if (!std::isfinite(value[0]) || !std::isfinite(value[1]) ||
            !std::isfinite(value[2])) {
            return false;
        }
        values.push_back(value);
    }
    return input.eof() && !values.empty();
}

bool readPoses(const std::filesystem::path& path,
               std::vector<mapping::Pose>& poses) {
    std::ifstream input(path);
    mapping::Pose pose;
    while (input >> pose.position[0] >> pose.position[1] >> pose.position[2]
                 >> pose.quaternion[0] >> pose.quaternion[1]
                 >> pose.quaternion[2] >> pose.quaternion[3]) {
        const double length = cv::norm(pose.quaternion);
        if (!std::isfinite(length) || length == 0.0) {
            return false;
        }
        pose.quaternion /= length;
        poses.push_back(pose);
    }
    return input.eof() && !poses.empty();
}

std::string frameNumber(int frame) {
    std::ostringstream number;
    number << std::setw(6) << std::setfill('0') << frame;
    return number.str();
}

float decodeDepth(const cv::Vec4b& bytes) {
    const std::uint32_t bits = static_cast<std::uint32_t>(bytes[0]) |
        (static_cast<std::uint32_t>(bytes[1]) << 8) |
        (static_cast<std::uint32_t>(bytes[2]) << 16) |
        (static_cast<std::uint32_t>(bytes[3]) << 24);
    float depth;
    std::memcpy(&depth, &bits, sizeof(depth));
    return depth;
}

}  // namespace

TartanAirSource::TartanAirSource(std::filesystem::path trajectory)
    : trajectory_(std::move(trajectory)) {}

bool TartanAirSource::open(bool include_imu, std::string& error) {
    static_assert(sizeof(float) == 4 && std::numeric_limits<float>::is_iec559,
                  "TartanAir depth requires IEEE-754 float32");
    const auto pose_path = trajectory_ / "pose_lcam_front.txt";
    if (!readPoses(pose_path, poses_)) {
        error = "Could not read camera poses: " + pose_path.string();
        return false;
    }
    const auto imu_dir = trajectory_ / "imu";
    if (!readValues(imu_dir / "cam_time.txt", camera_times_) ||
        camera_times_.size() < poses_.size()) {
        error = "Could not read matching camera timestamps";
        return false;
    }
    if (!std::isfinite(camera_times_.front())) {
        error = "Camera timestamps must be finite";
        return false;
    }
    for (std::size_t i = 1; i < camera_times_.size(); ++i) {
        if (!std::isfinite(camera_times_[i]) ||
            camera_times_[i] <= camera_times_[i - 1]) {
            error = "Camera timestamps must increase";
            return false;
        }
    }
    if (!include_imu) {
        return true;
    }

    std::vector<double> times;
    std::vector<cv::Vec3d> acceleration, gyro;
    if (!readValues(imu_dir / "imu_time.txt", times) ||
        !readVectors(imu_dir / "acc.txt", acceleration) ||
        !readVectors(imu_dir / "gyro.txt", gyro) ||
        !readVectors(imu_dir / "vel_global.txt", velocities_) ||
        times.size() < 2 || acceleration.size() != times.size() ||
        gyro.size() != times.size() || velocities_.size() != times.size()) {
        error = "Could not read matching IMU samples";
        return false;
    }
    for (std::size_t i = 0; i < times.size(); ++i) {
        if (!std::isfinite(times[i]) ||
            (i > 0 && times[i] <= times[i - 1])) {
            error = "IMU timestamps must increase";
            return false;
        }
        imu_samples_.push_back({times[i], acceleration[i], gyro[i]});
    }
    return true;
}

cv::Vec3d TartanAirSource::initialVelocity(double time) const {
    const auto upper = std::upper_bound(imu_samples_.begin(), imu_samples_.end(),
        time, [](double t, const mapping::ImuSample& sample) {
            return t < sample.time;
        });
    if (upper == imu_samples_.begin()) {
        return velocities_.front();
    }
    if (upper == imu_samples_.end()) {
        return velocities_.back();
    }
    const std::size_t index = static_cast<std::size_t>(upper - imu_samples_.begin());
    const double fraction = (time - imu_samples_[index - 1].time) /
        (imu_samples_[index].time - imu_samples_[index - 1].time);
    return velocities_[index - 1] * (1.0 - fraction) +
           velocities_[index] * fraction;
}

bool TartanAirSource::readFrame(int index, bool include_right,
                                 bool include_depth, mapping::Frame& frame,
                                 std::string& error) const {
    if (index < 0 || static_cast<std::size_t>(index) >= poses_.size()) {
        error = "Frame index exceeds the dataset trajectory";
        return false;
    }
    const std::string number = frameNumber(index);
    const auto left_path = trajectory_ / "image_lcam_front" /
        (number + "_lcam_front.png");
    frame.left = cv::imread(left_path.string(), cv::IMREAD_COLOR);
    if (frame.left.empty()) {
        error = "Could not read left image: " + left_path.string();
        return false;
    }
    if (include_right) {
        const auto right_path = trajectory_ / "image_rcam_front" /
            (number + "_rcam_front.png");
        frame.right = cv::imread(right_path.string(), cv::IMREAD_COLOR);
        if (frame.right.size() != frame.left.size()) {
            error = "Could not read matching right image: " + right_path.string();
            return false;
        }
    }
    if (include_depth) {
        const auto depth_path = trajectory_ / "depth_lcam_front" /
            (number + "_lcam_front_depth.png");
        const cv::Mat packed = cv::imread(depth_path.string(), cv::IMREAD_UNCHANGED);
        if (packed.type() != CV_8UC4 || packed.size() != frame.left.size()) {
            error = "Could not read matching packed depth: " + depth_path.string();
            return false;
        }
        frame.depth.create(packed.size(), CV_32F);
        for (int y = 0; y < packed.rows; ++y) {
            for (int x = 0; x < packed.cols; ++x) {
                frame.depth.at<float>(y, x) =
                    decodeDepth(packed.at<cv::Vec4b>(y, x));
            }
        }
    }
    frame.time = camera_times_[index];
    frame.truth_pose = poses_[index];
    return true;
}

bool TartanAirSource::stream(
    const std::vector<int>& frames, bool include_right, bool include_depth,
    const std::function<void(const mapping::ImuSample&)>& on_imu,
    const std::function<void(int, const mapping::Frame&)>& on_frame,
    std::string& error) const {
    std::size_t imu_index = 0;
    int previous_index = -1;
    for (int index : frames) {
        if (index <= previous_index || index < 0 ||
            static_cast<std::size_t>(index) >= poses_.size()) {
            error = "Frame indices must increase within the dataset trajectory";
            return false;
        }
        while (imu_index < imu_samples_.size() &&
               imu_samples_[imu_index].time <= camera_times_[index]) {
            on_imu(imu_samples_[imu_index++]);
        }
        mapping::Frame frame;
        if (!readFrame(index, include_right, include_depth, frame, error)) {
            return false;
        }
        on_frame(index, frame);
        previous_index = index;
    }
    return true;
}
