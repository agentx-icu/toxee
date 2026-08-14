#include "echo_peer_protocol.h"

#include <climits>
#include <string>
#include <vector>

namespace echo_peer {

BoundedReadResult ReadBoundedRecord(
    BoundedRecordReader reader,
    const std::size_t initial_capacity,
    const std::size_t max_capacity,
    std::string* record) {
    if (record == nullptr) {
        return BoundedReadResult::kInvalidLength;
    }
    record->clear();
    if (reader == nullptr || initial_capacity == 0 ||
        initial_capacity > max_capacity ||
        max_capacity > static_cast<std::size_t>(INT_MAX)) {
        return BoundedReadResult::kInvalidLength;
    }

    std::vector<char> buffer(initial_capacity);
    while (true) {
        const int bytes = reader(buffer.data(), static_cast<int>(buffer.size()));
        if (bytes == 0) {
            return BoundedReadResult::kEmpty;
        }
        if (bytes > 0) {
            const std::size_t length = static_cast<std::size_t>(bytes);
            if (length > buffer.size() || length > max_capacity) {
                return BoundedReadResult::kInvalidLength;
            }
            record->assign(buffer.data(), length);
            return BoundedReadResult::kRecord;
        }

        const long long required = -static_cast<long long>(bytes);
        if (required <= static_cast<long long>(buffer.size()) ||
            required > static_cast<long long>(max_capacity)) {
            return BoundedReadResult::kInvalidLength;
        }
        buffer.resize(static_cast<std::size_t>(required));
    }
}

bool ParseC2CTextEvent(const std::string& line, C2CTextEvent* event) {
    if (event == nullptr || line.compare(0, 4, "c2c:") != 0) {
        return false;
    }
    const std::size_t sender_end = line.find(':', 4);
    if (sender_end == std::string::npos || sender_end == 4) {
        return false;
    }
    event->sender = line.substr(4, sender_end - 4);
    // The payload is opaque and can contain newlines; the queue stores one
    // record per poll, so only the sender boundary is parsed here.
    event->payload = line.substr(sender_end + 1);
    return true;
}

std::vector<std::string> ParseFriendApplicationIds(
    const std::string& applications) {
    std::vector<std::string> ids;
    std::size_t line_start = 0;
    while (line_start < applications.size()) {
        std::size_t line_end = applications.find('\n', line_start);
        if (line_end == std::string::npos) {
            line_end = applications.size();
        }
        const std::size_t separator = applications.find('\t', line_start);
        if (separator != std::string::npos && separator < line_end &&
            separator > line_start) {
            ids.push_back(applications.substr(line_start,
                                              separator - line_start));
        }
        line_start = line_end + 1;
    }
    return ids;
}

}
