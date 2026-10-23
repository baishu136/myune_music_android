"""Run the release wrapper in a disposable project with a fake Flutter SDK."""

from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest


PWSH = shutil.which("pwsh")
SCRIPT = Path(__file__).resolve().parents[1] / "build_android_release.ps1"
APK_NAME = "Myune-Music-1.2.3-android.418-arm64-v8a.apk"
FAKE_FLUTTER = r"""
Add-Content -LiteralPath 'calls.txt' -Value ($args -join ' ')
if ($env:MYUNE_TEST_FAIL -eq $args[0]) {
    $global:LASTEXITCODE = 17
    return
}
if ($args[0] -eq 'build') {
    New-Item -ItemType Directory -Force -Path 'build/app/outputs/flutter-apk' | Out-Null
    [IO.File]::WriteAllBytes((Join-Path $PWD 'build/app/outputs/flutter-apk/app-arm64-v8a-release.apk'), [byte[]](1, 2, 3, 4))
    if ($env:MYUNE_TEST_CHANGE_VERSION -eq '1') {
        Set-Content -LiteralPath 'pubspec.yaml' -Value 'version: 1.2.3+419'
    }
    if ($env:MYUNE_TEST_CREATE_ARCHIVE -eq '1') {
        New-Item -ItemType Directory -Force -Path 'dist' | Out-Null
        Set-Content -LiteralPath 'dist/Myune-Music-1.2.3-android.418-arm64-v8a.apk' -Value 'concurrent archive'
    }
}
$global:LASTEXITCODE = 0
"""


@unittest.skipUnless(PWSH, "PowerShell 7 is required for the release wrapper")
class ReleaseBuildTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="myune release test ")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "tool").mkdir()
        shutil.copyfile(SCRIPT, self.root / "tool/build_android_release.ps1")
        (self.root / "pubspec.yaml").write_text("version: 1.2.3+418\n", encoding="utf-8")
        self.flutter = self.root / "fake flutter.ps1"
        self.flutter.write_text(FAKE_FLUTTER, encoding="utf-8")
        self.output = self.root / "dist" / APK_NAME

    def run_build(self, *args, **environment):
        env = {key: value for key, value in os.environ.items()
               if not key.startswith("MYUNE_TEST_")}
        env.update(environment)
        return subprocess.run(
            [PWSH, "-NoProfile", "-NonInteractive", "-File",
             str(self.root / "tool/build_android_release.ps1"),
             "-FlutterPath", str(self.flutter), *args],
            cwd=self.root, env=env, text=True, encoding="utf-8", capture_output=True,
            timeout=30,
        )

    def calls(self):
        path = self.root / "calls.txt"
        return path.read_text(encoding="utf-8-sig").splitlines() if path.exists() else []

    def test_success_uses_current_version_and_only_arm64(self):
        result = self.run_build()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.output.read_bytes(), bytes((1, 2, 3, 4)))
        self.assertEqual(self.calls(), [
            "pub get", "build apk --release --target-platform android-arm64 --split-per-abi",
        ])
        self.assertIn("SHA256:", result.stdout)

    def test_existing_archive_is_preserved_before_flutter_runs(self):
        self.output.parent.mkdir()
        self.output.write_bytes(b"immutable historical APK")
        result = self.run_build()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.output.read_bytes(), b"immutable historical APK")
        self.assertEqual(self.calls(), [])

    def test_existing_archive_directory_is_rejected_before_flutter_runs(self):
        self.output.mkdir(parents=True)
        result = self.run_build()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_invalid_or_ambiguous_version_stops_before_flutter_runs(self):
        for version in (
            "version: invalid\n",
            "version: 1.2.3+418\nversion: 1.2.3+419\n",
            "version: 1.2.3+418\nversion: invalid\n",
            "version:\n1.2.3+418\n",
        ):
            with self.subTest(version=version):
                (self.root / "pubspec.yaml").write_text(version, encoding="utf-8")
                result = self.run_build()
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.calls(), [])
                self.assertFalse(self.output.exists())

    def test_pub_failure_does_not_build_or_stage(self):
        result = self.run_build(MYUNE_TEST_FAIL="pub")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.calls(), ["pub get"])
        self.assertFalse(self.output.exists())

    def test_build_failure_does_not_stage_stale_apk(self):
        source = self.root / "build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
        source.parent.mkdir(parents=True)
        source.write_bytes(b"stale APK")
        result = self.run_build(MYUNE_TEST_FAIL="build")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.output.exists())

    def test_changed_version_during_build_is_not_mislabeled(self):
        result = self.run_build(MYUNE_TEST_CHANGE_VERSION="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(self.calls()), 2)
        self.assertFalse((self.root / "dist").exists())

    def test_custom_output_directory_with_spaces(self):
        destination = self.root / "custom output"
        result = self.run_build("-OutputDirectory", str(destination))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((destination / APK_NAME).read_bytes(), bytes((1, 2, 3, 4)))

    def test_archive_created_during_build_is_preserved(self):
        result = self.run_build(MYUNE_TEST_CREATE_ARCHIVE="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.output.read_text(encoding="utf-8-sig").strip(), "concurrent archive")

    def test_skip_pub_get_builds_without_refetching_dependencies(self):
        result = self.run_build("-SkipPubGet")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls(), [
            "build apk --release --target-platform android-arm64 --split-per-abi",
        ])


if __name__ == "__main__":
    unittest.main()
