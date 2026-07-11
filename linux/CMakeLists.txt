# Project-level configuration.
cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "toxee")
# The unique GTK application identifier for this application. See:
# https://wiki.gnome.org/HowDoI/ChooseApplicationID
set(APPLICATION_ID "com.toxee.app")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(SET CMP0063 NEW)

# Load bundled libraries from the lib/ directory relative to the binary.
set(CMAKE_INSTALL_RPATH "$ORIGIN/lib")

# Root filesystem for cross-building.
if(FLUTTER_TARGET_PLATFORM_SYSROOT)
  set(CMAKE_SYSROOT ${FLUTTER_TARGET_PLATFORM_SYSROOT})
  set(CMAKE_FIND_ROOT_PATH ${CMAKE_SYSROOT})
  set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
  set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
  set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
  set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
endif()

# Define build configuration options.
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE "Debug" CACHE
    STRING "Flutter build mode" FORCE)
  set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
    "Debug" "Profile" "Release")
endif()

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE -Wall -Werror)
  target_compile_options(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:-O3>")
  target_compile_definitions(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:NDEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# System-level dependencies.
find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK REQUIRED IMPORTED_TARGET gtk+-3.0)

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)

# Only the install-generated bundle's copy of the executable will launch
# correctly, since the resources must in the right relative locations. To avoid
# people trying to run the unbundled copy, put it in a subdirectory instead of
# the default top-level location.
set_target_properties(${BINARY_NAME}
  PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/intermediates_do_not_run"
)


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)

