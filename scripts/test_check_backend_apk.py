import struct
import tempfile
import unittest
import zipfile
from pathlib import Path

import check_backend_apk as audit


def elf64(machine: int, align: int) -> bytes:
    """A minimal little-endian ELF64 header with one PT_LOAD program header."""
    header = bytearray(64)
    header[:4] = b"\x7fELF"
    header[4] = 2
    header[5] = 1
    struct.pack_into("<H", header, 18, machine)
    struct.pack_into("<Q", header, 32, 64)
    struct.pack_into("<HH", header, 54, 56, 1)
    program = bytearray(56)
    struct.pack_into("<I", program, 0, audit.PT_LOAD)
    struct.pack_into("<Q", program, 48, align)
    return bytes(header + program)


class CheckBackendApkTest(unittest.TestCase):
    def build_apk(self, directory: Path, libraries: dict) -> Path:
        apk = directory / "app.apk"
        with zipfile.ZipFile(apk, "w") as zf:
            for name, data in libraries.items():
                zf.writestr(name, data)
        return apk

    def libraries(self, abi: str, machine: int, align: int = 16384) -> dict:
        names = audit.CORE_LIBRARIES + audit.BACKEND_LIBRARIES
        return {f"lib/{abi}/{name}": elf64(machine, align) for name in names}

    def test_accepts_complete_arm64_apk(self):
        with tempfile.TemporaryDirectory() as tmp:
            apk = self.build_apk(Path(tmp), self.libraries("arm64-v8a", 183))
            self.assertEqual(audit.main([str(apk), "--abis", "arm64-v8a"]), 0)

    def test_rejects_missing_backend(self):
        with tempfile.TemporaryDirectory() as tmp:
            libraries = self.libraries("x86_64", 62)
            del libraries["lib/x86_64/libkalao_mobile.so"]
            apk = self.build_apk(Path(tmp), libraries)
            with self.assertRaisesRegex(audit.AuditError, "missing APK entry"):
                audit.audit(apk, ("x86_64",))

    def test_rejects_4k_aligned_backend(self):
        with tempfile.TemporaryDirectory() as tmp:
            apk = self.build_apk(Path(tmp), self.libraries("arm64-v8a", 183, align=4096))
            with self.assertRaisesRegex(audit.AuditError, "alignment"):
                audit.audit(apk, ("arm64-v8a",))

    def test_rejects_unexpected_abi_and_wrong_machine(self):
        with tempfile.TemporaryDirectory() as tmp:
            libraries = self.libraries("arm64-v8a", 183)
            libraries["lib/x86_64/libapp.so"] = elf64(62, 16384)
            apk = self.build_apk(Path(tmp), libraries)
            with self.assertRaisesRegex(audit.AuditError, "unexpected lib ABI"):
                audit.audit(apk, ("arm64-v8a",))
        with tempfile.TemporaryDirectory() as tmp:
            apk = self.build_apk(Path(tmp), self.libraries("arm64-v8a", 62))
            with self.assertRaisesRegex(audit.AuditError, "e_machine"):
                audit.audit(apk, ("arm64-v8a",))

    def test_parse_abis(self):
        self.assertEqual(audit.parse_abis("arm64-v8a, x86_64"), ("arm64-v8a", "x86_64"))
        with self.assertRaises(audit.AuditError):
            audit.parse_abis("mips")
        with self.assertRaises(audit.AuditError):
            audit.parse_abis("x86_64,x86_64")


if __name__ == "__main__":
    unittest.main()
