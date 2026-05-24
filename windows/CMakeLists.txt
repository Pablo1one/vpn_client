cmake_minimum_required(VERSION 3.14)
project(vpn_client LANGUAGES CXX)

set(BINARY_NAME "vpn_client")
cmake_policy(SET CMP0063 NEW)

set(CMAKE_INSTALL_RPATH "$ORIGIN/lib")
set(BUILD_BUNDLE_DIR "${PROJECT_BINARY_DIR}/bundle")
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${BUILD_BUNDLE_DIR}")
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY "${BUILD_BUNDLE_DIR}")

set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
include(${FLUTTER_MANAGED_DIR}/generated_plugins.cmake OPTIONAL)
add_subdirectory(${FLUTTER_MANAGED_DIR} managed_flutter)
add_subdirectory(runner)

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR  "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
        COMPONENT Runtime)
install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
        COMPONENT Runtime)
install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${CMAKE_INSTALL_PREFIX}"
        COMPONENT Runtime)

foreach(bundled_library ${PLUGIN_BUNDLED_LIBRARIES})
  install(FILES "${bundled_library}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endforeach(bundled_library)

install(CODE "
  file(GLOB_RECURSE LIBS_TO_DEPLOY
    \"${BUILD_BUNDLE_DIR}/flutter_assets\"
  )
  file(INSTALL \${LIBS_TO_DEPLOY}
    DESTINATION \"${INSTALL_BUNDLE_DATA_DIR}/flutter_assets\"
  )
  " COMPONENT Runtime)
