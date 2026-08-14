#pragma once

#include <cstddef>
#include <string>
#include <vector>

namespace echo_peer {

struct C2CTextEvent {
    std::string sender;
    std::string payload;
};

enum class BoundedReadResult {
    kEmpty,
    kRecord,
    kInvalidLength,
};

using BoundedRecordReader = int (*)(char*, int);

BoundedReadResult ReadBoundedRecord(
    BoundedRecordReader reader,
    std::size_t initial_capacity,
    std::size_t max_capacity,
    std::string* record);
bool ParseC2CTextEvent(const std::string& line, C2CTextEvent* event);
std::vector<std::string> ParseFriendApplicationIds(const std::string& applications);

}
