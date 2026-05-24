cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

set(BINARY_NAME "vpn_client")
set(APP_VERSION "1.0.0")
set(APP_VERSION_MAJOR 1)
set(APP_VERSION_MINOR 0)
set(APP_VERSION_PATCH 0)

configure_file(
  "${CMAKE_CURRENT_SOURCE_DIR}/resource.h.in"
  "${CMAKE_CURRENT_BINARY_DIR}/resource.h"
)

add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

apply_standard_settings(${BINARY_NAME})

target_compile_definitions(${BINARY_NAME} PRIVATE
  "FLUTTER_VERSION=\"${FLUTTER_VERSION}\""
  "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}"
  "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}"
  "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}"
  "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}"
)

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_CURRENT_BINARY_DIR}")
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")

set_target_properties(${BINARY_NAME} PROPERTIES
  LINK_FLAGS "/SUBSYSTEM:WINDOWS"
)
add_dependencies(${BINARY_NAME} flutter_assemble)
