#include "cloud_viewer.hpp"

#include <algorithm>
#include <string>
#include <utility>

#include <vtkActor.h>
#include <vtkCallbackCommand.h>
#include <vtkCellArray.h>
#include <vtkCommand.h>
#include <vtkInteractorStyleTrackballCamera.h>
#include <vtkPointData.h>
#include <vtkPoints.h>
#include <vtkPolyData.h>
#include <vtkPolyDataMapper.h>
#include <vtkProperty.h>
#include <vtkRenderWindow.h>
#include <vtkRenderWindowInteractor.h>
#include <vtkRenderer.h>
#include <vtkUnsignedCharArray.h>

CloudViewer::CloudViewer()
    : points_(vtkSmartPointer<vtkPoints>::New()),
      vertices_(vtkSmartPointer<vtkCellArray>::New()),
      colors_(vtkSmartPointer<vtkUnsignedCharArray>::New()),
      renderer_(vtkSmartPointer<vtkRenderer>::New()),
      window_(vtkSmartPointer<vtkRenderWindow>::New()),
      interactor_(vtkSmartPointer<vtkRenderWindowInteractor>::New()) {
    points_->SetDataTypeToFloat();
    colors_->SetNumberOfComponents(3);
    colors_->SetName("RGB");
    renderer_->SetBackground(0.08, 0.08, 0.10);

    window_->AddRenderer(renderer_);
    window_->SetWindowName("Growing point cloud");
    window_->SetSize(1000, 750);
    interactor_->SetRenderWindow(window_);
    interactor_->SetInteractorStyle(
        vtkSmartPointer<vtkInteractorStyleTrackballCamera>::New());
}

void CloudViewer::addPoint(float x, float y, float z,
                           unsigned char red, unsigned char green,
                           unsigned char blue) {
    const vtkIdType id = points_->InsertNextPoint(x, y, z);
    vertices_->InsertNextCell(1);
    vertices_->InsertCellPoint(id);
    colors_->InsertNextTuple3(red, green, blue);
}

void CloudViewer::finishFrame() {
    auto cloud = vtkSmartPointer<vtkPolyData>::New();
    cloud->SetPoints(points_);
    cloud->SetVerts(vertices_);
    cloud->GetPointData()->SetScalars(colors_);
    auto mapper = vtkSmartPointer<vtkPolyDataMapper>::New();
    mapper->SetInputData(cloud);
    mapper->SetColorModeToDirectScalars();
    auto actor = vtkSmartPointer<vtkActor>::New();
    actor->SetMapper(mapper);
    actor->GetProperty()->SetPointSize(2);
    actor->VisibilityOff();
    renderer_->AddActor(actor);
    actors_.push_back(actor);

    points_ = vtkSmartPointer<vtkPoints>::New();
    points_->SetDataTypeToFloat();
    vertices_ = vtkSmartPointer<vtkCellArray>::New();
    colors_ = vtkSmartPointer<vtkUnsignedCharArray>::New();
    colors_->SetNumberOfComponents(3);
    colors_->SetName("RGB");
}

void CloudViewer::appendFrames(
    std::size_t batch, const std::vector<FramePose>& frames) {
    if (frames.empty()) return;
    for (const auto& frame : frames) {
        if (!active_trajectory_.actor) {
            setTrajectories({frame.position}, frame.truth_position
                ? std::vector<std::array<float, 3>>{*frame.truth_position}
                : std::vector<std::array<float, 3>>{});
        } else {
            active_trajectory_.positions.push_back(frame.position);
            if (frame.truth_position) {
                truth_trajectory_.positions.push_back(*frame.truth_position);
            }
        }
    }
    finishFrame();
    showThroughFrameAt(batch, active_trajectory_.positions.size() - 1,
                       frames.back().number);
}

void CloudViewer::makeTrajectory(
    Trajectory& trajectory, std::vector<std::array<float, 3>> positions,
    double red, double green, double blue) {
    if (positions.empty()) {
        return;
    }
    trajectory.positions = std::move(positions);
    trajectory.points = vtkSmartPointer<vtkPoints>::New();
    trajectory.points->SetDataTypeToFloat();
    trajectory.lines = vtkSmartPointer<vtkCellArray>::New();
    trajectory.data = vtkSmartPointer<vtkPolyData>::New();
    trajectory.data->SetPoints(trajectory.points);
    trajectory.data->SetLines(trajectory.lines);
    auto mapper = vtkSmartPointer<vtkPolyDataMapper>::New();
    mapper->SetInputData(trajectory.data);
    mapper->ScalarVisibilityOff();
    trajectory.actor = vtkSmartPointer<vtkActor>::New();
    trajectory.actor->SetMapper(mapper);
    trajectory.actor->GetProperty()->SetColor(red, green, blue);
    trajectory.actor->GetProperty()->SetLineWidth(3);
    trajectory.actor->SetUseBounds(false);
    renderer_->AddActor(trajectory.actor);
}

