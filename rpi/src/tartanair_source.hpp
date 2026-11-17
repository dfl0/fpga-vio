#pragma once

#include <filesystem>
#include <functional>
#include <string>
#include <vector>

#include <opencv2/core.hpp>

#include "cloud_mapper.hpp"

class TartanAirSource {
public:
    explicit TartanAirSource(std::filesystem::path trajectory);

    bool open(bool include_imu, std::string& error);
    bool readFrame(int index, bool include_right, bool include_depth,
                   mapping::Frame& frame, std::string& error) const;
    bool stream(const std::vector<int>& frames, bool include_right,
                bool include_depth,
                const std::function<void(const mapping::ImuSample&)>& on_imu,
                const std::function<void(int, const mapping::Frame&)>& on_frame,
                std::string& error) const;

    const std::vector<mapping::Pose>& poses() const { return poses_; }
    const std::vector<mapping::ImuSample>& imuSamples() const { return imu_samples_; }
    cv::Vec3d initialVelocity(double time) const;
    double frameTime(int index) const { return camera_times_.at(index); }

private:
    std::filesystem::path trajectory_;
    std::vector<mapping::Pose> poses_;
    std::vector<double> camera_times_;
    std::vector<mapping::ImuSample> imu_samples_;
    std::vector<cv::Vec3d> velocities_;
};
