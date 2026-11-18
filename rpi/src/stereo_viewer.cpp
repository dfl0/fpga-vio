#include <algorithm>
#include <cmath>
#include <cstddef>
#include <iostream>
#include <string>
#include <vector>

#include <opencv2/core.hpp>
#include <opencv2/highgui.hpp>
#include <opencv2/imgcodecs.hpp>
#include <opencv2/imgproc.hpp>

#include "display_window.hpp"
#include "stereo_matcher.hpp"

namespace {

constexpr char kPairWindowName[] = "Stereo input pair";
constexpr char kDisparityWindowName[] = "Computed disparity";

using stereo::computeDisparity;
using stereo::colorizeDisparity;
using stereo::DisparityResult;
using stereo::kMinDisparity;
using stereo::kNumDisparities;
using stereo::MatcherAlgorithm;
using stereo::ReferenceView;

const char* viewName(ReferenceView view) {
    return view == ReferenceView::Left ? "Left" : "Right";
}

const char* matcherName(MatcherAlgorithm algorithm) {
    return algorithm == MatcherAlgorithm::Sgbm ? "StereoSGBM" : "StereoBM";
}

void printUsage(const char* executable) {
    std::cerr << "Usage: " << executable
              << " <left-image> <right-image>"
              << " [ground-truth-disparity.pgm]"
              << " [--gt-view left|right] [--matcher sgbm|bm]\n"
              << "Ground truth must match the selected view (default: right)\n";
}

}  // namespace