void CloudViewer::setTrajectories(
    std::vector<std::array<float, 3>> active,
    std::vector<std::array<float, 3>> truth) {
    makeTrajectory(active_trajectory_, std::move(active), 1.0, 0.75, 0.1);
    makeTrajectory(truth_trajectory_, std::move(truth), 0.1, 0.85, 1.0);

    if (!active_trajectory_.positions.empty()) {
        marker_points_ = vtkSmartPointer<vtkPoints>::New();
        marker_points_->SetDataTypeToFloat();
        const auto& first = active_trajectory_.positions.front();
        marker_points_->InsertNextPoint(first[0], first[1], first[2]);
        auto vertices = vtkSmartPointer<vtkCellArray>::New();
        vertices->InsertNextCell(1);
        vertices->InsertCellPoint(0);
        auto marker = vtkSmartPointer<vtkPolyData>::New();
        marker->SetPoints(marker_points_);
        marker->SetVerts(vertices);
        auto mapper = vtkSmartPointer<vtkPolyDataMapper>::New();
        mapper->SetInputData(marker);
        mapper->ScalarVisibilityOff();
        auto actor = vtkSmartPointer<vtkActor>::New();
        actor->SetMapper(mapper);
        actor->GetProperty()->SetColor(1.0, 1.0, 1.0);
        actor->GetProperty()->SetPointSize(10);
        actor->SetUseBounds(false);
        renderer_->AddActor(actor);
    }
}

void CloudViewer::showTrajectory(Trajectory& trajectory, std::size_t index) {
    if (trajectory.positions.empty()) {
        return;
    }
    index = std::min(index, trajectory.positions.size() - 1);
    trajectory.points->Reset();
    trajectory.lines->Reset();
    for (std::size_t i = 0; i <= index; ++i) {
        const auto& point = trajectory.positions[i];
        trajectory.points->InsertNextPoint(point[0], point[1], point[2]);
    }
    if (index > 0) {
        trajectory.lines->InsertNextCell(static_cast<vtkIdType>(index + 1));
        for (std::size_t i = 0; i <= index; ++i) {
            trajectory.lines->InsertCellPoint(static_cast<vtkIdType>(i));
        }
    }
    trajectory.points->Modified();
    trajectory.lines->Modified();
    trajectory.data->Modified();
}

void CloudViewer::open() {
    if (!window_open_) {
        window_->Render();
        interactor_->Initialize();
        window_open_ = true;
    }
}

void CloudViewer::showThroughFrame(std::size_t index, int frame) {
    showThroughFrameAt(index, index, frame);
}

void CloudViewer::showThroughFrameAt(
    std::size_t actor_index, std::size_t pose_index, int frame) {
    if (actor_index >= actors_.size() ||
        pose_index >= active_trajectory_.positions.size() ||
        interactor_->GetDone()) {
        return;
    }
    for (std::size_t i = 0; i < actors_.size(); ++i) {
        actors_[i]->SetVisibility(i <= actor_index);
    }
    showTrajectory(active_trajectory_, pose_index);
    showTrajectory(truth_trajectory_, pose_index);
    if (marker_points_) {
        const auto& point = active_trajectory_.positions[pose_index];
        marker_points_->SetPoint(0, point[0], point[1], point[2]);
        marker_points_->Modified();
    }
    if (!camera_set_) {
        renderer_->ResetCamera();
        camera_set_ = true;
    }
    renderer_->ResetCameraClippingRange();
    const std::string title = "Growing point cloud - frame " +
        std::to_string(frame) + " (" + std::to_string(pose_index + 1) + "/" +
        std::to_string(active_trajectory_.positions.size()) + ")" +
        (truth_trajectory_.positions.empty()
             ? " [trajectory: yellow]" : " [IMU: yellow, truth: cyan]");
    window_->SetWindowName(title.c_str());
    window_->Render();
    if (!window_open_) {
        interactor_->Initialize();
        window_open_ = true;
    }
}

void CloudViewer::runInteractive(
    std::function<void(const std::string&)> on_key,
    std::function<void()> on_tick) {
    if (!window_open_ || interactor_->GetDone()) {
        return;
    }

    auto key_callback = vtkSmartPointer<vtkCallbackCommand>::New();
    key_callback->SetClientData(&on_key);
    key_callback->SetCallback([](vtkObject* caller, unsigned long, void* data, void*) {
        auto* interactor = static_cast<vtkRenderWindowInteractor*>(caller);
        const char* key = interactor->GetKeySym();
        (*static_cast<std::function<void(const std::string&)>*>(data))(
            key ? key : "");
    });
    const auto key_tag = interactor_->AddObserver(vtkCommand::KeyPressEvent,
                                                  key_callback, 1.0f);

    auto timer_callback = vtkSmartPointer<vtkCallbackCommand>::New();
    timer_callback->SetClientData(&on_tick);
    timer_callback->SetCallback([](vtkObject*, unsigned long, void* data, void*) {
        (*static_cast<std::function<void()>*>(data))();
    });
    const auto timer_tag = interactor_->AddObserver(vtkCommand::TimerEvent,
                                                    timer_callback);
    const int timer_id = interactor_->CreateRepeatingTimer(30);
    interactor_->Start();
    interactor_->DestroyTimer(timer_id);
    interactor_->RemoveObserver(timer_tag);
    interactor_->RemoveObserver(key_tag);
}

void CloudViewer::close() {
    interactor_->TerminateApp();
}

void CloudViewer::waitUntilClosed() {
    if (window_open_ && !interactor_->GetDone()) {
        interactor_->Start();
    }
}
