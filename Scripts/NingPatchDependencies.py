#!/usr/bin/env python3
"""Apply the smallest source-level Alderis compatibility fix after SwiftPM resolution."""
import argparse, hashlib, re
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--packages', required=True)
args = parser.parse_args()
path = Path(args.packages) / 'checkouts/Alderis/Alderis/ColorPickerInnerViewController.swift'
if not path.is_file():
    raise SystemExit(f'Alderis checkout missing: {path}')
old = path.read_bytes()
text = old.decode('utf-8')
property_pattern = re.compile(r'(?m)^(\s*)var tab: ColorPickerTab \{')
assignment_pattern = re.compile(r'(?m)^(\s*)tab = configuration\.initialTab$')
if len(property_pattern.findall(text)) != 1:
    raise SystemExit('Expected exactly one Alderis tab property')
if len(assignment_pattern.findall(text)) != 1:
    raise SystemExit('Expected exactly one Alderis initial-tab assignment')
text = property_pattern.sub(r'\1var selectedColorPickerTab: ColorPickerTab {', text, count=1)
text = assignment_pattern.sub(r'\1selectedColorPickerTab = configuration.initialTab', text, count=1)
if 'var tab: ColorPickerTab' in text or 'tab = configuration.initialTab' in text:
    raise SystemExit('Alderis compatibility replacement was incomplete')
path.write_text(text, encoding='utf-8')
print(json_line := {
    'file': str(path),
    'before_sha256': hashlib.sha256(old).hexdigest(),
    'after_sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
    'renamed_property': 'tab -> selectedColorPickerTab'
})
