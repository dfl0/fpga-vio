#pragma once

#include <array>
#include <cstddef>
#include <functional>
#include <optional>
#include <string>
#include <vector>
#include <vtkSmartPointer.h>

class vtkActor;
class vtkCellArray;
class vtkPoints;
class vtkPolyData;
class vtkRenderWindow;
class vtkRenderWindowInteractor;
class vtkRenderer;
class vtkUnsignedCharArray;

class CloudViewer {
public:
    struct FramePose {
        int number = 0;
        std::array<float, 3> position{};
        std::optional<std::array<float, 3>> truth_position;
    };

    CloudViewer();

    void addPoint(float x, float y, float z,
                  unsigned char red, unsigned char green, unsigned char blue);
    void finishFrame();
    void appendFrames(std::size_t batch, const std::vector<FramePose>& frames,
                      bool imu_only = false);
    void setTrajectories(std::vector<std::array<float, 3>> active,
                         std::vector<std::array<float, 3>> truth = {});
    void showThroughFrame(std::size_t index, int frame);
    void open();
    void runInteractive(std::function<void(const std::string&)> on_key,
                        std::function<void()> on_tick);
    void close();
    void waitUntilClosed();

private:
    struct Trajectory {
        std::vector<std::array<float, 3>> positions;
        vtkSmartPointer<vtkPoints> points;
        vtkSmartPointer<vtkCellArray> lines;
        vtkSmartPointer<vtkPolyData> data;
        vtkSmartPointer<vtkActor> actor;
    };

    void makeTrajectory(Trajectory& trajectory,
                        std::vector<std::array<float, 3>> positions,
                        double red, double green, double blue);
    void showTrajectory(Trajectory& trajectory, std::size_t index);
    void showThroughFrameAt(std::size_t actor_index,
                            std::size_t pose_index, int frame, bool imu_only = false);

    vtkSmartPointer<vtkPoints> points_;
    vtkSmartPointer<vtkCellArray> vertices_;
    vtkSmartPointer<vtkUnsignedCharArray> colors_;
    std::vector<vtkSmartPointer<vtkActor>> actors_;
    Trajectory active_trajectory_;
    Trajectory truth_trajectory_;
    vtkSmartPointer<vtkPoints> marker_points_;
    vtkSmartPointer<vtkRenderer> renderer_;
    vtkSmartPointer<vtkRenderWindow> window_;
    vtkSmartPointer<vtkRenderWindowInteractor> interactor_;
    bool window_open_ = false;
    bool camera_set_ = false;
};
