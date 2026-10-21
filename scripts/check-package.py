#!/usr/bin/env python3
"""Check required runtime files before publishing/installing this plugin."""
from pathlib import Path
import re
import sys
import tomllib

root = Path(__file__).resolve().parents[1]
manifest = tomllib.loads((root / 'plugin.toml').read_text())
checked = set()


def visit(path):
    path = path.resolve()
    if not path.is_relative_to(root):
        raise ValueError(f'Module leaves package: {path}')
    if path in checked:
        return
    if not path.is_file():
        raise FileNotFoundError(f'Missing runtime file: {path.relative_to(root)}')
    checked.add(path)
    if path.suffix in ('.luau', '.lua'):
        for module in re.findall(r'require\([\'\"](\.[^\'\"]+)[\'\"]\)', path.read_text()):
            base = path.parent / module
            candidates = [base.with_suffix('.luau'), base.with_suffix('.lua'), base / 'init.luau']
            target = next((p for p in candidates if p.is_file()), candidates[0])
            visit(target)


try:
    for field in ('window', 'host'):
        if manifest.get(field):
            visit(root / manifest[field])
    for style in manifest.get('styles', []):
        visit(root / style)
except (ValueError, FileNotFoundError) as error:
    sys.exit(str(error))

print(f'Package complete: {len(checked)} runtime files, version {manifest["version"]}')