int main(int argc, char* argv[]) {
    if (argc == 2 &&
        (std::string(argv[1]) == "--help" ||
         std::string(argv[1]) == "-h")) {
        printUsage(argv[0]);
        return 0;
    }

    ReferenceView groundTruthView = ReferenceView::Right;
    MatcherAlgorithm algorithm = MatcherAlgorithm::Sgbm;
    std::vector<std::string> paths;
    for (int i = 1; i < argc; ++i) {
        const std::string arg = argv[i];
        if (arg == "--gt-view") {
            if (++i >= argc ||
                (std::string(argv[i]) != "left" && std::string(argv[i]) != "right")) {
                std::cerr << "--gt-view requires left or right\n";
                printUsage(argv[0]);
                return 2;
            }
            groundTruthView = std::string(argv[i]) == "left"
                ? ReferenceView::Left : ReferenceView::Right;
        } else if (arg == "--matcher") {
            if (++i >= argc ||
                (std::string(argv[i]) != "sgbm" && std::string(argv[i]) != "bm")) {
                std::cerr << "--matcher requires sgbm or bm\n";
                printUsage(argv[0]);
                return 2;
            }
            algorithm = std::string(argv[i]) == "sgbm"
                ? MatcherAlgorithm::Sgbm : MatcherAlgorithm::Bm;
        } else if (arg.rfind("--", 0) == 0) {
            std::cerr << "Unknown option: " << arg << '\n';
            printUsage(argv[0]);
            return 2;
        } else {
            paths.push_back(arg);
        }
    }
    if (paths.size() != 2 && paths.size() != 3) {
        printUsage(argv[0]);
        return 2;
    }

    const std::string& leftPath = paths[0];
    const std::string& rightPath = paths[1];
    const bool validate = paths.size() == 3;
    const std::string groundTruthPath = validate ? paths[2] : "";

    const cv::Mat left =
        cv::imread(leftPath, cv::IMREAD_COLOR);
    const cv::Mat right =
        cv::imread(rightPath, cv::IMREAD_COLOR);

    if (left.empty()) {
        std::cerr << "Could not load left image: "
                  << leftPath << '\n';
        return 1;
    }

    if (right.empty()) {
        std::cerr << "Could not load right image: "
                  << rightPath << '\n';
        return 1;
    }

    if (left.size() != right.size()) {
        std::cerr << "Left and right images must have the same dimensions\n";
        return 1;
    }

    std::cout << "Image dimensions: "
              << left.cols << 'x' << left.rows << '\n';

    cv::Mat leftGray;
    cv::Mat rightGray;

    cv::cvtColor(left, leftGray, cv::COLOR_BGR2GRAY);
    cv::cvtColor(right, rightGray, cv::COLOR_BGR2GRAY);

    const DisparityResult leftDisparity = computeDisparity(
        leftGray, rightGray, ReferenceView::Left, algorithm
    );
    const cv::Mat disparityColor = colorizeDisparity(leftDisparity);

    cv::Mat gtColor;
    cv::Mat errorColor;

    if (validate) {
        const cv::Mat gtRaw = cv::imread(
                groundTruthPath,
                cv::IMREAD_UNCHANGED
                );

        if (gtRaw.empty()) {
            std::cerr << "Could not load ground truth: "
                << groundTruthPath << '\n';
            return 1;
        }

        if (gtRaw.size() != left.size()) {
            std::cerr << "Ground truth dimensions do not match stereo images\n";
            return 1;
        }

        if (gtRaw.type() != CV_8UC1) {
            std::cerr << "Expected an 8-bit grayscale ground-truth PGM image\n";
            return 1;
        }

        const DisparityResult prediction = groundTruthView == ReferenceView::Left
            ? leftDisparity
            : computeDisparity(leftGray, rightGray, groundTruthView, algorithm);
        const cv::Mat predictionColor = colorizeDisparity(prediction);

        constexpr float focalLengthPixels = 615.0f;
        constexpr float baselineMeters = 0.10f;

        cv::Mat depth = cv::Mat::zeros(
            prediction.pixels.size(),
            CV_32F
        );

        for (int y = 0; y < prediction.pixels.rows; ++y) {
            for (int x = 0; x < prediction.pixels.cols; ++x) {
                const float d = prediction.pixels.at<float>(y, x);

                if (d > 0.0f && prediction.invalidMask.at<unsigned char>(y, x) == 0) {
                    depth.at<float>(y, x) =
                        focalLengthPixels * baselineMeters / d;
                }
            }
        }

        cv::Mat depthDisplay;

        // map 0 to 8 m to reversed 8-bit intensity for display
        depth.convertTo(depthDisplay, CV_8U, -255.0 / 8, 255.0);

        cv::Mat depthColor;
        cv::applyColorMap(
            depthDisplay,
            depthColor,
            cv::COLORMAP_MAGMA
        );

        cv::Mat invalidDepthMask;
        cv::compare(depth, 0.0f, invalidDepthMask, cv::CMP_LE);
        cv::bitwise_or(invalidDepthMask, depth > 10.0f, invalidDepthMask);
        depthColor.setTo(cv::Scalar(0, 0, 0), invalidDepthMask);

        // Tsukuba disparity is scaled by 8; zero is invalid
        cv::Mat gtInvalidMask;
        cv::compare(
                gtRaw,
                cv::Scalar(0),
                gtInvalidMask,
                cv::CMP_EQ
                );

        cv::Mat gtGray;
        gtRaw.convertTo(
            gtGray,
            CV_8U,
            255.0 / (8.0 * kNumDisparities)
        );

        cv::applyColorMap(gtGray, gtColor, cv::COLORMAP_TURBO);
        gtColor.setTo(cv::Scalar(0, 0, 0), gtInvalidMask);

        // saturate displayed absolute error at 4 pixels
        constexpr float kBadPixelThreshold = 1.0f;
        constexpr float kErrorDisplayRange = 4.0f;

        cv::Mat errorGray = cv::Mat::zeros(gtRaw.size(), CV_8UC1);

        std::size_t gtValidPixels = 0;
        std::size_t predictedValidPixels = 0;
        std::size_t badPixels = 0;
        double absoluteErrorSum = 0.0;

        for (int y = 0; y < gtRaw.rows; ++y) {
            for (int x = 0; x < gtRaw.cols; ++x) {
                const unsigned char gtCode =
                    gtRaw.at<unsigned char>(y, x);

                if (gtCode == 0) {
                    continue;
                }

                ++gtValidPixels;

                if (prediction.invalidMask.at<unsigned char>(y, x) != 0) {
                    // missing predictions count as bad pixels
                    ++badPixels;
                    errorGray.at<unsigned char>(y, x) = 255;
                    continue;
                }

                const float estimatedDisparity =
                    prediction.pixels.at<float>(y, x);

                const float trueDisparity =
                    static_cast<float>(gtCode) / 8.0f;

                const float error = std::abs(
                        estimatedDisparity - trueDisparity
                        );

                ++predictedValidPixels;
                absoluteErrorSum += error;

                if (error > kBadPixelThreshold) {
                    ++badPixels;
                }

                errorGray.at<unsigned char>(y, x) =
                    cv::saturate_cast<unsigned char>(
                            std::min(
                                error / kErrorDisplayRange,
                                1.0f
                                ) * 255.0f
                            );
            }
        }

        cv::applyColorMap(errorGray, errorColor, cv::COLORMAP_TURBO);

        errorColor.setTo(cv::Scalar(0, 0, 0), gtInvalidMask);

        std::cout << "\nDisparity validation\n"
            << "Reference view: " << viewName(groundTruthView) << '\n'
            << "Valid GT pixels: " << gtValidPixels << '\n'
            << "Valid predictions: " << predictedValidPixels << '\n';

        if (gtValidPixels > 0) {
            const double coverage =
                100.0 * predictedValidPixels / gtValidPixels;

            const double badPixelRate =
                100.0 * badPixels / gtValidPixels;

            std::cout << "Prediction coverage: "
                << coverage << "%\n"
                << "Bad pixels (error > 1 px or invalid): "
                << badPixelRate << "%\n";
        }

        if (predictedValidPixels > 0) {
            const double meanAbsoluteError =
                absoluteErrorSum / predictedValidPixels;

            std::cout << "Mean absolute error (valid predictions): "
                << meanAbsoluteError << " pixels\n";
        }

        const std::string predictionWindow =
            std::string(viewName(groundTruthView)) + "-view estimated disparity";
        cv::namedWindow("Ground-truth disparity", cv::WINDOW_NORMAL);
        cv::namedWindow(predictionWindow, cv::WINDOW_NORMAL);
        cv::namedWindow("Absolute disparity error", cv::WINDOW_NORMAL);
        cv::namedWindow("Depth map (meters)", cv::WINDOW_NORMAL);

        cv::imshow("Ground-truth disparity", gtColor);
        cv::imshow(predictionWindow, predictionColor);
        cv::imshow("Absolute disparity error", errorColor);
        cv::imshow("Depth map (meters)", depthColor);
        resizeForImagePixels("Ground-truth disparity", gtColor.size());
        resizeForImagePixels(predictionWindow, predictionColor.size());
        resizeForImagePixels("Absolute disparity error", errorColor.size());
        resizeForImagePixels("Depth map (meters)", depthColor.size());
    }

    cv::Mat pairDisplay;
    cv::hconcat(left, right, pairDisplay);
    drawImageLabel(pairDisplay, "Left", {12, 36});
    drawImageLabel(pairDisplay, "Right", {left.cols + 12, 36});

    cv::namedWindow(kPairWindowName, cv::WINDOW_NORMAL);
    cv::namedWindow(kDisparityWindowName, cv::WINDOW_NORMAL);
    cv::imshow(kPairWindowName, pairDisplay);
    cv::imshow(kDisparityWindowName, disparityColor);
    resizeForImagePixels(kPairWindowName, pairDisplay.size());
    resizeForImagePixels(kDisparityWindowName, disparityColor.size());

    std::cout
        << "Disparity computed using " << matcherName(algorithm) << ".\n"
        << "Minimum disparity: " << kMinDisparity << '\n'
        << "Disparity search range: " << kNumDisparities
        << " pixels\n"
        << "Press any key while an image window is focused to exit.\n";

    cv::waitKey(0);
    cv::destroyAllWindows();

    return 0;
}
