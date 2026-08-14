cmake_minimum_required(VERSION 3.10)
project(echo_peer CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

get_filename_component(TIM2TOX_ROOT
    "${CMAKE_CURRENT_SOURCE_DIR}/../../../third_party/tim2tox"
    ABSOLUTE)

if(NOT EXISTS "${TIM2TOX_ROOT}/ffi/tim2tox_ffi.h")
    message(FATAL_ERROR "Tim2Tox C FFI header not found under ${TIM2TOX_ROOT}/ffi")
endif()

if(DEFINED ENV{TIM2TOX_FFI_LIB})
    set(TIM2TOX_FFI_LIB "$ENV{TIM2TOX_FFI_LIB}")
elseif(NOT DEFINED TIM2TOX_FFI_LIB)
    if(APPLE)
        set(TIM2TOX_FFI_LIB "${TIM2TOX_ROOT}/build/ffi/libtim2tox_ffi.dylib")
    elseif(WIN32)
        set(TIM2TOX_FFI_LIB "${TIM2TOX_ROOT}/build/ffi/tim2tox_ffi.dll")
    else()
        set(TIM2TOX_FFI_LIB "${TIM2TOX_ROOT}/build/ffi/libtim2tox_ffi.so")
    endif()
endif()

if(NOT EXISTS "${TIM2TOX_FFI_LIB}")
    message(FATAL_ERROR "Tim2Tox C FFI library not found: ${TIM2TOX_FFI_LIB}")
endif()

add_library(tim2tox_ffi SHARED IMPORTED)
set_target_properties(tim2tox_ffi PROPERTIES
    IMPORTED_LOCATION "${TIM2TOX_FFI_LIB}"
    INTERFACE_INCLUDE_DIRECTORIES "${TIM2TOX_ROOT}/ffi")

add_library(echo_peer_protocol STATIC echo_peer_protocol.cpp)
target_include_directories(echo_peer_protocol PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")

add_executable(echo_peer echo_peer.cpp)
target_link_libraries(echo_peer
    PRIVATE
        echo_peer_protocol
        tim2tox_ffi)

add_executable(echo_peer_protocol_test echo_peer_protocol_test.cpp)
target_link_libraries(echo_peer_protocol_test PRIVATE echo_peer_protocol)

enable_testing()
add_test(NAME echo_peer_protocol_test COMMAND echo_peer_protocol_test)

if(APPLE)
    set_target_properties(echo_peer PROPERTIES
        INSTALL_RPATH "${TIM2TOX_ROOT}/build/ffi"
        BUILD_WITH_INSTALL_RPATH TRUE)
endif()
