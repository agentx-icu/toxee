#!/usr/bin/env bash
# Prove that the toxee echo-peer harness consumes Tim2Tox exclusively through
# its public C FFI boundary. This replaces the old byte-drift comparison with
# the upstream direct-C++ example: the local peer is intentionally no longer
# derived from, or linked like, that example.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE_DIR="${ECHO_PEER_SOURCE_DIR:-$REPO_ROOT/tool/mcp_test/echo_peer_src}"
MAIN_SOURCE="${ECHO_PEER_MAIN_SOURCE:-$SOURCE_DIR/echo_peer.cpp}"
CMAKE_FILE="${ECHO_PEER_CMAKE_FILE:-$SOURCE_DIR/CMakeLists.txt}"
FFI_HEADER="${ECHO_PEER_FFI_HEADER:-$REPO_ROOT/third_party/tim2tox/ffi/tim2tox_ffi.h}"
PEER_BIN="${ECHO_PEER_BIN:-$SOURCE_DIR/build/echo_peer}"
PROTOCOL_TEST_BIN="${ECHO_PEER_PROTOCOL_TEST_BIN:-$SOURCE_DIR/build/echo_peer_protocol_test}"
CONTRACT_SMOKE="${ECHO_PEER_CONTRACT_SMOKE:-$REPO_ROOT/tool/mcp_test/echo_peer_contract_smoke.sh}"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

for required in "$MAIN_SOURCE" "$CMAKE_FILE" "$FFI_HEADER" "$CONTRACT_SMOKE"; do
    [[ -f "$required" ]] || fail "required_file status=missing"
done
[[ -x "$PEER_BIN" ]] || fail "echo_peer status=missing"
[[ -x "$PROTOCOL_TEST_BIN" ]] || fail "protocol_test status=missing"

echo "echo_peer C-FFI boundary/provenance check"
echo "  source status: present"
echo "  ffi header status: present"
echo "  echo_peer status: present"
echo "  protocol_test status: present"

