"""Package UTF-8 JS and an SDK manifest without executing either input."""
import argparse
import json
from pathlib import Path


def pack(manifest: Path, script: Path, output: Path) -> None:
    if manifest.stat().st_size > 8192 or script.stat().st_size > 128 * 1024:
        raise ValueError('Plugin input exceeds size limit')
    data = json.loads(manifest.read_text(encoding='utf-8-sig'))
    if not isinstance(data, dict) or data.get('sdk') != 1:
        raise ValueError('SDK 1 manifest required')
    code = script.read_text(encoding='utf-8-sig')
    if not code.strip() or '\0' in code:
        raise ValueError('Empty or invalid JavaScript')
    payload = json.dumps({'manifest': data, 'script': code}, ensure_ascii=False, indent=2) + '\n'
    if len(payload.encode('utf-8')) > 192 * 1024:
        raise ValueError('Plugin package exceeds size limit')
    # Published examples/packages are immutable; explicitly choose a new path.
    with output.open('x', encoding='utf-8', newline='\n') as stream:
        stream.write(payload)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest', type=Path)
    parser.add_argument('script', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    pack(args.manifest, args.script, args.output)
