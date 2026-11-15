#!/usr/bin/env python3
# Derived from Mornye (https://github.com/mornyeapp/Mornye), Copyright 2026 zarzet,
# LGPL-3.0-only. Modified for Kalao.
"""Check that a release APK contains the Rust backend for exactly the expected ABIs."""

import argparse
import hashlib
import struct
import sys
import zipfile
import zlib
from pathlib import Path
from typing import Iterable, Optional, Sequence, Tuple

# ABI -> (ELF class, e_machine)
ABI_LAYOUT = {
    "arm64-v8a": (2, 183),
    "armeabi-v7a": (1, 40),
    "x86_64": (2, 62),
}
CORE_LIBRARIES = ("libapp.so", "libflutter.so")
BACKEND_LIBRARIES = ("libkalao_mobile.so", "libjnidispatch.so")
PAGE_ALIGNMENT = 16 * 1024
PT_LOAD = 1


class AuditError(Exception):
    pass


def parse_abis(raw: str) -> Tuple[str, ...]:
    abis = tuple(part.strip() for part in raw.split(",") if part.strip())
    if not abis:
        raise AuditError("--abis must contain at least one ABI")
    unknown = sorted(set(abis) - set(ABI_LAYOUT))
    if unknown:
        raise AuditError("unsupported ABI(s): " + ", ".join(unknown))
    if len(set(abis)) != len(abis):
        raise AuditError("--abis contains a duplicate ABI")
    return abis


def artifact_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def required_entry(infos: Sequence[zipfile.ZipInfo], path: str) -> zipfile.ZipInfo:
    matches = [info for info in infos if info.filename == path and not info.is_dir()]
    if not matches:
        raise AuditError("missing APK entry: " + path)
    if len(matches) > 1:
        raise AuditError("duplicate APK entry: " + path)
    return matches[0]


def check_abi_directories(names: Iterable[str], expected: Sequence[str]) -> None:
    actual = {parts[1] for parts in (name.split("/") for name in names) if len(parts) >= 3 and parts[0] == "lib" and parts[1]}
    unexpected = sorted(actual - set(expected))
    if unexpected:
        raise AuditError("unexpected lib ABI directory(s): " + ", ".join(unexpected))


def check_archive_integrity(zf: zipfile.ZipFile, infos: Sequence[zipfile.ZipInfo]) -> None:
    # Reading to EOF checks both decompression and CRC.
    for info in infos:
        if info.is_dir():
            continue
        try:
            with zf.open(info, "r") as stream:
                while stream.read(1024 * 1024):
                    pass
        except (zipfile.BadZipFile, zlib.error, EOFError) as exc:
            raise AuditError(f"corrupt APK entry {info.filename}: {exc}") from exc


def check_elf(data: bytes, path: str, abi: str, min_alignment: Optional[int] = None) -> None:
    expected_class, expected_machine = ABI_LAYOUT[abi]
    if len(data) < 20 or data[:4] != b"\x7fELF":
        raise AuditError(path + ": invalid ELF header")
    if data[4] != expected_class:
        raise AuditError(f"{path}: ELF class {data[4]} does not match {abi}")
    if data[5] != 1:
        raise AuditError(path + ": Android libraries must be little-endian")
    machine = struct.unpack_from("<H", data, 18)[0]
    if machine != expected_machine:
        raise AuditError(f"{path}: e_machine {machine} does not match {abi}")
    if min_alignment is not None:
        check_load_alignment(data, path, min_alignment)


def check_load_alignment(data: bytes, path: str, min_alignment: int) -> None:
    """Every PT_LOAD segment must be aligned for 16 KB page devices."""
    is64 = data[4] == 2
    if is64:
        phoff = struct.unpack_from("<Q", data, 32)[0]
        phentsize, phnum = struct.unpack_from("<HH", data, 54)
    else:
        phoff = struct.unpack_from("<I", data, 28)[0]
        phentsize, phnum = struct.unpack_from("<HH", data, 42)
    loads = 0
    for index in range(phnum):
        offset = phoff + index * phentsize
        if offset + phentsize > len(data):
            raise AuditError(path + ": truncated program header table")
        if struct.unpack_from("<I", data, offset)[0] != PT_LOAD:
            continue
        loads += 1
        align = struct.unpack_from("<Q", data, offset + 48)[0] if is64 else struct.unpack_from("<I", data, offset + 28)[0]
        if align < min_alignment:
            raise AuditError(f"{path}: PT_LOAD alignment {align} is below {min_alignment}")
    if loads == 0:
        raise AuditError(path + ": no PT_LOAD segments")


def audit(path: Path, abis: Sequence[str]) -> str:
    if not path.is_file():
        raise AuditError("APK is not a regular file: " + str(path))
    digest = artifact_sha256(path)
    try:
        with zipfile.ZipFile(path, "r") as zf:
            infos = zf.infolist()
            check_archive_integrity(zf, infos)
            names = [info.filename for info in infos]
            if "assets/flutter_assets/kernel_blob.bin" in names:
                raise AuditError("debug APK contains assets/flutter_assets/kernel_blob.bin")
            check_abi_directories(names, abis)
            for abi in abis:
                for library in CORE_LIBRARIES + BACKEND_LIBRARIES:
                    entry_path = f"lib/{abi}/{library}"
                    data = zf.read(required_entry(infos, entry_path))
                    alignment = PAGE_ALIGNMENT if library == "libkalao_mobile.so" else None
                    check_elf(data, entry_path, abi, alignment)
    except zipfile.BadZipFile as exc:
        raise AuditError("invalid APK/ZIP: " + str(exc)) from exc
    return digest


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk", type=Path, help="release APK to audit")
    parser.add_argument("--abis", required=True, metavar="ABI[,ABI...]", help="expected APK ABIs")
    args = parser.parse_args(argv)
    try:
        abis = parse_abis(args.abis)
        digest = audit(args.apk, abis)
    except (AuditError, OSError) as exc:
        print("error: " + str(exc), file=sys.stderr)
        return 1
    print(f"OK sha256={digest} abis={','.join(abis)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