shopt -s nullglob
source_files=("$SOURCE_DIR"/*.c "$SOURCE_DIR"/*.cc "$SOURCE_DIR"/*.cpp \
              "$SOURCE_DIR"/*.h "$SOURCE_DIR"/*.hpp)
shopt -u nullglob
if grep -Eq '(^|[^[:alnum:]_])(V2TIM[[:alnum:]_]*|ToxManager|ToxAVManager|ToxUtil)([^[:alnum:]_]|$)' "${source_files[@]}"; then
    fail "direct C++ SDK identifier found under echo_peer_src"
fi
if grep -Eq '(^|[^[:alnum:]_])tox_[[:alnum:]_]*[[:space:]]*\(' "${source_files[@]}"; then
    fail "direct Tox API symbol found under echo_peer_src"
fi
if grep -Eq '^[[:space:]]*#[[:space:]]*include[[:space:]]*[<"][^>"]*(tim2tox/|tox/|tox\.h)[^>"]*[>"]' "${source_files[@]}"; then
    fail "direct Tim2Tox or Tox include found under echo_peer_src"
fi
if grep -Eq 'extern[[:space:]]+"C".*tim2tox_ffi_' "${source_files[@]}"; then
    fail "hand-written Tim2Tox C FFI declaration found under echo_peer_src"
fi

if ! /usr/bin/python3 - "$MAIN_SOURCE" "$CMAKE_FILE" <<'PY'
import pathlib
import re
import sys

main = pathlib.Path(sys.argv[1]).read_text()
cmake = pathlib.Path(sys.argv[2]).read_text()

if not re.search(r'^[ \t]*#[ \t]*include[ \t]*[<"]tim2tox_ffi\.h[>"]', main, re.M):
    sys.exit(1)

position = 0
markers = ("std::printf(", "std::fprintf(")
while position < len(main):
    starts = [main.find(marker, position) for marker in markers]
    starts = [start for start in starts if start >= 0]
    if not starts:
        break
    start = min(starts)
    end = main.find(";", start)
    if end < 0:
        sys.exit(1)
    statement = main[start:end]
    if "%s" in statement:
        allowed_identity_line = (
            statement.startswith("std::printf(")
            and "ECHO_PEER_TOX_ID: %s" in statement
            and "tox_id.c_str()" in statement
        )
        if not allowed_identity_line:
            sys.exit(1)
    position = end + 1
if any(stream in main for stream in ("std::cout", "std::cerr", "std::clog")):
    sys.exit(1)

def calls(source, name):
    pattern = re.compile(r'\b' + re.escape(name) + r'\s*\(')
    result = []
    for match in pattern.finditer(source):
        depth = 1
        quote = None
        escaped = False
        position = match.end()
        while position < len(source) and depth:
            character = source[position]
            if quote is not None:
                if escaped:
                    escaped = False
                elif character == '\\':
                    escaped = True
                elif character == quote:
                    quote = None
            elif character in ('"', "'"):
                quote = character
            elif character == '(':
                depth += 1
            elif character == ')':
                depth -= 1
            position += 1
        if depth:
            sys.exit(1)
        result.append(source[match.end():position - 1])
    return result

def tokens(body):
    return [token.strip('"\'') for token in re.findall(
        r'"(?:\\.|[^"])*"|\'(?:\\.|[^\'])*\'|[^\s]+', body)]

allowed_commands = {
    'add_executable',
    'add_library',
    'add_test',
    'cmake_minimum_required',
    'else',
    'elseif',
    'enable_testing',
    'endif',
    'get_filename_component',
    'if',
    'message',
    'project',
    'set',
    'set_target_properties',
    'target_include_directories',
    'target_link_libraries',
}
commands = re.findall(r'^[ \t]*([A-Za-z_][A-Za-z0-9_]*)[ \t]*\(', cmake, re.M)
if any(command.lower() not in allowed_commands for command in commands):
    sys.exit(1)

if re.search(r'\blibtim2tox(?!_ffi\b)', cmake, re.I):
    sys.exit(1)
if re.search(r'\$\{TIM2TOX_ROOT\}/(?:include|source)(?:[/}"\s]|$)', cmake):
    sys.exit(1)
if re.search(r'\badd_subdirectory\s*\(', cmake):
    sys.exit(1)
for forbidden in (
    'include_directories',
    'link_directories',
    'link_libraries',
    'target_link_directories',
    'target_sources',
    'set_property',
):
    if calls(cmake, forbidden):
        sys.exit(1)

if [tokens(call) for call in calls(cmake, 'add_library')] != [
    ['tim2tox_ffi', 'SHARED', 'IMPORTED'],
    ['echo_peer_protocol', 'STATIC', 'echo_peer_protocol.cpp'],
]:
    sys.exit(1)
if [tokens(call) for call in calls(cmake, 'add_executable')] != [
    ['echo_peer', 'echo_peer.cpp'],
    ['echo_peer_protocol_test', 'echo_peer_protocol_test.cpp'],
]:
    sys.exit(1)
if [tokens(call) for call in calls(cmake, 'target_include_directories')] != [
    ['echo_peer_protocol', 'PUBLIC', '${CMAKE_CURRENT_SOURCE_DIR}'],
]:
    sys.exit(1)
if [tokens(call) for call in calls(cmake, 'target_link_libraries')] != [
    ['echo_peer', 'PRIVATE', 'echo_peer_protocol', 'tim2tox_ffi'],
    ['echo_peer_protocol_test', 'PRIVATE', 'echo_peer_protocol'],
]:
    sys.exit(1)
if [tokens(call) for call in calls(cmake, 'set_target_properties')] != [
    [
        'tim2tox_ffi', 'PROPERTIES', 'IMPORTED_LOCATION',
        '${TIM2TOX_FFI_LIB}', 'INTERFACE_INCLUDE_DIRECTORIES',
        '${TIM2TOX_ROOT}/ffi',
    ],
    [
        'echo_peer', 'PROPERTIES', 'INSTALL_RPATH',
        '${TIM2TOX_ROOT}/build/ffi', 'BUILD_WITH_INSTALL_RPATH', 'TRUE',
    ],
]:
    sys.exit(1)
PY
then
    fail "echo_peer canonical include/link configuration violated"
fi
if grep -Eq 'value=\$PEER_ID|v[12]=\$PEER_ID' "$CONTRACT_SMOKE"; then
    fail "contract smoke exposes a raw identity payload"
fi

while IFS= read -r symbol; do
    [[ -n "$symbol" ]] || continue
    grep -Fq "$symbol(" "$FFI_HEADER" || \
        fail "$symbol is used by echo_peer but not declared in tim2tox_ffi.h"
done < <(grep -Eo 'tim2tox_ffi_[A-Za-z0-9_]+[[:space:]]*\(' "$MAIN_SOURCE" \
    | tr -d ' (' | sort -u)

if nm -u "$PEER_BIN" | grep -q 'V2TIM'; then
    nm -u "$PEER_BIN" | grep 'V2TIM' >&2 || true
    fail "built echo_peer has undefined direct C++ SDK symbols"
fi
tim2tox_dep_count=0
tim2tox_dependency=""
while IFS= read -r dependency; do
    [[ -n "$dependency" ]] || continue
    tim2tox_dep_count=$((tim2tox_dep_count + 1))
    tim2tox_dependency="$dependency"
done < <(otool -L "$PEER_BIN" \
    | grep -E 'libtim2tox[^/]*\.(dylib|so)' \
    | sed -E 's/^[[:space:]]*([^[:space:]]+).*/\1/')
[[ "$tim2tox_dep_count" -eq 1 ]] || \
    fail "expected exactly one Tim2Tox dynamic dependency, found $tim2tox_dep_count"
[[ "$tim2tox_dependency" == *libtim2tox_ffi.dylib ]] || \
    fail "Tim2Tox dynamic dependency status=unexpected"

echo "PASS: echo_peer stays on the canonical Tim2Tox C FFI boundary"
