#include "V2TIMLog.h"

#include <array>
#include <cstdint>
#include <atomic>
#include <string>
#include <thread>
#include <vector>
#include <cstring>
#include <filesystem>
#include <iostream>
#ifndef _WIN32
#include <csignal>
#include <sys/resource.h>
#endif

// Compile this against the actual pinned logger implementation. There is no
// substitute writer or production test hook in this retention regression.
int runProbe(int argc, char** argv) {
    if (argc < 2 || argc > 3) return 2;
    auto& logger = V2TIMLog::getInstance();
    if (argc == 3) {
        uint64_t generation = 999;
        const auto configured = logger.configureOwnedLog(argv[1], &generation);
        const std::string mode = argv[2];
        if (mode == "busy") return configured == 7 && generation == 0 ? 0 : 27;
        if (mode == "unsafe") return configured == 3 && generation == 0 ? 0 : 10;
        if (mode == "missing") return configured == 4 && generation == 0 && logger.releaseOwnedLog(0) == 0 ? 0 : 11;
        if (configured != 0 || generation == 0) return 12;
        if (mode == "hold") {
            std::cout << "READY\n" << std::flush;
            std::string command;
            std::getline(std::cin, command);
        }
        if (logger.releaseOwnedLog(0) != 5 || logger.releaseOwnedLog(generation + 1) != 5) return 13;
        uint64_t second = 999;
        if (logger.configureOwnedLog(argv[1], &second) != 7 || second != 0) return 14;
        // A legacy SDK setter must not change the current managed owner.
        logger.setLogFile(std::string(argv[1]) + ".must-not-exist");
        const uint8_t invalid[] = {0xc0, 0xaf};
        if (logger.appendOwnedLog(generation, invalid, sizeof(invalid)) != 2) return 15;
        if (mode == "failure") {
#ifndef _WIN32
            struct rlimit original{}, limited{};
            if (getrlimit(RLIMIT_FSIZE, &original)) return 16;
            limited = original; limited.rlim_cur = 1024 * 1024;
            std::signal(SIGXFSZ, SIG_IGN);
            if (setrlimit(RLIMIT_FSIZE, &limited)) return 17;
            const std::string line(32768, 'f');
            int32_t result = 0;
            for (int i = 0; i < 40 && result == 0; ++i)
                result = logger.appendOwnedLog(generation, reinterpret_cast<const uint8_t*>(line.data()), line.size());
            if (setrlimit(RLIMIT_FSIZE, &original)) return 18;
            if (result != 6 || logger.releaseOwnedLog(generation) != 0 || logger.releaseOwnedLog(0) != 0) return 19;
#else
            return 20; // The caller must not report a POSIX fault fixture on Windows.
#endif
        } else if (mode == "owned") {
            std::atomic<bool> failed{false};
            std::vector<std::thread> workers;
            for (int thread = 0; thread < 4; ++thread) {
                workers.emplace_back([&, thread] {
                    std::array<tim2tox::diag::Field, 64> fields;
                    for (auto& field : fields) field = tim2tox::diag::Field::Count(1234567890);
                    const std::string line = "[INFO] dart_harness_marker=" + std::string(1100, 'd') + "\n";
                    for (int index = 0; index < 28000; ++index) {
                        if (thread == 0) {
                            if (logger.appendOwnedLog(generation, reinterpret_cast<const uint8_t*>(line.data()), line.size()) != 0) failed = true;
                        } else logger.Info(tim2tox::diag::Event<"retention_probe", "bounded_record">{fields.data(), fields.size()});
                    }
                });
            }
            for (auto& worker : workers) worker.join();
            if (failed) return 21;
            // An oversized record must be visibly truncated at a UTF-8 code
            // point, without creating a segment larger than production budget.
            std::string huge;
            for (int i = 0; i < 30000; ++i) huge += "\xe7\x95\x8c";
            if (logger.appendOwnedLog(generation, reinterpret_cast<const uint8_t*>(huge.data()), huge.size()) != 1) return 22;
        }
        const auto final = tim2tox::diag::Field::Status(123456789);
        logger.Info(tim2tox::diag::Event<"retention_probe", "retention_final">{&final, 1});
        if (logger.releaseOwnedLog(generation) != 0 || logger.releaseOwnedLog(generation) != 0 || logger.releaseOwnedLog(0) != 0) return 23;
        if (logger.appendOwnedLog(generation, invalid, sizeof(invalid)) != 5) return 24;
        uint64_t next = 0;
        if (logger.configureOwnedLog(argv[1], &next) != 0 || next <= generation) return 25;
        if (logger.releaseOwnedLog(generation) != 5 || logger.releaseOwnedLog(next) != 0) return 26;
        return 0;
    }
    logger.setLogFile(argv[1]);
    logger.enableConsoleOutput(false);
    std::array<tim2tox::diag::Field, 64> fields;
    for (auto& field : fields) field = tim2tox::diag::Field::Count(1234567890);
    for (int index = 0; index < 15000; ++index) {
        logger.Info(tim2tox::diag::Event<"retention_probe", "bounded_record">{
            fields.data(), fields.size()});
    }
    const auto final = tim2tox::diag::Field::Status(123456789);
    logger.Info(tim2tox::diag::Event<"retention_probe", "retention_final">{&final, 1});
    return 0;
}

#ifdef _WIN32
int wmain(int argc, wchar_t** wide) {
    std::vector<std::string> encoded;
    for (int i = 0; i < argc; ++i) {
        const auto bytes = std::filesystem::path(wide[i]).u8string();
        encoded.emplace_back(bytes.begin(), bytes.end());
    }
    std::vector<char*> argv;
    for (auto& value : encoded) argv.push_back(value.data());
    return runProbe(argc, argv.data());
}
#else
int main(int argc, char** argv) { return runProbe(argc, argv); }
#endif
