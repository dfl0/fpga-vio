#pragma once

#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/core/version.hpp>
#if CV_VERSION_MAJOR >= 5
#include <opencv2/stereo.hpp>
#else
#include <opencv2/calib3d.hpp>
#endif

namespace stereo {

constexpr int kMinDisparity = 0;
constexpr int kNumDisparities = 64;
constexpr int kSgbmBlockSize = 5;
constexpr int kBmBlockSize = 15;

enum class ReferenceView { Left, Right };
enum class MatcherAlgorithm { Sgbm, Bm };

struct DisparityResult {
    cv::Mat pixels;       // positive disparity in pixels
    cv::Mat invalidMask;  // nonzero marks invalid pixels
};

inline DisparityResult computeDisparity(
    const cv::Mat& leftGray,
    const cv::Mat& rightGray,
    ReferenceView view,
    MatcherAlgorithm algorithm,
    int numDisparities = kNumDisparities,
    int blockSize = 0
) {
    const bool isLeft = view == ReferenceView::Left;
    const int minDisparity = isLeft
        ? kMinDisparity : -kMinDisparity - numDisparities;
    const cv::Mat& reference = isLeft ? leftGray : rightGray;
    const cv::Mat& other = isLeft ? rightGray : leftGray;
    cv::Ptr<cv::StereoMatcher> matcher;
    if (algorithm == MatcherAlgorithm::Sgbm) {
        const int size = blockSize ? blockSize : kSgbmBlockSize;
        auto sgbm = cv::StereoSGBM::create(
            minDisparity, numDisparities, size
        );
        sgbm->setP1(8 * reference.channels() * size * size);
        sgbm->setP2(32 * reference.channels() * size * size);
        sgbm->setPreFilterCap(31);
        sgbm->setUniquenessRatio(10);
        matcher = sgbm;
    } else {
        auto bm = cv::StereoBM::create(numDisparities,
                                       blockSize ? blockSize : kBmBlockSize);
        bm->setMinDisparity(minDisparity);
        bm->setPreFilterCap(31);
        bm->setUniquenessRatio(10);
        matcher = bm;
    }
    matcher->setDisp12MaxDiff(1);
    matcher->setSpeckleWindowSize(100);
    matcher->setSpeckleRange(2);

    cv::Mat raw;
    matcher->compute(reference, other, raw);

    DisparityResult result;
    cv::compare(raw, (minDisparity - 1) * 16,
                result.invalidMask, cv::CMP_LE);
    raw.convertTo(result.pixels, CV_32F, (isLeft ? 1.0 : -1.0) / 16.0);
    return result;
}

inline cv::Mat colorizeDisparity(const DisparityResult& disparity,
                                int numDisparities = kNumDisparities) {
    cv::Mat gray;
    const double scale = 255.0 / numDisparities;
    disparity.pixels.convertTo(gray, CV_8U, scale, -kMinDisparity * scale);
    cv::Mat color;
    cv::applyColorMap(gray, color, cv::COLORMAP_TURBO);
    color.setTo(cv::Scalar(0, 0, 0), disparity.invalidMask);
    return color;
}

}  // namespace stereo
