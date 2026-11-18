#pragma once

#include <iosfwd>

#include "stream_event.hpp"

// local pipe format uses text headers and raw left BGR8/right GRAY8 bytes
bool writeImuStreamHeader(std::ostream& out);
bool writeStreamHeader(std::ostream& out, const mapping::Config& config,
                       cv::Size image_size);
bool writeStreamEvent(std::ostream& out, const mapping::StreamEvent& event);
