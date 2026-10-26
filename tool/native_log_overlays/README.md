# Bounded local logging overlay

This app-owned overlay modifies exactly Tim2Tox
`5341e64ed62b81a94a311c768a73863a3cffcbb1`; it neither advances the
submodule nor publishes another repository. `manifest.json` records every
before/after source hash (the new header has an absent-before value) and the
patch hash. Bootstrap applies pristine sources, accepts verified outputs
idempotently, and rejects revision drift, partial application, links, unknown
files at the new-header path and out-of-inventory patch paths without resets.
The offline check and native cache keys include the overlay.

`V2TIMLog` owns the sole file sink, mutex and process-local generation. The
controlled C ABI exposes configure/append/release; only the sanitized AppLogger
boundary may send application text. The transport is not a sanitizer. Native
threads retain their typed events; SDK legacy setters cannot steal a managed
owner. Statuses are closed: 0 success, 1 visible UTF-8 truncation, 2 invalid,
3 unsafe path, 4 configure I/O with no owner, 5 wrong owner, 6 partial I/O with
confirmed release, 7 busy, 8 uncertain. A generation-zero release only confirms
this process has no file owner; it must not clear a prior BUSY/unsafe refusal
into permission to delete another owner's files.

The fixed production budget is ten segments of 10 MiB including the active
file and retained sessions; each input record retains at most 64 KiB with an
explicit omitted-byte marker. Rotation happens before writing, never replaces
an existing history name, and trims oversized legacy files in place to retain
the recent tail with a fixed omission notice. Canonical `app_<timestamp>.log`
sessions share the ledger. Custom/harness numeric-suffix roots plus extensions each have the same
budget and remain independent. A zero-byte family lock is ownership metadata,
not an eleventh diagnostic segment. A second process in the same family gets
BUSY without disrupting the SDK/app; independent harness families can persist
concurrently. This is not cross-process log merging.

Dart resolves an established parent, including normal OS aliases, before
secure native opens. Linux/Android walks ancestors using no-follow `O_PATH`
directory references and opens the final ledger directory for reading;
search-only ancestors do not need enumeration permission. Darwin opens only
the readable final directory with `O_DIRECTORY|O_NOFOLLOW`, then verifies that
the held fd's public `F_GETPATH` exactly matches the canonical physical parent
before any mutation. All later operations use that same directory fd. This
uses APIs present in the supported macOS 10.15 source, without relying on a
newer kernel's `O_SEARCH`; it is not an old-device qualification. See Apple's
[fcntl contract](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/fcntl.2.html)
and [10.15-era implementation](https://github.com/apple-oss-distributions/xnu/blob/xnu-6153.11.26/bsd/kern/kern_descrip.c#L1626).
POSIX also checks actual inode/link identity. Windows holds physical parent handles and rejects
reparse points and multiple links on the actual file handles. Clear-logs
requires confirmed close before deleting. Refused/uncertain ownership never
falls back to another file writer. When native logging is unavailable, bounded
safe memory/stderr diagnostics continue; buffered records can be lost on exit.
No remote collector, crash handler or new product permission is introduced.

Run the real source regressions after bootstrap:

```sh
python3 tool/ci/test_native_log_retention.py --evidence build/evidence/native-log-retention.json
flutter test test/tool/bootstrap_native_log_overlay_test.dart
```

The native regression compiles the pristine pinned writer to reproduce the
original oversized-file defect, then compiles the actual overlaid writer with
the same legacy producer, more than 120 MiB from four concurrent producers,
twelve sessions, original-size UTF-8 truncation, old-tail repair, two-process
ownership, independent harness families, Unicode paths and link negatives.
POSIX additionally exercises a legal search-only ancestor, unreadable or
unsearchable ledger rejection, ancestor replacement during a held owner and
rotation, actual kernel write refusal and a test-link-only failed directory
enumeration. There is no production test hook or reduced
budget. MSVC C++20 must be available when running the Windows probe. Reports
qualify only the actual CI OS/architecture; iOS/Android compilation does not
replace on-device storage/crash qualification.
