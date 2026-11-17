#pragma once

#include "cloud_mapper.hpp"

namespace mapping {

struct StreamEvent {
    enum class Kind { Imu, Frame } kind;
    ImuSample imu{};
    Frame frame{};
    int frame_number = 0;
};

}  // namespace mapping
