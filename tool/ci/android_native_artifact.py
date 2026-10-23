#!/usr/bin/env python3
"""Inspect staged ELF or final APK/AAB native bytes; this is not store approval."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import sys
import zipfile


ABIS = {"arm64-v8a": (2, 183), "armeabi-v7a": (1, 40),
        "x86_64": (2, 62), "x86": (1, 3)}
REQUIRED = ("libapp.so", "libflutter.so", "libtim2tox_ffi.so")


def inspect_elf(data, abi, label):
    if len(data) < 52 or data[:4] != b"\x7fELF":
        raise ValueError(f"{label}: invalid or truncated ELF header")
    elf_class, machine = ABIS[abi]
    if data[4] != elf_class or data[5] != 1:
        raise ValueError(f"{label}: ELF class/endianness does not match ABI {abi}")
    actual_machine = struct.unpack_from("<H", data, 18)[0]
    if actual_machine != machine:
        raise ValueError(f"{label}: ELF machine {actual_machine} does not match {abi}")
    if elf_class == 2:
        if len(data) < 64:
            raise ValueError(f"{label}: truncated ELF64 header")
        offset = struct.unpack_from("<Q", data, 32)[0]
        size, count = struct.unpack_from("<HH", data, 54)
        minimum = 56
    else:
        offset = struct.unpack_from("<I", data, 28)[0]
        size, count = struct.unpack_from("<HH", data, 42)
        minimum = 32
    if not count or count > 4096 or size < minimum or offset + size * count > len(data):
        raise ValueError(f"{label}: truncated or invalid program-header bounds")
    alignments = []
    for index in range(count):
        start = offset + size * index
        if struct.unpack_from("<I", data, start)[0] != 1:
            continue
        if elf_class == 2:
            _, _, file_offset, address, _, file_size, memory_size, alignment = (
                struct.unpack_from("<IIQQQQQQ", data, start))
        else:
            _, file_offset, address, _, file_size, memory_size, _, alignment = (
                struct.unpack_from("<IIIIIIII", data, start))
        if file_offset + file_size > len(data) or memory_size < file_size:
            raise ValueError(f"{label}: LOAD segment outside ELF bounds")
        required_alignment = 16384 if elf_class == 2 else 4096
        if (alignment < required_alignment or alignment & (alignment - 1)
                or file_offset % alignment != address % alignment):
            raise ValueError(f"{label}: LOAD segment lacks valid "
                             f"{'16 KB' if elf_class == 2 else '4 KB'} alignment")
        alignments.append(alignment)
    if not alignments:
        raise ValueError(f"{label}: no LOAD segments")
    return {"machine": machine, "elf_class": elf_class,
            "load_alignments": alignments}


def zip_data_offset(source, info):
    source.seek(info.header_offset)
    header = source.read(30)
    if len(header) != 30 or header[:4] != b"PK\x03\x04":
        raise ValueError(f"{info.filename}: invalid ZIP local header")
    name_size, extra_size = struct.unpack_from("<HH", header, 26)
    return info.header_offset + 30 + name_size + extra_size


def inspect_archive(path, kind, expected_abis):
    path = Path(path)
    if kind not in ("apk", "aab"):
        raise ValueError("Expected APK or AAB format")
    if not expected_abis or any(abi not in ABIS for abi in expected_abis):
        raise ValueError("Explicit supported expected ABIs are required")
    pattern = (r"lib/([^/]+)/([^/]+\.so)" if kind == "apk"
               else r"[^/]+/lib/([^/]+)/([^/]+\.so)")
    libraries, seen, found_abis, base_names = [], set(), set(), {}
    with zipfile.ZipFile(path) as archive, path.open("rb") as source:
        for info in archive.infolist():
            if info.is_dir() or not info.filename.endswith(".so"):
                continue
            if info.filename in seen:
                raise ValueError(f"duplicate native ZIP entry: {info.filename}")
            seen.add(info.filename)
            match = re.fullmatch(pattern, info.filename)
            if not match:
                raise ValueError(f"Unknown native-library layout: {info.filename}")
            abi, name = match.groups()
            if abi not in expected_abis:
                raise ValueError(f"Unexpected ABI {abi}: {info.filename}")
            if info.file_size > 512 * 1024 * 1024:
                raise ValueError(f"Native payload exceeds inspection limit: {info.filename}")
            found_abis.add(abi)
            if kind == "apk" or info.filename.startswith("base/lib/"):
                base_names.setdefault(abi, set()).add(name)
            data = archive.read(info)
            result = inspect_elf(data, abi, info.filename)
            offset = zip_data_offset(source, info)
            # Bundle ZIP layout is not the delivered APK layout. Compressed APK
            # libraries are extracted instead of mmap'ed directly from the ZIP.
            if kind == "apk" and info.compress_type == zipfile.ZIP_STORED:
                alignment = 16384 if ABIS[abi][0] == 2 else 4096
                if offset % alignment:
                    raise ValueError(f"{info.filename}: uncompressed APK ZIP offset "
                                     f"{offset} is not {alignment}-byte aligned")
            libraries.append({"path": info.filename, "abi": abi,
                              "sha256": hashlib.sha256(data).hexdigest(),
                              "zip_compression": info.compress_type,
                              "zip_data_offset": offset, **result})
    if found_abis != set(expected_abis):
        raise ValueError(f"ABI inventory mismatch: found {sorted(found_abis)}, "
                         f"expected {sorted(expected_abis)}")
    for abi in expected_abis:
        missing = set(REQUIRED) - base_names.get(abi, set())
        if missing:
            raise ValueError(f"{abi}: missing required native libraries: {sorted(missing)}")
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return {"artifact": path.name, "sha256": digest.hexdigest(), "format": kind,
            "abis": sorted(found_abis), "libraries": libraries,
            "evidence_scope": "native headers and archive layout; device loading required"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("artifact", type=Path)
    parser.add_argument("--format", choices=("apk", "aab", "elf"), required=True)
    parser.add_argument("--abis", nargs="+", required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.format == "elf":
            if len(args.abis) != 1 or args.abis[0] not in ABIS:
                raise ValueError("Staged ELF requires exactly one supported ABI")
            data = args.artifact.read_bytes()
            report = {"artifact": args.artifact.name, "format": "elf", "abis": args.abis,
                      "libraries": [{"path": args.artifact.name, "abi": args.abis[0],
                                     "sha256": hashlib.sha256(data).hexdigest(),
                                     **inspect_elf(data, args.abis[0], args.artifact.name)}]}
        else:
            report = inspect_archive(args.artifact, args.format, args.abis)
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2) + "\n")
    except (ValueError, OSError, zipfile.BadZipFile, RuntimeError) as error:
        print(f"Android artifact rejected: {error}", file=sys.stderr)
        return 1
    print(f"Verified {len(report['libraries'])} native libraries: {args.artifact.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
