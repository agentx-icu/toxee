#include "echo_peer_protocol.h"

#include <cstring>
#include <cstdio>
#include <cstddef>
#include <string>
#include <vector>

namespace {

constexpr std::size_t kInitialCapacity = 64 * 1024;
constexpr std::size_t kMaxCapacity = 16 * 1024 * 1024;

struct ReaderScript {
    std::vector<int> returns;
    std::vector<int> capacities;
    std::string payload;
    std::size_t next = 0;
};

ReaderScript* g_reader_script = nullptr;

int ReadScript(char* buffer, int buffer_length) {
    g_reader_script->capacities.push_back(buffer_length);
    const std::size_t step = g_reader_script->next++;
    if (step >= g_reader_script->returns.size()) {
        return 0;
    }
    const int result = g_reader_script->returns[step];
    if (result > 0 && static_cast<std::size_t>(result) <=
                          static_cast<std::size_t>(buffer_length)) {
        std::memcpy(buffer, g_reader_script->payload.data(),
                    static_cast<std::size_t>(result));
    }
    return result;
}

bool Expect(bool condition, const char* message) {
    if (!condition) {
        std::fprintf(stderr, "FAIL: %s\n", message);
        return false;
    }
    return true;
}

}

int main() {
    bool ok = true;

    ReaderScript growing_record;
    growing_record.returns = {-70000, -80000, 0};
    growing_record.payload = "ALICE\thello";
    growing_record.returns.back() =
        static_cast<int>(growing_record.payload.size());
    g_reader_script = &growing_record;
    std::string record;
    ok &= Expect(
        echo_peer::ReadBoundedRecord(
            ReadScript, kInitialCapacity, kMaxCapacity, &record) ==
            echo_peer::BoundedReadResult::kRecord,
        "negative required lengths are retried");
    ok &= Expect(record == "ALICE\thello", "retried record is preserved");
    ok &= Expect(
        growing_record.capacities == std::vector<int>({
            static_cast<int>(kInitialCapacity), 70000, 80000}),
        "retry capacities grow monotonically");

    ReaderScript non_growing;
    non_growing.returns = {-static_cast<int>(kInitialCapacity)};
    g_reader_script = &non_growing;
    ok &= Expect(
        echo_peer::ReadBoundedRecord(
            ReadScript, kInitialCapacity, kMaxCapacity, &record) ==
            echo_peer::BoundedReadResult::kInvalidLength,
        "non-growing required length is rejected");

    ReaderScript too_large;
    too_large.returns = {-static_cast<int>(kMaxCapacity + 1)};
    g_reader_script = &too_large;
    ok &= Expect(
        echo_peer::ReadBoundedRecord(
            ReadScript, kInitialCapacity, kMaxCapacity, &record) ==
            echo_peer::BoundedReadResult::kInvalidLength,
        "required length above 16 MiB is rejected");

    ReaderScript oversized_result;
    oversized_result.returns = {
        static_cast<int>(kInitialCapacity + 1),
    };
    g_reader_script = &oversized_result;
    ok &= Expect(
        echo_peer::ReadBoundedRecord(
            ReadScript, kInitialCapacity, kMaxCapacity, &record) ==
            echo_peer::BoundedReadResult::kInvalidLength,
        "positive result beyond the buffer is rejected");

    echo_peer::C2CTextEvent event;
    ok &= Expect(
        echo_peer::ParseC2CTextEvent("c2c:ABCDEF:one:two:three", &event),
        "C2C text event is recognized");
    ok &= Expect(event.sender == "ABCDEF", "sender is extracted");
    ok &= Expect(event.payload == "one:two:three", "payload colons are preserved");
    ok &= Expect(
        echo_peer::ParseC2CTextEvent("c2c:ABCDEF:line1\nline2", &event),
        "newline-bearing payload is recognized as one record");
    ok &= Expect(
        event.payload == "line1\nline2",
        "newline-bearing payload is preserved verbatim");
    ok &= Expect(
        !echo_peer::ParseC2CTextEvent("conn:success", &event),
        "non-C2C poll events are ignored");
    ok &= Expect(
        !echo_peer::ParseC2CTextEvent("c2c::missing-sender", &event),
        "empty sender is rejected");

    const std::vector<std::string> ids =
        echo_peer::ParseFriendApplicationIds(
            "ALICE\thello\nBOB\twording:with:colons\nmalformed\n\tempty\n");
    ok &= Expect(ids.size() == 2, "only valid application records are returned");
    ok &= Expect(ids.size() > 0 && ids[0] == "ALICE", "first applicant is preserved");
    ok &= Expect(ids.size() > 1 && ids[1] == "BOB", "second applicant is preserved");

    if (ok) {
        std::puts("PASS: echo_peer protocol helpers");
        return 0;
    }
    return 1;
}
