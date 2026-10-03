"""Exercise the audit with real ZIP compression and binary ELF fixtures."""

from pathlib import Path
import struct
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from analyze_android_apk import (  # noqa: E402
    FONT, REQUIRED_LIBS, compare, elf_load_alignments, inspect_apk,
)


def elf(alignment=16384):
    data = bytearray(4096)
    data[:6] = b"\x7fELF\x02\x01"
    struct.pack_into("<H", data, 18, 183)
    struct.pack_into("<Q", data, 32, 64)
    struct.pack_into("<HH", data, 54, 56, 1)
    struct.pack_into("<I", data, 64, 1)
    struct.pack_into("<Q", data, 112, alignment)
    return data


def apk(path, compressed=True, omit=None, font=b"full variable font", abi="arm64-v8a"):
    method = zipfile.ZIP_DEFLATED if compressed else zipfile.ZIP_STORED
    with zipfile.ZipFile(path, "w", compression=method) as archive:
        for name in sorted(REQUIRED_LIBS - {omit}):
            archive.writestr(f"lib/{abi}/{name}", elf())
        archive.writestr(FONT, font)
        archive.writestr("assets/flutter_assets/shaders/example.frag", b"shader")


class ApkAuditTest(unittest.TestCase):
    def test_repack_preserves_contents_and_measures_real_reduction(self):
        with tempfile.TemporaryDirectory() as directory:
            baseline_path, current_path = Path(directory) / "old.apk", Path(directory) / "new.apk"
            apk(baseline_path, compressed=False)
            apk(current_path)
            baseline, old_hashes = inspect_apk(baseline_path)
            current, new_hashes = inspect_apk(current_path, require_compressed=True)
            comparison = compare(current, baseline, new_hashes, old_hashes)
            self.assertGreater(comparison["saved_percent"], 80)
            self.assertEqual(comparison["identical_protected_entries"], 8)
            self.assertTrue(all(n["compression_method"] == 8 for n in current["native"]))

    def test_changed_font_or_shader_fails_baseline_comparison(self):
        with tempfile.TemporaryDirectory() as directory:
            old, new = Path(directory) / "old.apk", Path(directory) / "new.apk"
            apk(old, compressed=False)
            apk(new, font=b"subset losing glyphs")
            baseline, old_hashes = inspect_apk(old)
            current, new_hashes = inspect_apk(new)
            with self.assertRaisesRegex(ValueError, "Protected content"):
                compare(current, baseline, new_hashes, old_hashes)
            new_hashes[FONT] = old_hashes[FONT]
            del new_hashes["assets/flutter_assets/shaders/example.frag"]
            with self.assertRaisesRegex(ValueError, "Protected content"):
                compare(current, baseline, new_hashes, old_hashes)

    def test_no_claim_of_savings_for_same_package(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "same.apk"
            apk(path)
            report, hashes = inspect_apk(path)
            with self.assertRaisesRegex(ValueError, "not smaller"):
                compare(report, report, hashes, hashes)

    def test_missing_decoder_or_wrong_abi_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "bad.apk"
            for options in ({"omit": "libmpv.so"}, {"abi": "x86_64"}):
                apk(path, **options)
                with self.assertRaisesRegex(ValueError, "only ARM64"):
                    inspect_apk(path)

    def test_stored_native_library_rejected_when_requested(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "stored.apk"
            apk(path, compressed=False)
            with self.assertRaisesRegex(ValueError, "Uncompressed native"):
                inspect_apk(path, require_compressed=True)

    def test_malformed_or_unaligned_elf_rejected(self):
        self.assertEqual(elf_load_alignments(elf()), [16384])
        for data in (b"invalid", elf(4096), elf()[:80], elf(20000)):
            with self.assertRaises(ValueError):
                elf_load_alignments(data)


if __name__ == "__main__":
    unittest.main()
