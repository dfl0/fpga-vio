#include <atomic>
#include <chrono>
#include <iostream>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "cloud_mapper.hpp"
#include "cloud_viewer.hpp"
#include "stdin_source.hpp"

namespace {

int runLiveMapping(StdinSource& source, mapping::Config config) {
    mapping::CloudMapper mapper(config);
    CloudViewer viewer;
    std::mutex mutex;
    std::atomic<bool> stop{false};
    std::vector<CloudViewer::FramePose> pending_frames;
    std::size_t processed_frames = 0;
    int imu_count = 0;
    bool finished = false, failed = false;
    std::string error;

    if (mapper.initializing())
        std::cerr << "Keep the IMU still for the first " << mapper.stationary_samples << " samples\n";
    viewer.open();
    std::thread worker([&]() {
        try {
            mapping::StreamEvent event;
            std::string source_error;
            while (!stop) {
                const auto status = source.poll(event, source_error);
                if (status == StdinSource::Poll::Waiting) {
                    std::this_thread::sleep_for(std::chrono::milliseconds(2));
                    continue;
                }
                if (status == StdinSource::Poll::Finished ||
                    status == StdinSource::Poll::Error) {
                    std::lock_guard<std::mutex> lock(mutex);
                    finished = status == StdinSource::Poll::Finished;
                    if (finished && mapper.initializing()) {
                        finished = false;
                        source_error = "Stream ended during stationary initialization";
                    }
                    failed = !finished;
                    error = source_error;
                    break;
                }

                std::lock_guard<std::mutex> lock(mutex);
                if (event.kind == mapping::StreamEvent::Kind::Imu) {
                    const bool initializing = mapper.initializing();
                    mapper.processImu(event.imu);
                    ++imu_count;
                    if (mapper.initializing()) continue;
                    if (initializing) std::cerr << "Stationary initialization complete; tracking motion\n";
                    if (source.imuOnly()) {
                        pending_frames.push_back({imu_count, mapping::viewerPosition(
                            mapper.pose(), config.initial_pose), std::nullopt});
                    }
                    continue;
                }
                if (mapper.initializing()) continue;
                const mapping::FrameResult result = mapper.processFrame(event.frame);
                CloudViewer::FramePose frame;
                frame.number = event.frame_number;
                frame.position = mapping::viewerPosition(result.pose,
                                                         config.initial_pose);
                if (config.imu_pose && event.frame.truth_pose) {
                    frame.truth_position = mapping::viewerPosition(
                        *event.frame.truth_pose, config.initial_pose);
                }
                pending_frames.push_back(frame);
                ++processed_frames;
            }
        } catch (const std::exception& exception) {
            std::lock_guard<std::mutex> lock(mutex);
            failed = true;
            error = exception.what();
        }
    });

    std::size_t displayed_points = 0;
    std::size_t viewer_updates = 0;
    bool reported = false, viewer_failed = false;
    const auto update_viewer = [&]() {
        try {
            std::vector<mapping::CloudPoint> new_points;
            std::vector<CloudViewer::FramePose> frames;
            bool stream_finished = false, stream_failed = false;
            std::size_t total_points = 0, frame_count = 0;
            int sample_count = 0;
            std::string stream_error;
            {
                std::unique_lock<std::mutex> lock(mutex, std::try_to_lock);
                if (!lock.owns_lock()) return;
                if (!pending_frames.empty()) {
                    const auto& points = mapper.points();
                    new_points.assign(points.begin() + displayed_points,
                                      points.end());
                    displayed_points = points.size();
                    frames.swap(pending_frames);
                }
                stream_finished = finished;
                stream_failed = failed;
                stream_error = error;
                total_points = mapper.points().size();
                frame_count = processed_frames;
                sample_count = imu_count;
            }
            if (!frames.empty()) {
                for (const auto& point : new_points) {
                    viewer.addPoint(point.x, point.y, point.z,
                                    point.red, point.green, point.blue);
                }
                viewer.appendFrames(viewer_updates++, frames, source.imuOnly());
            }
            if (stream_failed) {
                std::cerr << stream_error << '\n';
                reported = true;
                viewer.close();
            } else if (stream_finished && !reported) {
                if (source.imuOnly()) std::cout << "Stream finished: " << sample_count << " IMU samples.\n";
                else std::cout << "Stream finished: " << frame_count << " frames, "
                               << total_points << " points.\n";
                reported = true;
            }
        } catch (const std::exception& exception) {
            std::cerr << exception.what() << '\n';
            viewer_failed = true;
            stop = true;
            viewer.close();
        }
    };

    std::cout << "Press q or Esc in the cloud window to close.\n";
    viewer.runInteractive(
        [&](const std::string& key) {
            if (key == "q" || key == "Q" || key == "Escape") viewer.close();
        }, update_viewer);
    stop = true;
    worker.join();
    if (!reported) {
        if (failed) {
            std::cerr << error << '\n';
        } else if (finished) {
            std::cout << "Stream finished: " << processed_frames << " frames, "
                      << mapper.points().size() << " points.\n";
        }
    }
    return failed || viewer_failed ? 1 : 0;
}

}  // namespace

int main(int argc, char* argv[]) {
    bool stationary_start = false;
    for (int i = 1; i < argc; ++i) {
        const std::string arg = argv[i];
        if (arg == "--stationary-start") stationary_start = true;
        else if (arg == "--source" && i + 1 < argc && std::string(argv[i + 1]) == "stdin") ++i;
        else {
            std::cerr << "Usage: live_mapper [--source stdin] [--stationary-start] < data-stream\n";
            return 1;
        }
    }

    StdinSource source;
    mapping::Config config;
    std::string error;
    if (!source.open(config, error)) {
        std::cerr << error << '\n';
        return 1;
    }
    if (stationary_start) {
        config.stationary_start = true;
        config.initial_pose = {};
        config.initial_velocity = {};
    }
    return runLiveMapping(source, config);
}
