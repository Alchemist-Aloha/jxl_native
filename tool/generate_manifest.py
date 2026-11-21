#!/usr/bin/env python3
import gzip
import hashlib
import json
import shutil
import sys
from pathlib import Path

if len(sys.argv) != 4:
    raise SystemExit("usage: generate_manifest.py <version> <owner/repository> <dist-directory>")

version, repository, dist_arg = sys.argv[1:]
dist = Path(dist_arg).resolve()
release = dist.parent / "release"
release.mkdir(parents=True, exist_ok=True)
artifacts = {}

for archive in sorted(dist.rglob("*.gz")):
    # Release artifacts download as native-<target>/<library>.gz.
    target = archive.parent.name.removeprefix("native-")
    compressed_name = archive.name
    library_name = compressed_name[:-3]
    release_name = f"{target}-{compressed_name}"
    archive_bytes = archive.read_bytes()
    library_bytes = gzip.decompress(archive_bytes)
    shutil.copyfile(archive, release / release_name)
    artifacts[target] = {
        "url": f"https://github.com/{repository}/releases/download/native-v{version}/{release_name}",
        "archiveSha256": hashlib.sha256(archive_bytes).hexdigest(),
        "librarySha256": hashlib.sha256(library_bytes).hexdigest(),
        "fileName": library_name,
    }

if not artifacts:
    raise RuntimeError("No compressed native libraries found")

(release / "manifest.json").write_text(
    json.dumps({"nativeVersion": version, "artifacts": artifacts}, indent=2) + "\n",
    encoding="utf-8",
)
