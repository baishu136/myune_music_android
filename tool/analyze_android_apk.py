"""Reproducible ARM64 APK size/content audit; Python standard library only.

Does not replace apksigner, zipalign or real-device install/playback checks.
Comparison checks uncompressed bytes, so repackaging cannot hide lost assets.
"""

import argparse
import hashlib
import json
from pathlib import Path
import struct
import zipfile


REQUIRED_LIBS = frozenset({
    "libapp.so", "libflutter.so", "libmpv.so", "libc++_shared.so",
    "libdartjni.so", "libdatastore_shared_counter.so", "libmpv_audio_kit_jni.so",
})
FONT = "assets/flutter_assets/assets/fonts/MiSansVF.ttf"


def digest(stream):
    result = hashlib.sha256()
    while chunk := stream.read(1024 * 1024):
        result.update(chunk)
    return result.hexdigest()


def elf_load_alignments(data):
    """Read ELF64 LE program headers (ARM64), without extracting files."""
    if len(data) < 64 or data[:6] != b"\x7fELF\x02\x01":
        raise ValueError("Expected ELF64 little-endian library")
    if struct.unpack_from("<H", data, 18)[0] != 183:
        raise ValueError("Expected AArch64 library")
    offset = struct.unpack_from("<Q", data, 32)[0]
    stride, count = struct.unpack_from("<HH", data, 54)
    if stride < 56 or offset + stride * count > len(data):
        raise ValueError("Truncated ELF program headers")
    alignments = []
    for index in range(count):
        start = offset + index * stride
        if struct.unpack_from("<I", data, start)[0] == 1:  # PT_LOAD
            alignment = struct.unpack_from("<Q", data, start + 48)[0]
            if alignment < 16384 or alignment & (alignment - 1):
                raise ValueError("ELF LOAD alignment is not >= 16 KiB")
            alignments.append(alignment)
    if not alignments:
        raise ValueError("ELF has no LOAD segments")
    return alignments


def inspect_apk(path, require_compressed=False):
    path = Path(path).resolve()
    categories = {}
    hashes = {}
    native = []
    with zipfile.ZipFile(path) as apk:
        entries = apk.infolist()
        names = [entry.filename for entry in entries]
        if len(names) != len(set(names)):
            raise ValueError("Duplicate APK entries")
        libraries = [entry for entry in entries if entry.filename.startswith("lib/")]
        if {entry.filename for entry in libraries} != {
            f"lib/arm64-v8a/{name}" for name in REQUIRED_LIBS
        }:
            raise ValueError("APK must contain all required libraries and only ARM64")
        if FONT not in names:
            raise ValueError("Missing full MiSans font")
        for entry in entries:
            group = ("native" if entry.filename.startswith("lib/") else
                     "flutter_assets" if entry.filename.startswith("assets/flutter_assets/") else
                     "dex" if entry.filename.endswith(".dex") else "other")
            category = categories.setdefault(group, {"raw_bytes": 0, "zip_bytes": 0})
            category["raw_bytes"] += entry.file_size
            category["zip_bytes"] += entry.compress_size
            if entry.is_dir():
                continue
            # Verify CRCs/content even for entries not compared with a baseline.
            with apk.open(entry) as stream:
                hashes[entry.filename] = digest(stream)
            if entry in libraries:
                if require_compressed and entry.compress_type != zipfile.ZIP_DEFLATED:
                    raise ValueError(f"Uncompressed native library: {entry.filename}")
                native.append({
                    "name": entry.filename, "raw_bytes": entry.file_size,
                    "zip_bytes": entry.compress_size,
                    "compression_method": entry.compress_type,
                    "load_alignments": elf_load_alignments(apk.read(entry)),
                    "sha256": hashes[entry.filename],
                })
        largest = sorted(entries, key=lambda entry: entry.compress_size, reverse=True)[:12]
        report = {
            "path": str(path), "apk_bytes": path.stat().st_size,
            "categories": categories, "native": native,
            "largest_entries": [{"name": e.filename, "raw_bytes": e.file_size,
                                 "zip_bytes": e.compress_size} for e in largest],
        }
    with path.open("rb") as stream:
        report["sha256"] = digest(stream)
    return report, hashes


def compare(current, baseline, current_hashes, baseline_hashes):
    # libapp.so contains versioned application code; it is expected to change.
    # Preserve the entire remaining native stack and every Flutter asset,
    # including shaders, translations, icons and notices, byte-for-byte.
    protected = {
        name for name in baseline_hashes
        if (name.startswith("lib/") and not name.endswith("/libapp.so"))
        or name.startswith("assets/flutter_assets/")
    }
    changed = sorted(name for name in protected
                     if current_hashes.get(name) != baseline_hashes[name])
    if changed:
        raise ValueError(f"Protected content missing/changed: {changed}")
    saved = baseline["apk_bytes"] - current["apk_bytes"]
    if saved <= 0:
        raise ValueError("Optimized APK is not smaller than baseline")
    return {"baseline_path": baseline["path"], "baseline_bytes": baseline["apk_bytes"],
            "saved_bytes": saved,
            "saved_percent": round(saved * 100 / baseline["apk_bytes"], 4),
            "identical_protected_entries": len(protected)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk", type=Path)
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--require-compressed-native", action="store_true")
    args = parser.parse_args()
    try:
        report, hashes = inspect_apk(args.apk, args.require_compressed_native)
        if args.baseline:
            baseline, baseline_hashes = inspect_apk(args.baseline)
            report["comparison"] = compare(report, baseline, hashes, baseline_hashes)
        print(json.dumps(report, indent=2, ensure_ascii=False))
    except (ValueError, zipfile.BadZipFile, OSError) as error:
        parser.exit(1, f"APK audit failed: {error}\n")


if __name__ == "__main__":
    main()
