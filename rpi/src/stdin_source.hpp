#pragma once

#include <cstddef>
#include <string>

#include "stream_event.hpp"

class StdinSource {
public:
    enum class Poll { Ready, Waiting, Finished, Error };

    ~StdinSource();
    bool open(mapping::Config& config, std::string& error);
    Poll poll(mapping::StreamEvent& event, std::string& error);

private:
    int original_flags_ = -1;
    int width_ = 0;
    int height_ = 0;
    std::size_t image_bytes_ = 0;
    std::string buffer_;
    bool eof_ = false;
    bool frame_pending_ = false;
    int pending_frame_number_ = 0;
    double pending_frame_time_ = 0.0;
};
