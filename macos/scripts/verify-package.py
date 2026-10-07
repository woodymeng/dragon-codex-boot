#!/usr/bin/env python3
"""Check archive paths, required bundle files, license, and exact approved media bytes."""
import hashlib
import json
import plistlib
import sys
import zipfile
from pathlib import Path, PurePosixPath

repo = Path(__file__).resolve().parents[2]
archive = Path(sys.argv[1])
prefix = "Dragon Codex Boot.app/Contents/"
with zipfile.ZipFile(archive) as bundle:
    assert len(bundle.namelist()) == len(set(bundle.namelist())), "duplicate ZIP entries"
    for name in bundle.namelist():
        path = PurePosixPath(name)
        assert "\\" not in name and not path.is_absolute() and ".." not in path.parts, name
        assert not any(part in ("logs", ".integration", ".git", "qa") for part in path.parts), name
    plist = plistlib.loads(bundle.read(prefix + "Info.plist"))
    assert plist["CFBundleIdentifier"] == "community.DragonCodexBoot"
    assert plist["LSMinimumSystemVersion"] == "13.0"
    binary = bundle.read(prefix + "MacOS/DragonCodexBoot")
    assert binary[:4] == b"\xcf\xfa\xed\xfe", "expected 64-bit Mach-O"
    assert int.from_bytes(binary[4:8], "little") == 0x0100000C, "expected native arm64 CPU"
    for relative in ("LICENSE", "THIRD_PARTY_NOTICES.md"):
        assert bundle.read(prefix + "Resources/" + relative) == (repo / relative).read_bytes()
    for relative in ("startup.mp4", "MEDIA_NOTICE.md"):
        assert hashlib.sha256(bundle.read(prefix + "Resources/media/" + relative)).digest() == hashlib.sha256((repo / "media" / relative).read_bytes()).digest()
    configuration = bundle.read(prefix + "Resources/launcher.example.json")
    assert configuration == (repo / "macos/Resources/launcher.example.json").read_bytes()
    assert json.loads(configuration)["video"] == "media/startup.mp4"
    assert bundle.read(prefix + "Resources/README.md") == (repo / "macos/README.md").read_bytes()
expected = archive.with_suffix(archive.suffix + ".sha256").read_text().split()[0]
assert hashlib.sha256(archive.read_bytes()).hexdigest() == expected
print("PASS: native arm64 bundle, config, media, licenses, safe ZIP paths, SHA-256")
