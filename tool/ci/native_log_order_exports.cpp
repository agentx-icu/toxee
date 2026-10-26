#include "V2TIMLog.h"
#ifdef _WIN32
#define LOG_PROBE_EXPORT __declspec(dllexport)
#else
#define LOG_PROBE_EXPORT
#endif
// Three-symbol test adapter over the actual pinned source, never an app FFI.
extern "C" LOG_PROBE_EXPORT int32_t tim2tox_ffi_log_configure_owned(const char* path, uint64_t* generation) {
    if (generation) *generation = 0;
    try { return V2TIMLog::getInstance().configureOwnedLog(path, generation); } catch (...) { return 8; }
}
extern "C" LOG_PROBE_EXPORT int32_t tim2tox_ffi_log_append_owned(uint64_t generation, const uint8_t* bytes, size_t length) {
    try { return V2TIMLog::getInstance().appendOwnedLog(generation, bytes, length); } catch (...) { return 8; }
}
extern "C" LOG_PROBE_EXPORT int32_t tim2tox_ffi_log_release_owned(uint64_t generation) {
    try { return V2TIMLog::getInstance().releaseOwnedLog(generation); } catch (...) { return 8; }
}