# desktop_drop_for_t (the pub republish of desktop_drop the UIKit fork depends
# on) renamed the PACKAGE but its linux/CMakeLists.txt still defines the target
# as `desktop_drop_plugin` (the Windows one was fixed upstream, Linux was not);
# flutter's generated_plugins.cmake links + bundles `<package>_plugin`
# (`desktop_drop_for_t_plugin`), which fails at the CMake generate step with
# "No target". Bridge with an ALIAS — target_link_libraries and the
# $<TARGET_FILE:> bundling genex both resolve aliases late, so defining it
# right after the include is sufficient.
if(TARGET desktop_drop_plugin AND NOT TARGET desktop_drop_for_t_plugin)
  add_library(desktop_drop_for_t_plugin ALIAS desktop_drop_plugin)
  # Same republish sloppiness for headers: they still live under
  # include/desktop_drop/, while generated_plugin_registrant.cc includes
  # <desktop_drop_for_t/desktop_drop_plugin.h>. compat_include/ carries a
  # forwarding header with the expected path.
  target_include_directories(${BINARY_NAME} PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/compat_include")
endif()


# === Installation ===
# By default, "installing" just makes a relocatable bundle in the build
# directory.
set(BUILD_BUNDLE_DIR "${PROJECT_BINARY_DIR}/bundle")
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

# Start with a clean build bundle directory every time.
install(CODE "
  file(REMOVE_RECURSE \"${BUILD_BUNDLE_DIR}/\")
  " COMPONENT Runtime)

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}/lib")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

foreach(bundled_library ${PLUGIN_BUNDLED_LIBRARIES})
  install(FILES "${bundled_library}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endforeach(bundled_library)

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/linux/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
if(NOT CMAKE_BUILD_TYPE MATCHES "Debug")
  install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# Install the tim2tox FFI shared library and its libsodium dependency into the
# bundle's lib/ dir so `flutter build linux` produces a self-contained bundle
# (mirrors windows/CMakeLists.txt and tool/ci/package_artifacts.sh release
# staging). The native library can come from two scripts in different layouts:
#   * tool/ci/build_tim2tox.sh — canonical path — emits build/native-artifacts/
#     linux/ (libtim2tox_ffi.so + the libsodium SONAME symlink and real file,
#     captured from the FFI's ldd) and the raw cmake output under
#     third_party/tim2tox/build/ci-linux/.
#   * third_party/tim2tox/build_ffi.sh — dev convenience — emits build/ffi/.
# Install the candidate with the newest mtime so whichever build ran most
# recently wins. The native lib MUST be built before `flutter build linux`
# (build_all.sh does this first), so it is present at configure time normally.
set(_TIM2TOX_NATIVE_ARTIFACTS_DIR "${CMAKE_SOURCE_DIR}/../build/native-artifacts/linux")
set(_TIM2TOX_FFI_SO_CANDIDATES
  "${_TIM2TOX_NATIVE_ARTIFACTS_DIR}/libtim2tox_ffi.so"
  "${CMAKE_SOURCE_DIR}/../third_party/tim2tox/build/ci-linux/ffi/libtim2tox_ffi.so"
  "${CMAKE_SOURCE_DIR}/../third_party/tim2tox/build/ffi/libtim2tox_ffi.so"
)
set(_best_ffi "")
set(_best_ffi_ts "0")
foreach(_so IN LISTS _TIM2TOX_FFI_SO_CANDIDATES)
  if(EXISTS "${_so}")
    file(TIMESTAMP "${_so}" _ts "%Y%m%d%H%M%S")
    if(_ts STRGREATER _best_ffi_ts)
      set(_best_ffi_ts "${_ts}")
      set(_best_ffi "${_so}")
    endif()
  endif()
endforeach()
if(_best_ffi)
  install(FILES "${_best_ffi}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}" COMPONENT Runtime)
  message(STATUS "toxee: bundling libtim2tox_ffi.so from ${_best_ffi}")

  # libsodium: build_tim2tox.sh stages both the SONAME symlink (e.g.
  # libsodium.so) and the resolved real file (e.g. libsodium.so.26.x.y) into
  # native-artifacts/linux, so bundling the glob makes the NEEDED soname
  # resolve. On a dev box without native-artifacts this is simply skipped and
  # the system libsodium (via ldconfig) is used instead — which is fine.
  file(GLOB _sodium_libs "${_TIM2TOX_NATIVE_ARTIFACTS_DIR}/libsodium.so*")
  if(_sodium_libs)
    install(FILES ${_sodium_libs} DESTINATION "${INSTALL_BUNDLE_LIB_DIR}" COMPONENT Runtime)
    message(STATUS "toxee: bundling libsodium from ${_TIM2TOX_NATIVE_ARTIFACTS_DIR}")
  else()
    # build_all.sh's tim2tox path (build_ffi.sh) does NOT capture libsodium, so
    # for that flow the bundle relies on the system libsodium via ldconfig (fine
    # on a dev box). Only tool/ci/build_tim2tox.sh --target linux stages a
    # libsodium copy, yielding a fully self-contained bundle.
    message(STATUS "toxee: no libsodium in ${_TIM2TOX_NATIVE_ARTIFACTS_DIR}; the "
      "linux bundle will rely on the system libsodium (ldconfig). Run "
      "tool/ci/build_tim2tox.sh --target linux for a fully self-contained bundle.")
  endif()

  # The runner's RPATH ($ORIGIN/lib, set at the top of this file) resolves
  # runner -> libtim2tox_ffi.so, but libtim2tox_ffi.so -> libsodium needs the
  # FFI lib's OWN RUNPATH to point at its directory. Patch it to $ORIGIN after
  # install (mirrors patchelf in tool/ci/package_artifacts.sh). execute_process
  # runs patchelf directly (no shell), so "$ORIGIN" is passed as a literal and
  # written verbatim into the ELF RUNPATH rather than being shell-expanded.
  find_program(_TOXEE_PATCHELF patchelf)
  get_filename_component(_ffi_name "${_best_ffi}" NAME)
  if(_TOXEE_PATCHELF)
    install(CODE
      "execute_process(COMMAND \"${_TOXEE_PATCHELF}\" --set-rpath \"\$ORIGIN\" \"${INSTALL_BUNDLE_LIB_DIR}/${_ffi_name}\")"
      COMPONENT Runtime)
  else()
    message(WARNING "toxee: patchelf not found; libtim2tox_ffi.so RUNPATH will "
      "not be set to \$ORIGIN. A bundled libsodium next to it may not resolve "
      "at runtime (the system libsodium via ldconfig will still work). Install "
      "patchelf to make the bundle fully self-contained.")
  endif()
else()
  message(WARNING "toxee: libtim2tox_ffi.so not found in any known build output "
    "location; the bundle will be missing the Tox native library. Run "
    "tool/ci/build_tim2tox.sh --target linux (or build_all.sh) before "
    "`flutter build linux`.")
endif()
