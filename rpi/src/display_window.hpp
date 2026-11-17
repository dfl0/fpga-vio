#pragma once

#include <algorithm>
#include <string>

#include <opencv2/core.hpp>
#include <opencv2/highgui.hpp>
#include <opencv2/imgproc.hpp>

inline void resizeForImagePixels(const std::string& name, cv::Size image_size) {
    cv::resizeWindow(name,
                     std::max(1, image_size.width),
                     std::max(1, image_size.height));
}

inline void drawImageLabel(cv::Mat& image, const std::string& text,
                           cv::Point origin, double scale = 0.8, int thickness = 1) {
    constexpr int font = cv::FONT_HERSHEY_SIMPLEX;
    CV_Assert(image.type() == CV_8UC3 && thickness > 0);
    int baseline = 0, unused_baseline = 0;
    const cv::Size font_size = cv::getTextSize("Ag", font, scale,
                                              thickness, &baseline);
    const int width = cv::getTextSize(text, font, scale,
                                      thickness, &unused_baseline).width;
    constexpr int padding = 2;
    cv::rectangle(image,
                  {origin.x - padding, origin.y - font_size.height - padding},
                  {origin.x + width + padding, origin.y + baseline + padding},
                  cv::Scalar(0, 0, 0), cv::FILLED);
    cv::putText(image, text, origin, font, scale,
                cv::Scalar(255, 255, 255), thickness, cv::LINE_AA);
}
