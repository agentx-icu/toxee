# Bounded local logging overlay

This app-owned overlay modifies exactly Tim2Tox
`98c5b25d9ed27dad4a544b077675b0978d82d73d`; it neither advances the
submodule nor publishes another repository. `manifest.json` records every
before/after source hash (new headers have absent-before values) and the
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
budget and remain independent. The existing family lock inode holds exactly
1024 bytes of bounded ownership/order metadata, outside the ten `.log` segments. A second process in the same family gets
BUSY without disrupting the SDK/app; independent harness families can persist
concurrently. This is not cross-process log merging.

Each successful claim, including a short session or a reused custom active path,
receives a fresh family-wide rank before writing any body. The fixed 1 KiB
index has two 512-byte versioned/checksummed snapshots of a monotonic counter
and at most ten actual file identities/ranks (POSIX device/inode; Windows
volume/file index). Both copies are flushed before new body bytes are allowed.
Rotation keeps the archived inode's rank; suffix reuse, tied timestamps and
wall-clock rollback cannot make that new archive older. Victims are unlinked
before their identities are removed from the durable index, and that removal
is flushed before a new active file is created and bound to its fresh rank.
The lock inode is never renamed, and no sidecar, log-header change or per-record
fsync is introduced.

Only an initial zero-byte pre-upgrade lock permits legacy bootstrap. Its entire
safe inventory is ordered by subsecond mtime and numeric filename order; exact
legacy ties have no recoverable true chronology. An overfull legacy population
is pruned to the existing budget before the first bounded index commit, with
no managed body written during bootstrap. Later missing identities are
reconciled, but an unknown nonempty file (external copy/restore/replacement),
invalid/oversized index, duplicate identity/rank or exhausted counter is
refused, never silently treated as a fresh legacy ledger. A created-but-empty
unbound file can be claimed and indexed before its first body. One intact slot
recovers a damaged copy; two invalid slots require explicit owner action.
Metadata partial writes or flush failures remain uncertain and cannot permit
clear-logs deletion or replay. After all writers are stopped/confirmed closed,
the owner may explicitly remove unwanted restored files or clear the family,
then reclaim it; refusal itself never deletes them. This does not qualify a
backup/restore or previous-release upgrade flow. Existing iOS logs backup
exclusion and profile migration scope are unchanged.

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
enumeration. The ordering fixture additionally checks retained recent content,
sixteen tied/rollback rotations across restarts, short sessions/custom reclaim,
either damaged slot, malformed/duplicate/overflow metadata, external identity
replacement, and POSIX partial/flush failure plus victim-identity substitution.
Its three-symbol source adapter is not the complete app FFI; full-library
qualification runs separately. There is no production test hook or reduced
budget. MSVC C++20 must be available when running the Windows probe. Reports
qualify only the actual CI OS/architecture; iOS/Android compilation does not
replace on-device storage/crash qualification.
