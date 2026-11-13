#!/usr/bin/env python3
import hashlib,json,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
manifest=json.loads((ROOT/'ning-source.json').read_text())
for name,want in manifest['sha256'].items():
 p=ROOT/name
 assert p.is_file(),f'Missing source: {name}'
 got=hashlib.sha256(p.read_bytes()).hexdigest()
 assert got==want,f'Source hash mismatch: {name}'
for name,want in manifest['submodules'].items():
 got=subprocess.check_output(['git','-C',str(ROOT/name),'rev-parse','HEAD'],text=True).strip()
 assert got==want,f'Submodule commit mismatch: {name}'
print(f"Verified {len(manifest['sha256'])} exact files, {len(manifest['submodules'])} pinned submodules")
