#!/usr/bin/env python3
"""Write the launch_toxee_instance.sh instance.json contract."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json-file", required=True)
    parser.add_argument("--instance-name", required=True)
    parser.add_argument("--pid", required=True, type=int)
    parser.add_argument("--start-time", required=True)
    parser.add_argument("--cmdline", required=True)
    parser.add_argument("--home-override-dir", required=True)
    parser.add_argument("--app-support-override-dir", required=True)
    parser.add_argument("--shared-prefs-prefix", required=True)
    parser.add_argument("--tccf-global-subdir", required=True)
    parser.add_argument("--build-dir", required=True)
    parser.add_argument("--stdio-log", required=True)
    parser.add_argument("--vm-uri-file", required=True)
    parser.add_argument("--vm-uri", required=True)
    parser.add_argument("--ws-uri", required=True)
    parser.add_argument("--app-support-log", required=True)
    parser.add_argument("--default-support-log", required=True)
    # TCP-only pairs: the localhost relay port THIS instance hosts ("" when
    # none), so re-wires can connect each side to the PEER's relay.
    parser.add_argument("--tcp-relay-port", default="")
    # "1" when the instance runs TCP-only (TOX_FORCE_TCP_ONLY); a relaunch
    # restores both from this record (see launch_toxee_instance.sh).
    parser.add_argument("--tcp-only", default="")
    return parser


def main() -> int:
    args = _parser().parse_args()
    doc = {
        "format_version": 1,
        "instance_name": args.instance_name,
        "pid": args.pid,
        "start_time": args.start_time,
        "cmdline": args.cmdline,
        "home_override_dir": args.home_override_dir,
        "app_support_override_dir": args.app_support_override_dir,
        "shared_prefs_prefix": args.shared_prefs_prefix,
        "tccf_global_subdir": args.tccf_global_subdir,
        "build_dir": args.build_dir,
        "stdio_log": args.stdio_log,
        "vm_uri_file": args.vm_uri_file,
        "vm_uri": args.vm_uri,
        "ws_uri": args.ws_uri,
        "tcp_relay_port": args.tcp_relay_port,
        "tcp_only": args.tcp_only.strip().lower() in {"1", "true", "yes"},
        "app_support_log": args.app_support_log,
        "app_support_log_exists": os.path.exists(args.app_support_log),
        "default_support_log": args.default_support_log,
        "default_support_log_exists": os.path.exists(args.default_support_log),
    }
    out = Path(args.json_file)
    out.parent.mkdir(parents=True, exist_ok=True)
    tmp = out.with_suffix(out.suffix + ".tmp")
    tmp.write_text(json.dumps(doc, indent=2) + "\n", encoding="utf-8")
    tmp.replace(out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
