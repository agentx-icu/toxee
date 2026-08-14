#include "echo_peer_protocol.h"
#include "tim2tox_ffi.h"

#include <array>
#include <chrono>
#include <cctype>
#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <string>
#include <thread>
#include <unordered_set>
#include <vector>

namespace {

volatile std::sig_atomic_t g_should_exit = 0;
constexpr std::size_t kMaxBufferedRecordBytes = 16ULL * 1024ULL * 1024ULL;
constexpr std::size_t kInitialFriendApplicationsBytes = 64ULL * 1024ULL;

void HandleShutdownSignal(int) {
    g_should_exit = 1;
}

std::string ResolveStateDir() {
    const char* configured = std::getenv("ECHO_PEER_STATE_DIR");
    std::error_code error;
    std::filesystem::path directory;
    if (configured != nullptr && configured[0] != '\0') {
        directory = configured;
    } else {
        directory = std::filesystem::current_path(error) / "build" /
                    "echo_peer_state";
        if (error) {
            std::fprintf(stderr,
                         "echo_peer: state_directory status=resolve_failed\n");
            return {};
        }
    }

    std::filesystem::create_directories(directory, error);
    if (error) {
        std::fprintf(stderr,
                     "echo_peer: state_directory status=create_failed\n");
        return {};
    }

    const std::filesystem::path canonical =
        std::filesystem::weakly_canonical(directory, error);
    return error ? directory.string() : canonical.string();
}

bool IsToxId(const std::string& value) {
    if (value.size() != 76) {
        return false;
    }
    for (const unsigned char character : value) {
        if (std::isxdigit(character) == 0) {
            return false;
        }
    }
    return true;
}

void DrainFriendApplications(std::unordered_set<std::string>* accepted_ids) {
    std::string applications;
    const echo_peer::BoundedReadResult result = echo_peer::ReadBoundedRecord(
        tim2tox_ffi_get_friend_applications,
        kInitialFriendApplicationsBytes,
        kMaxBufferedRecordBytes,
        &applications);
    if (result == echo_peer::BoundedReadResult::kInvalidLength) {
        std::fprintf(stderr,
                     "echo_peer: friend_applications status=invalid_length\n");
        return;
    }
    if (result == echo_peer::BoundedReadResult::kEmpty) {
        return;
    }

    const std::vector<std::string> applicant_ids =
        echo_peer::ParseFriendApplicationIds(applications);
    std::size_t accepted_count = 0;
    std::size_t failed_count = 0;
    for (const std::string& applicant_id : applicant_ids) {
        if (accepted_ids->count(applicant_id) != 0) {
            continue;
        }
        if (tim2tox_ffi_accept_friend(applicant_id.c_str()) == 1) {
            accepted_ids->insert(applicant_id);
            ++accepted_count;
        } else {
            ++failed_count;
        }
    }
    if (accepted_count != 0 || failed_count != 0) {
        std::printf(
            "echo_peer: friend_applications accepted_count=%zu failed_count=%zu\n",
            accepted_count, failed_count);
    }
}

bool DrainTextEvents(unsigned long long* echo_count) {
    std::vector<char> buffer(4096);
    while (g_should_exit == 0) {
        const int bytes = tim2tox_ffi_poll_text(
            0, buffer.data(), static_cast<int>(buffer.size()));
        if (bytes == 0) {
            return true;
        }
        if (bytes < 0) {
            const long long required = -static_cast<long long>(bytes);
            if (required <= static_cast<long long>(buffer.size()) ||
                required > static_cast<long long>(kMaxBufferedRecordBytes)) {
                std::fprintf(stderr,
                             "echo_peer: poll_text status=invalid_length\n");
                return false;
            }
            buffer.resize(static_cast<std::size_t>(required));
            continue;
        }
        if (static_cast<std::size_t>(bytes) > buffer.size()) {
            std::fprintf(stderr,
                         "echo_peer: poll_text status=invalid_length\n");
            return false;
        }

        echo_peer::C2CTextEvent event;
        if (!echo_peer::ParseC2CTextEvent(
                std::string(buffer.data(), static_cast<std::size_t>(bytes)),
                &event)) {
            continue;
        }
        if (tim2tox_ffi_send_c2c_text(event.sender.c_str(),
                                      event.payload.c_str()) != 1) {
            std::fprintf(stderr, "echo_peer: text_echo status=failed\n");
            continue;
        }
        ++(*echo_count);
        std::printf("echo_peer: text_echo status=sent count=%llu\n",
                    *echo_count);
    }
    return true;
}

void Shutdown() {
    tim2tox_ffi_save_tox_profile();
    tim2tox_ffi_uninit();
}

}

int main() {
    setvbuf(stdout, nullptr, _IONBF, 0);
    setvbuf(stderr, nullptr, _IONBF, 0);

    struct sigaction action {};
    action.sa_handler = HandleShutdownSignal;
    sigemptyset(&action.sa_mask);
    action.sa_flags = 0;
    sigaction(SIGTERM, &action, nullptr);
    sigaction(SIGINT, &action, nullptr);

    const std::string state_dir = ResolveStateDir();
    if (state_dir.empty()) {
        return 1;
    }
    std::printf("echo_peer: state_directory status=ready\n");

    if (tim2tox_ffi_init_with_path(state_dir.c_str()) != 1) {
        std::fprintf(stderr, "echo_peer: init status=failed\n");
        return 1;
    }
    if (tim2tox_ffi_login("EchoBotServer", "dummy_sig") != 1) {
        std::fprintf(stderr, "echo_peer: login status=failed\n");
        Shutdown();
        return 1;
    }

    std::array<char, 128> tox_id_buffer{};
    const int tox_id_bytes = tim2tox_ffi_get_self_tox_id(
        tox_id_buffer.data(), static_cast<int>(tox_id_buffer.size()));
    const std::string tox_id = tox_id_bytes > 0
        ? std::string(tox_id_buffer.data(),
                      static_cast<std::size_t>(tox_id_bytes))
        : std::string();
    if (!IsToxId(tox_id)) {
        std::fprintf(stderr,
                     "echo_peer: identity status=invalid length=%d\n",
                     tox_id_bytes);
        Shutdown();
        return 1;
    }
    std::printf("ECHO_PEER_TOX_ID: %s\n", tox_id.c_str());

    std::unordered_set<std::string> accepted_ids;
    unsigned long long echo_count = 0;
    auto next_friend_drain = std::chrono::steady_clock::now();
    while (g_should_exit == 0) {
        if (!DrainTextEvents(&echo_count)) {
            Shutdown();
            return 1;
        }
        const auto now = std::chrono::steady_clock::now();
        if (now >= next_friend_drain) {
            DrainFriendApplications(&accepted_ids);
            next_friend_drain = now + std::chrono::milliseconds(500);
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
    }

    std::printf("echo_peer: shutdown status=signal_received\n");
    Shutdown();
    return 0;
}
