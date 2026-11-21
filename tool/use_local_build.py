#!/usr/bin/env python3
"""Points native/manifest.json at a library built by tool/native/build_*.

usage: tool/use_local_build.py <target>

For local development and CI only; never commit the rewritten manifest.
"""
import hashlib
import json
import shutil
import sys
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit(__doc__)

target = sys.argv[1]
root = Path(__file__).resolve().parent.parent
built = next(p for p in (root / "dist" / target).iterdir() if p.suffix != ".gz")
artifact = root / "native" / "artifacts" / target / built.name
artifact.parent.mkdir(parents=True, exist_ok=True)
shutil.copyfile(built, artifact)

manifest_path = root / "native" / "manifest.json"
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
manifest["artifacts"][target] = {
    "path": f"artifacts/{target}/{built.name}",
    "librarySha256": hashlib.sha256(artifact.read_bytes()).hexdigest(),
    "fileName": built.name,
}
manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
print(f"native/manifest.json now uses {artifact.relative_to(root)} for {target}")
