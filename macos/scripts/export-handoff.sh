#!/bin/bash
set -euo pipefail
script_root="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_root/../.." && pwd)"
cd "$repo_root"
base_revision="${1:-origin/main}"
git merge-base --is-ancestor "$base_revision" HEAD
git diff --quiet
git diff --cached --quiet
mkdir -p dist
git archive --format=zip --prefix=dragon-codex-boot/ --output=dist/dragon-codex-boot-macos-source.zip HEAD
git format-patch --stdout --binary "$base_revision..HEAD" > dist/feat-macos-port.patch
git bundle create dist/feat-macos-port.bundle feat/macos-port
python3 - "$base_revision" <<'PY'
import hashlib
import json
import subprocess
import sys
from pathlib import Path

def git(*args):
    return subprocess.check_output(['git', *args], text=True).strip()

files = ['dragon-codex-boot-macos-source.zip', 'feat-macos-port.patch', 'feat-macos-port.bundle']
manifest = {
    'branch': git('branch', '--show-current'),
    'commit': git('rev-parse', 'HEAD'),
    'baseCommit': git('rev-parse', sys.argv[1]),
    'remote': 'https://github.com/woodymeng/dragon-codex-boot',
    'files': {name: hashlib.sha256((Path('dist') / name).read_bytes()).hexdigest() for name in files}
}
Path('dist/DELIVERY.json').write_text(json.dumps(manifest, indent=2) + '\n')
Path('dist/SHA256SUMS').write_text(''.join(f'{digest}  {name}\n' for name, digest in manifest['files'].items()))
print(json.dumps(manifest, indent=2))
PY
git bundle verify dist/feat-macos-port.bundle
