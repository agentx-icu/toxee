#include "V2TIMLog.h"
#include <cerrno>
#include <dirent.h>

// Test-link interposition only: actual source must distinguish a failed libc
// directory read from EOF. No production macro, hook or reduced budget.
extern "C" struct dirent* readdir(DIR*) {
    errno = EIO;
    return nullptr;
}

int main(int argc, char** argv) {
    if (argc != 2) return 2;
    uint64_t generation = 99;
    auto& logger = V2TIMLog::getInstance();
    return logger.configureOwnedLog(argv[1], &generation) == 4 &&
        generation == 0 && logger.releaseOwnedLog(0) == 0 ? 0 : 3;
}
