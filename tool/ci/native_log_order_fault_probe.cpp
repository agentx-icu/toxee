#include "V2TIMLog.h"
#include <cerrno>
#include <cstring>
#include <dlfcn.h>
#include <fcntl.h>
#include <string>
#include <sys/stat.h>
#include <unistd.h>

// Test-link interposition only. Production has no fault switch or test budget.
static std::string mode;
static int metadataFd = -1, victimInspections = 0;
static bool partialDone = false;
static int metadataWrites = 0;

extern "C" ssize_t pwrite(int fd, const void* bytes, size_t count, off_t offset) {
    const auto real = reinterpret_cast<ssize_t (*)(int, const void*, size_t, off_t)>(dlsym(RTLD_NEXT, "pwrite"));
    if (fd == metadataFd && partialDone) { errno = EIO; return -1; }
    if (count == 512 && !std::memcmp(bytes, "TXLORD01", 8)) {
        metadataFd = fd;
        ++metadataWrites;
        if (mode == "partial" || (mode == "second-partial" && metadataWrites == 2)) {
            partialDone = true;
            return real(fd, bytes, 64, offset);
        }
    }
    return real(fd, bytes, count, offset);
}
extern "C" int fsync(int fd) {
    const auto real = reinterpret_cast<int (*)(int)>(dlsym(RTLD_NEXT, "fsync"));
    if (mode == "flush" && fd == metadataFd) { errno = EIO; return -1; }
    return real(fd);
}
extern "C" int fstatat(int directory, const char* path, struct stat* info, int flags) {
    const auto real = reinterpret_cast<int (*)(int, const char*, struct stat*, int)>(dlsym(RTLD_NEXT, "fstatat"));
    if (mode == "victim-replaced" && !std::strcmp(path, "app_1.log") && ++victimInspections == 2) {
        if (::renameat(directory, "app_1.log", directory, "saved-original") ||
            ::renameat(directory, "app_2.log", directory, "app_1.log")) { errno = EIO; return -1; }
    }
    return real(directory, path, info, flags);
}
int main(int argc, char** argv) {
    if (argc != 3) return 2;
    mode = argv[2];
    uint64_t generation = 99;
    auto& logger = V2TIMLog::getInstance();
    const auto result = logger.configureOwnedLog(argv[1], &generation);
    if (mode == "victim-replaced")
        return victimInspections == 2 && result == 3 && generation == 0 ? 0 : 3;
    // Metadata uncertainty must remain sticky: no deletion consent or replay.
    return metadataFd >= 0 && result == 8 && generation == 0 &&
        logger.releaseOwnedLog(0) == 8 && logger.configureOwnedLog(argv[1], &generation) == 8 ? 0 : 4;
}
