# action_recognition: STGCN action recognition node, custom msgs Action/ActionArray.
cmake_minimum_required(VERSION 3.10)
project(action_recognition LANGUAGES C CXX)

# Suppress CMP0148 warning from rosidl (FindPythonInterp deprecated).
if(POLICY CMP0148)
  cmake_policy(SET CMP0148 OLD)
endif()

set(CMAKE_CXX_STANDARD 17)

if(CMAKE_COMPILER_IS_GNUCXX OR CMAKE_CXX_COMPILER_ID MATCHES "Clang")
  add_compile_options(-Wall -Wextra -Wpedantic)
endif()

find_package(ament_cmake REQUIRED)
find_package(ament_index_cpp REQUIRED)
find_package(body_pose REQUIRED)
find_package(rclcpp REQUIRED)
find_package(rosidl_cmake REQUIRED)
find_package(rosidl_default_generators REQUIRED)
find_package(std_msgs REQUIRED)

# Custom messages: Action, ActionArray.
rosidl_generate_interfaces(${PROJECT_NAME}
  "msg/Action.msg"
  "msg/ActionArray.msg"
  DEPENDENCIES std_msgs
)

if(NOT DEFINED OpenCV_DIR)
  set(OpenCV_DIR "/opt/opencv-spacemit/lib/cmake/opencv4")
endif()
find_package(OpenCV 4 REQUIRED)
find_package(OpenCV REQUIRED COMPONENTS core imgproc highgui NO_DEFAULT_PATH)

set(SPACEMIT_ROBOT_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../..")
set(VISION_SERVICE_INCLUDE_DIR "${SPACEMIT_ROBOT_ROOT}/output/staging/include")
set(VISION_SERVICE_LIBRARY "${SPACEMIT_ROBOT_ROOT}/output/staging/lib/libvision.so")

if(NOT EXISTS "${VISION_SERVICE_INCLUDE_DIR}/vision_service.h")
  message(FATAL_ERROR "vision_service.h not found")
endif()
if(NOT EXISTS "${VISION_SERVICE_LIBRARY}")
  message(FATAL_ERROR "vision library not found. Ensure output/staging is prepared first.")
endif()

add_executable(action_recognition_node src/action_recognition_node.cpp)
target_include_directories(action_recognition_node PRIVATE ${VISION_SERVICE_INCLUDE_DIR} ${OpenCV_INCLUDE_DIRS})

ament_target_dependencies(action_recognition_node ament_index_cpp body_pose rclcpp std_msgs)
rosidl_get_typesupport_target(cpp_typesupport_target ${PROJECT_NAME} "rosidl_typesupport_cpp")
target_link_libraries(action_recognition_node
  "${cpp_typesupport_target}"
  std_msgs::std_msgs__rosidl_typesupport_cpp
  ${VISION_SERVICE_LIBRARY}
  ${OpenCV_LIBS}
)

get_filename_component(_opencv_lib_dir "${OpenCV_DIR}/../.." REALPATH)
get_filename_component(_vision_lib_dir "${SPACEMIT_ROBOT_ROOT}/output/staging/lib" REALPATH)
set_target_properties(action_recognition_node PROPERTIES
  INSTALL_RPATH "${_opencv_lib_dir};${_vision_lib_dir}"
  BUILD_WITH_INSTALL_RPATH FALSE
  BUILD_RPATH "${_opencv_lib_dir};${_vision_lib_dir}"
)

install(TARGETS action_recognition_node DESTINATION lib/${PROJECT_NAME})
install(DIRECTORY launch config DESTINATION share/${PROJECT_NAME})
ament_package()
