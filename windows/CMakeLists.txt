# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(toxee LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "toxee")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)


# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
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
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)

# Install the tim2tox FFI shared library (and its libsodium runtime dependency)
# next to the Flutter runner so the Dart FFI loader can find them via the
# executable directory at runtime. The native library can be produced by two
# scripts that emit into different layouts:
#   * tool/ci/build_tim2tox.sh — the canonical Windows path (CI + local Windows,
#     since build_ffi.sh below is make-based and does not run on Windows). It
#     drops a generator-independent copy in build/native-artifacts/windows/ and
#     leaves the raw Visual Studio output under
#     third_party/tim2tox/build/ci-windows/ffi/<config>/.
#   * third_party/tim2tox/build_ffi.sh — the Unix-oriented dev convenience that
#     build_all.sh invokes; emits build/ffi/.
# Rather than hard-coding a priority (which risks a stale copy in one layout
# shadowing a freshly-built copy in another — true in either order), we pick the
# candidate with the NEWEST mtime, so whichever build ran most recently wins.
# The native library MUST be built before `flutter build windows` (see
# build_all.sh / CLAUDE.md), so a candidate is present at configure time in
# normal flows; one that only appears after configure is intentionally not
# picked up — re-run CMake (touch the build) in that case.
set(_TIM2TOX_NATIVE_ARTIFACTS_DIR "${CMAKE_SOURCE_DIR}/../build/native-artifacts/windows")
set(_TIM2TOX_FFI_DLL_CANDIDATES
  "${_TIM2TOX_NATIVE_ARTIFACTS_DIR}/tim2tox_ffi.dll"
  "${CMAKE_SOURCE_DIR}/../third_party/tim2tox/build/ci-windows/ffi/Release/tim2tox_ffi.dll"
  "${CMAKE_SOURCE_DIR}/../third_party/tim2tox/build/ci-windows/ffi/Debug/tim2tox_ffi.dll"
  "${CMAKE_SOURCE_DIR}/../third_party/tim2tox/build/ffi/tim2tox_ffi.dll"
  "${CMAKE_SOURCE_DIR}/../third_party/tim2tox/build/ffi/Release/tim2tox_ffi.dll"
  "${CMAKE_SOURCE_DIR}/../third_party/tim2tox/build/ffi/Debug/tim2tox_ffi.dll"
  "${CMAKE_SOURCE_DIR}/../third_party/tim2tox/build/bin/tim2tox_ffi.dll"
)
# Install whichever of the listed candidates exists and has the newest mtime.
# Timestamps are formatted YYYYMMDDHHMMSS so plain string compare == time order.
function(toxee_install_newest_existing _label)
  set(_best "")
  set(_best_ts "0")
  foreach(_f IN LISTS ARGN)
    if(EXISTS "${_f}")
      file(TIMESTAMP "${_f}" _ts "%Y%m%d%H%M%S")
      if(_ts STRGREATER _best_ts)
        set(_best_ts "${_ts}")
        set(_best "${_f}")
      endif()
    endif()
  endforeach()
  if(_best)
    install(FILES "${_best}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}" COMPONENT Runtime)
    message(STATUS "toxee: bundling ${_label} from ${_best}")
  endif()
  set(toxee_install_newest_existing_result "${_best}" PARENT_SCOPE)
endfunction()

toxee_install_newest_existing("tim2tox_ffi.dll" ${_TIM2TOX_FFI_DLL_CANDIDATES})
if(NOT toxee_install_newest_existing_result)
  message(WARNING "toxee: tim2tox_ffi.dll not found in any known build output "
    "location; the runner will be missing the Tox native library. Run "
    "tool/ci/build_tim2tox.sh --target windows before `flutter build windows`.")
endif()

# tim2tox_ffi.dll dynamically links libsodium.dll, so the runner needs it next to
# the executable or the FFI library fails to load at startup. Probe the libsodium
# matching the target architecture (mirrors the triplet logic in
# tool/ci/build_tim2tox.sh). Note: $ENV{VCPKG_ROOT} is captured at CMake
# configure time — re-run CMake if it changes.
if(CMAKE_GENERATOR_PLATFORM MATCHES "[Aa][Rr][Mm]64")
  set(_TIM2TOX_VCPKG_TRIPLET "arm64-windows")
else()
  set(_TIM2TOX_VCPKG_TRIPLET "x64-windows")
endif()
set(_TIM2TOX_LIBSODIUM_DLL_CANDIDATES
  "${_TIM2TOX_NATIVE_ARTIFACTS_DIR}/libsodium.dll"
)
if(DEFINED ENV{VCPKG_ROOT})
  list(APPEND _TIM2TOX_LIBSODIUM_DLL_CANDIDATES
    "$ENV{VCPKG_ROOT}/installed/${_TIM2TOX_VCPKG_TRIPLET}/bin/libsodium.dll")
endif()
toxee_install_newest_existing("libsodium.dll" ${_TIM2TOX_LIBSODIUM_DLL_CANDIDATES})

# tim2tox_ffi.dll also dynamically links the vcpkg pthreads runtime
# (pthreadVC3.dll, release) on Windows because c-toxcore uses pthreads-win32.
# Bundle it next to the runner for the same reason as libsodium.dll: a missing
# transitive dependency makes the FFI library fail to load at startup with
# "error code 126" (ERROR_MOD_NOT_FOUND) even though tim2tox_ffi.dll is present.
# tool/ci/build_tim2tox.sh captures it into native-artifacts; fall back to the
# vcpkg bin dir (release pthreadVC3.dll only — the debug build is pthreadVC3d.dll).
set(_TIM2TOX_PTHREAD_DLL_CANDIDATES
  "${_TIM2TOX_NATIVE_ARTIFACTS_DIR}/pthreadVC3.dll"
)
if(DEFINED ENV{VCPKG_ROOT})
  list(APPEND _TIM2TOX_PTHREAD_DLL_CANDIDATES
    "$ENV{VCPKG_ROOT}/installed/${_TIM2TOX_VCPKG_TRIPLET}/bin/pthreadVC3.dll")
endif()
toxee_install_newest_existing("pthreadVC3.dll" ${_TIM2TOX_PTHREAD_DLL_CANDIDATES})
