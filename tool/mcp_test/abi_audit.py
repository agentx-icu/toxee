#!/usr/bin/env python3
"""Audit the native `Dart*` FFI surface against the generated Dart binding.

The binding (`native_imsdk_bindings_generated.dart`) is the ABI truth: it is what
the patched Tencent SDK actually calls through `NativeLibraryManager`. Every
`Dart*` symbol tim2tox implements in `ffi/dart_compat_*.cpp` (plus the few in
`ffi/callback_bridge.cpp`) must byte-match it.

Three failure classes, in descending nastiness:

  * MISSING   — Dart declares + calls a symbol C++ never defines. `_lookup` is
                `late final`, so this is not a startup failure: the FIRST CALL
                throws `ArgumentError: Failed to lookup symbol`, the Future
                completes with an error, and the feature silently does nothing.
  * MISMATCH  — same name, different signature. Arg-count and pointer-vs-scalar
                drift misaligns the whole frame (that was the
                DartSetC2CReceiveMessageOpt SIGSEGV). Integer WIDTH drift is
                subtler: on arm64/x86_64 a 64-bit argument read as 32-bit merely
                truncates, but on armeabi-v7a (a supported ABI — see
                tool/build_android_ffi.sh and tool/ci/build_tim2tox.sh) AAPCS
                puts a 64-bit argument in an even/odd register PAIR, so every
                later argument shifts and `user_data` is dereferenced as garbage.
  * EXTRA     — C++ exports a `Dart*` the binding never looks up. Usually fine
                (tim2tox's own FFI binding uses some), occasionally dead code.

Why this was rewritten (2026-08-08): the previous version hardcoded
`REPO = "/Users/bin.gao/chat-uikit/toxee"` (unrunnable anywhere else), matched
only `int`-returning C++ functions (so it saw 80 of ~158 definitions and none of
the `void DartSet*Callback` family), used `[^)]*` for argument lists (breaks on
function-pointer and template args), never scanned callback_bridge.cpp, and did
not compare integer width or signedness at all. It reported "0 mismatches".

Usage:
    python3 tool/mcp_test/abi_audit.py [--json] [--quiet]

Exit codes:
    0  no MISMATCH and no non-allowlisted MISSING
    1  drift found
    2  inputs missing / nothing parsed (never reports a clean bill in this case)
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass, field


def repo_root() -> str:
    env = os.environ.get("TOXEE_REPO_ROOT")
    if env:
        return env
    here = os.path.dirname(os.path.abspath(__file__))
    try:
        out = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            cwd=here,
            capture_output=True,
            text=True,
            check=True,
        )
        return out.stdout.strip()
    except Exception:
        # tool/mcp_test/abi_audit.py -> repo root is two levels up.
        return os.path.abspath(os.path.join(here, "..", ".."))


REPO = repo_root()
GEN = os.path.join(
    REPO,
    "third_party/tencent_cloud_chat_sdk/lib/native_im/bindings",
    "native_imsdk_bindings_generated.dart",
)
NATIVE_DIRS = [os.path.join(REPO, "third_party/tim2tox/ffi")]

# Symbols the binding declares that tim2tox deliberately does not implement,
# because the capability does not exist on a Tox P2P backend: cloud-side search,
# official accounts / follow graph, Community+Topic+PermissionGroup, server-side
# conversation and friend GROUPING. Anything NOT matched here that shows up as
# MISSING is a real gap the SDK adapter can reach at runtime.
#
# Append-only, with justification. That is the point of the gate: a newly
# missing symbol has to be an explicit decision, not a silent one.
ALLOWED_MISSING_PREFIXES = (
    "DartCreateCommunity",
    "DartCreateTopic",
    "DartDeleteTopic",
    "DartGetCommunity",
    "DartGetTopic",
    "DartSetTopic",
    "DartCreatePermissionGroup",
    "DartDeletePermissionGroup",
    "DartGetPermissionGroup",
    "DartModifyPermissionGroup",
    "DartAddPermissionGroupMember",
    "DartDeletePermissionGroupMember",
    "DartGetPermissionGroupMember",
    "DartFollow",
    "DartUnfollow",
    "DartGetMyFollow",
    "DartGetMutualFollow",
    "DartGetUserFollowInfo",
    "DartCheckFollowType",
    "DartSubscribeOfficialAccount",
    "DartUnsubscribeOfficialAccount",
    "DartGetOfficialAccount",
    "DartSearchCloud",
    "DartSearchUsers",
    "DartSearchGroupMembers",
    "DartCreateConversationGroup",
    "DartDeleteConversationGroup",
    "DartRenameConversationGroup",
    "DartGetConversationGroupList",
    "DartAddConversationsToGroup",
    "DartDeleteConversationsFromGroup",
    "DartCreateFriendGroup",
    "DartDeleteFriendGroup",
    "DartModifyFriendGroup",
    "DartGetFriendGroupList",
)

# Ratchet baseline: symbols that ARE missing today and are real capability gaps
# (not "impossible on Tox" — those go in ALLOWED_MISSING_PREFIXES above). They
# are listed so this tool can run as a CI gate that fails on NEW gaps while the
# existing debt is worked down. Removing an entry after implementing it is the
# intended direction; adding one requires a deliberate edit and review.
#
# Snapshot taken 2026-08-08, right after DartSetGroupReceiveMessageOpt was
# implemented and DartSetOfflinePushToken / DartDoForeground / DartTranslateText
# / DartConvertVoiceToText got explicit not-supported stubs.
KNOWN_MISSING = {
    # Cloud-side group metadata (attributes / counters).
    "DartInitGroupAttributes",
    "DartSetGroupAttributes",
    "DartGetGroupAttributes",
    "DartDeleteGroupAttributes",
    "DartSetGroupCounters",
    "DartGetGroupCounters",
    "DartIncreaseGroupCounter",
    "DartDecreaseGroupCounter",
    # Group join-approval flow.
    "DartGetGroupPendencyList",
    "DartHandleGroupPendency",
    "DartMarkGroupMemberList",
    "DartGetOnlineMemberCount",
    # Message reactions / server-side extensions.
    "DartGetMessageReactions",
    "DartGetAllUserListOfMessageReaction",
    "DartSetMessageExtensions",
    "DartGetMessageExtensions",
    "DartDeleteMessageExtensions",
    # Read receipts.
    "DartGetMessageReadReceipts",
    "DartSendMessageReadReceipts",
    "DartGetGroupMessageReadMemberList",
    # Pinned group messages.
    "DartPinGroupMessage",
    "DartGetPinnedGroupMessageList",
    # Subscriptions. NOTE: the matching callbacks ARE implemented, so these
    # register listeners that can never fire.
    "DartSubscribeUserStatus",
    "DartUnsubscribeUserStatus",
    "DartSubscribeUnreadMessageCountByFilter",
    "DartUnsubscribeUnreadMessageCountByFilter",
    # Misc.
    "DartDeleteFriendApplication",
    "DartSetConversationCustomData",
    "DartRemoveReceiveNewMsgCallback",  # potential callback leak
    # Community / Topic / PermissionGroup leftovers whose names do not share a
    # prefix with the allowlist entries above.
    "DartAddCommunityMembersToPermissionGroup",
    "DartRemoveCommunityMembersFromPermissionGroup",
    "DartAddTopicPermissionToPermissionGroup",
    "DartModifyTopicPermissionInPermissionGroup",
    "DartGetJoinedCommunityList",
    "DartGetJoinedPermissionGroupListInCommunity",
}

# --- type model: (kind, bits, signed); `signed` is None where meaningless -----

VOID = ("void", 0, None)
PTR = ("ptr", 64, None)
BOOL = ("bool", 8, None)

DART_TYPES = {
    "ffi.Void": VOID,
    "ffi.Bool": BOOL,
    "ffi.Int": ("int", 32, True),
    "ffi.Int32": ("int", 32, True),
    "ffi.UnsignedInt": ("int", 32, False),
    "ffi.Uint32": ("int", 32, False),
    "ffi.Int64": ("int", 64, True),
    "ffi.Uint64": ("int", 64, False),
    "ffi.IntPtr": ("int", 64, True),
    "ffi.Float": ("flt", 32, None),
    "ffi.Double": ("flt", 64, None),
    "Dart_Port": ("int", 64, True),  # typedef Dart_Port = ffi.Int64;
}

CPP_TYPES = {
    "void": VOID,
    "bool": BOOL,
    "_Bool": BOOL,
    "char": ("int", 8, True),
    "int": ("int", 32, True),
    "signed int": ("int", 32, True),
    "int32_t": ("int", 32, True),
    "unsigned": ("int", 32, False),
    "unsigned int": ("int", 32, False),
    "uint32_t": ("int", 32, False),
    "int64_t": ("int", 64, True),
    "long": ("int", 64, True),
    "long long": ("int", 64, True),
    "intptr_t": ("int", 64, True),
    "uint64_t": ("int", 64, False),
    "unsigned long": ("int", 64, False),
    "unsigned long long": ("int", 64, False),
    "size_t": ("int", 64, False),
    "uintptr_t": ("int", 64, False),
    "float": ("flt", 32, None),
    "double": ("flt", 64, None),
}


def split_top_level(s: str) -> list:
    """Split on commas not nested inside <>, () or []."""
    out, cur, depth = [], "", 0
    for ch in s:
        if ch in "<([":
            depth += 1
        elif ch in ">)]":
            depth -= 1
        if ch == "," and depth == 0:
            out.append(cur.strip())
            cur = ""
        else:
            cur += ch
    if cur.strip():
        out.append(cur.strip())
    return out


def dart_type(raw: str):
    t = re.sub(r"\s+", " ", raw).strip()
    if t.startswith("ffi.Pointer") or t.startswith("ffi.NativeFunction"):
        return PTR
    return DART_TYPES.get(t)


def cpp_type(raw: str):
    t = re.sub(r"\s+", " ", raw).strip()
    if "(*" in t:  # function-pointer parameter
        return PTR
    t = re.sub(r"\b(const|volatile|struct|enum|class|static|extern|inline)\b", " ", t)
    t = re.sub(r"\s+", " ", t).strip()
    if "*" in t or "&" in t or t.endswith("[]"):
        return PTR
    parts = t.split()
    for n in (3, 2, 1):
        if len(parts) >= n:
            cand = " ".join(parts[:n])
            if cand in CPP_TYPES:
                return CPP_TYPES[cand]
    return None


@dataclass
class Sig:
    name: str
    ret: tuple
    args: list = field(default_factory=list)
    where: str = ""


def parse_dart(path: str) -> dict:
    txt = open(path, encoding="utf-8").read()
    out: dict = {}
    pat = re.compile(r"_lookup<\s*ffi\.NativeFunction<\s*(.*?)>>\(\s*'(\w+)'\s*\)", re.S)
    for m in pat.finditer(txt):
        sig, name = re.sub(r"\s+", " ", m.group(1)), m.group(2)
        if not name.startswith("Dart"):
            continue
        fm = re.search(r"^(.*?)\bFunction\((.*)\)$", sig)
        if not fm:
            continue
        ret = dart_type(fm.group(1)) or ("?", 0, None)
        args = [dart_type(a) or ("?", 0, None) for a in split_top_level(fm.group(2))]
        line = txt.count("\n", 0, m.start()) + 1
        out[name] = Sig(name, ret, args, f"{os.path.relpath(path, REPO)}:{line}")
    return out


CPP_DEF = re.compile(r"^[ \t]*((?:[A-Za-z_][\w:<>*&\s]*?))\b(Dart\w+)\s*\(", re.M)


def parse_cpp(dirs: list) -> dict:
    out: dict = {}
    for d in dirs:
        if not os.path.isdir(d):
            continue
        for fn in sorted(os.listdir(d)):
            if not fn.endswith((".cpp", ".cc", ".c")):
                continue
            path = os.path.join(d, fn)
            txt = open(path, encoding="utf-8", errors="replace").read()
            for m in CPP_DEF.finditer(txt):
                ret_raw, name = m.group(1), m.group(2)
                i = m.end() - 1  # index of the '('
                depth, j = 0, i
                while j < len(txt):
                    if txt[j] == "(":
                        depth += 1
                    elif txt[j] == ")":
                        depth -= 1
                        if depth == 0:
                            break
                    j += 1
                arglist = txt[i + 1 : j]
                # Only definitions (a body follows) — skip declarations/calls.
                if not txt[j + 1 : j + 200].lstrip().startswith("{"):
                    continue
                args = []
                for a in split_top_level(arglist):
                    if a in ("void", ""):
                        continue
                    args.append(cpp_type(a) or ("?", 0, None))
                line = txt.count("\n", 0, m.start()) + 1
                out.setdefault(
                    name,
                    Sig(
                        name,
                        cpp_type(ret_raw) or ("?", 0, None),
                        args,
                        f"{os.path.relpath(path, REPO)}:{line}",
                    ),
                )
    return out


def describe(t: tuple) -> str:
    kind, bits, signed = t
    if kind in ("void", "ptr", "bool", "?"):
        return kind
    if kind == "int":
        return f"{'i' if signed else 'u'}{bits}"
    return f"{kind}{bits}"


def compare(dart: Sig, cpp: Sig) -> list:
    problems = []
    if len(dart.args) != len(cpp.args):
        return [f"arg count: dart={len(dart.args)} cpp={len(cpp.args)}"]
    for i, (d, c) in enumerate(zip(dart.args, cpp.args)):
        if "?" in (d[0], c[0]):
            continue
        if d[0] != c[0]:
            problems.append(f"arg{i} KIND: dart={describe(d)} cpp={describe(c)}")
        elif d[0] == "int" and d[1] != c[1]:
            problems.append(f"arg{i} WIDTH: dart={describe(d)} cpp={describe(c)}")
        elif d[0] == "int" and d[2] != c[2]:
            problems.append(f"arg{i} signedness: dart={describe(d)} cpp={describe(c)}")
    d, c = dart.ret, cpp.ret
    if "?" not in (d[0], c[0]):
        if d[0] != c[0]:
            problems.append(f"return KIND: dart={describe(d)} cpp={describe(c)}")
        elif d[0] == "int" and d[1] != c[1]:
            problems.append(f"return WIDTH: dart={describe(d)} cpp={describe(c)}")
    return problems


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()

    if not os.path.isfile(GEN):
        print(f"abi_audit: generated binding not found: {GEN}", file=sys.stderr)
        print("abi_audit: run `dart run tool/bootstrap_deps.dart` first.", file=sys.stderr)
        return 2

    dart = parse_dart(GEN)
    cpp = parse_cpp(NATIVE_DIRS)
    if not dart or not cpp:
        print(
            f"abi_audit: parsed dart={len(dart)} cpp={len(cpp)}; "
            "refusing to report a clean bill.",
            file=sys.stderr,
        )
        return 2

    mismatches, missing, missing_allowed, missing_known, extra = [], [], [], [], []
    for name, dsig in sorted(dart.items()):
        if name not in cpp:
            entry = {"name": name, "dart": dsig.where}
            if name.startswith(ALLOWED_MISSING_PREFIXES):
                missing_allowed.append(entry)
            elif name in KNOWN_MISSING:
                missing_known.append(entry)
            else:
                missing.append(entry)
            continue
        probs = compare(dsig, cpp[name])
        if probs:
            mismatches.append(
                {
                    "name": name,
                    "dart": dsig.where,
                    "cpp": cpp[name].where,
                    "problems": probs,
                }
            )
    for name, csig in sorted(cpp.items()):
        if name not in dart:
            extra.append({"name": name, "cpp": csig.where})

    # A KNOWN_MISSING entry that is now implemented should be removed from the
    # set, otherwise the baseline quietly stops meaning anything.
    stale_baseline = sorted(n for n in KNOWN_MISSING if n in cpp or n not in dart)

    result = {
        "dart_symbols": len(dart),
        "cpp_symbols": len(cpp),
        "mismatches": mismatches,
        "missing": missing,
        "missing_known_baseline": missing_known,
        "missing_allowlisted": missing_allowed,
        "stale_baseline_entries": stale_baseline,
        "extra": extra,
    }

    if args.json:
        print(json.dumps(result, indent=2))
    elif not args.quiet:
        print(f"dart binding symbols : {len(dart)}")
        print(f"cpp defined symbols  : {len(cpp)}")
        print()
        print(f"MISMATCH ({len(mismatches)}):")
        for m in mismatches:
            print(f"  {m['name']}")
            print(f"    dart {m['dart']}")
            print(f"    cpp  {m['cpp']}")
            for p in m["problems"]:
                print(f"    -> {p}")
        print()
        print(f"MISSING, NEW (not allowlisted, not in baseline) ({len(missing)}):")
        for m in missing:
            print(f"  {m['name']}   ({m['dart']})")
        print()
        print(f"MISSING, known capability gaps (baseline): {len(missing_known)}")
        print(f"MISSING, allowlisted as unsupported-on-Tox: {len(missing_allowed)}")
        if stale_baseline:
            print()
            print(f"STALE baseline entries — implemented or gone, remove them "
                  f"({len(stale_baseline)}):")
            for n in stale_baseline:
                print(f"  {n}")
        print()
        print(f"EXTRA, C++ only ({len(extra)}):")
        for m in extra:
            print(f"  {m['name']}   ({m['cpp']})")

    return 1 if (mismatches or missing or stale_baseline) else 0


if __name__ == "__main__":
    sys.exit(main())
