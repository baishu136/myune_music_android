import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('pack_myune_plugin', Path(__file__).parents[1] / 'pack_myune_plugin.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PluginPackingTests(unittest.TestCase):
    def test_unicode_round_trip_and_exclusive_output(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            manifest, script, output = [root / n for n in ['manifest.json', 'main.js', 'test.myune-plugin']]
            manifest.write_text(json.dumps({'sdk': 1, 'name': '歌词🎵'}), encoding='utf-8')
            script.write_text('globalThis.myunePlugin=()=>"你好🎵";', encoding='utf-8')
            module.pack(manifest, script, output)
            self.assertEqual(json.loads(output.read_text(encoding='utf-8'))['script'], script.read_text(encoding='utf-8'))
            with self.assertRaises(FileExistsError):
                module.pack(manifest, script, output)

    def test_invalid_sdk_and_oversize_never_create_output(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            manifest, script, output = [root / n for n in ['manifest.json', 'main.js', 'bad.myune-plugin']]
            script.write_text('x', encoding='utf-8')
            manifest.write_text('{"sdk":2}', encoding='utf-8')
            with self.assertRaises(ValueError):
                module.pack(manifest, script, output)
            manifest.write_text('{"sdk":1}', encoding='utf-8')
            script.write_text('x' * (128 * 1024 + 1), encoding='utf-8')
            with self.assertRaises(ValueError):
                module.pack(manifest, script, output)
            self.assertFalse(output.exists())
