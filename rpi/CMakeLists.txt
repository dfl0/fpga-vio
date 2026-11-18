cmake_minimum_required(VERSION 3.16)
project(fpga_vio_pi LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(OpenCV REQUIRED COMPONENTS
    core
    imgcodecs
    imgproc
    highgui
    OPTIONAL_COMPONENTS calib3d stereo
)
if(OpenCV_VERSION_MAJOR EQUAL 4 AND NOT OpenCV_calib3d_FOUND)
    message(FATAL_ERROR "OpenCV 4 requires the calib3d module for stereo matching")
elseif(OpenCV_VERSION_MAJOR GREATER_EQUAL 5 AND NOT OpenCV_stereo_FOUND)
    message(FATAL_ERROR "OpenCV 5 requires the stereo module for stereo matching")
endif()
find_package(Threads REQUIRED)

add_executable(stereo_viewer src/stereo_viewer.cpp)
target_include_directories(stereo_viewer PRIVATE ${OpenCV_INCLUDE_DIRS})
target_link_libraries(stereo_viewer PRIVATE ${OpenCV_LIBS})

if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/src/tartanair_cloud.cpp")
    add_executable(tartanair_cloud
        src/tartanair_cloud.cpp
        src/tartanair_source.cpp
        src/cloud_mapper.cpp)
    target_include_directories(tartanair_cloud PRIVATE ${OpenCV_INCLUDE_DIRS})
    target_link_libraries(tartanair_cloud PRIVATE ${OpenCV_LIBS})
endif()

add_executable(uart_bridge src/uart_bridge.cpp src/stream_writer.cpp)
target_include_directories(uart_bridge PRIVATE ${OpenCV_INCLUDE_DIRS})
target_link_libraries(uart_bridge PRIVATE ${OpenCV_LIBS})

add_executable(tartanair_feed
    src/tartanair_feed.cpp
    src/stream_writer.cpp
    src/tartanair_source.cpp)
target_include_directories(tartanair_feed PRIVATE ${OpenCV_INCLUDE_DIRS})
target_link_libraries(tartanair_feed PRIVATE ${OpenCV_LIBS})

find_package(VTK QUIET COMPONENTS CommonCore CommonDataModel
    RenderingCore RenderingOpenGL2 InteractionStyle)
if(VTK_FOUND)
    if(TARGET tartanair_cloud)
        target_sources(tartanair_cloud PRIVATE src/cloud_viewer.cpp)
        target_compile_definitions(tartanair_cloud PRIVATE HAVE_VTK)
        target_link_libraries(tartanair_cloud PRIVATE ${VTK_LIBRARIES})
        vtk_module_autoinit(TARGETS tartanair_cloud MODULES ${VTK_LIBRARIES})
    endif()

    add_executable(live_mapper
        src/live_mapper.cpp
        src/stdin_source.cpp
        src/cloud_mapper.cpp
        src/cloud_viewer.cpp)
    target_include_directories(live_mapper PRIVATE ${OpenCV_INCLUDE_DIRS})
    target_link_libraries(live_mapper PRIVATE ${OpenCV_LIBS} ${VTK_LIBRARIES}
        Threads::Threads)
    vtk_module_autoinit(TARGETS live_mapper MODULES ${VTK_LIBRARIES})
endif()
