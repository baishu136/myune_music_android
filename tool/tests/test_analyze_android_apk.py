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
    data[:7] = b"\x7fELF\x02\x01\x01"
    struct.pack_into("<H", data, 16, 3)  # ET_DYN
    struct.pack_into("<H", data, 18, 183)
    struct.pack_into("<I", data, 20, 1)
    struct.pack_into("<Q", data, 32, 64)
    struct.pack_into("<H", data, 52, 64)
    struct.pack_into("<HH", data, 54, 56, 1)
    struct.pack_into("<I", data, 64, 1)
    struct.pack_into("<QQ", data, 96, len(data), len(data))
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
            self.assertEqual(comparison["identical_protected_entries"], 9)
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
            for options in ({"omit": "libmpv.so"}, {"omit": "libmyune.so"}, {"abi": "x86_64"}):
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

    def test_load_offset_and_address_must_be_congruent(self):
        data = elf()
        struct.pack_into("<Q", data, 80, 1)  # p_vaddr, with p_offset still zero
        with self.assertRaisesRegex(ValueError, "congruent"):
            elf_load_alignments(data)

    def test_load_segment_must_fit_file_and_memory(self):
        for offset, file_size, memory_size in ((0, 4097, 4097), (0, 4096, 4095), (16384, 1, 1)):
            with self.subTest(offset=offset, file_size=file_size, memory_size=memory_size):
                data = elf()
                struct.pack_into("<QQ", data, 72, offset, offset)
                struct.pack_into("<QQ", data, 96, file_size, memory_size)
                with self.assertRaises(ValueError):
                    elf_load_alignments(data)

    def test_elf_identity_and_header_must_describe_a_shared_library(self):
        for offset, format_, value in ((6, "B", 0), (16, "H", 1), (20, "I", 0), (52, "H", 32)):
            with self.subTest(offset=offset):
                data = elf()
                struct.pack_into("<" + format_, data, offset, value)
                with self.assertRaises(ValueError):
                    elf_load_alignments(data)

    def test_zero_filled_memory_tail_is_valid(self):
        data = elf()
        struct.pack_into("<Q", data, 104, 8192)
        self.assertEqual(elf_load_alignments(data), [16384])

    def test_nonzero_congruent_offsets_are_valid(self):
        data = elf()
        struct.pack_into("<QQ", data, 72, 512, 16384 + 512)
        struct.pack_into("<QQ", data, 96, 1024, 2048)
        self.assertEqual(elf_load_alignments(data), [16384])

    def test_no_load_segments_or_truncated_program_table_rejected(self):
        for offset, format_, value in ((64, "I", 4), (56, "H", 0), (32, "Q", 4096), (54, "H", 40)):
            with self.subTest(offset=offset):
                data = elf()
                struct.pack_into("<" + format_, data, offset, value)
                with self.assertRaises(ValueError):
                    elf_load_alignments(data)


if __name__ == "__main__":
    unittest.main()
