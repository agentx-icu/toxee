# FFI Reentrancy Audit Tests

Companion to `docs/audits/2026-05-16-ffi-reentrancy-audit.md`. One test
file per matrix row. Each test exercises the surface against the real
`libtim2tox_ffi.dylib` where the test environment allows (no network
bootstrap required), and falls back to a code-inspection assertion with
file:line citations where a real FFI call is impractical inside
`flutter test`.

The tests are not gates on PR 4 — the audit doc is the gate. The tests
document the basis for the verdict so a future refactor can re-run them
and see whether the assumptions still hold.

To run:

```bash
flutter test test/ffi_audit/
```

If the native library is missing, set up a build:

```bash
cd third_party/tim2tox && ./build.sh
# Then symlink to the hardcoded path used by Tim2ToxFfi.open() on macOS:
mkdir -p /Users/$(whoami)/chat-uikit/tim2tox/build/ffi
ln -sf "$(pwd)/build/ffi/libtim2tox_ffi.dylib" \
       /Users/$(whoami)/chat-uikit/tim2tox/build/ffi/libtim2tox_ffi.dylib
```
