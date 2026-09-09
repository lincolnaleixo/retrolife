#!/usr/bin/env python3
"""Inspect the exact index that will be committed; report paths, never matched values."""
from pathlib import Path
import re
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
names = subprocess.check_output(['git', 'ls-files', '-z'], cwd=root).decode().split('\0')
failures = []
if not any(names):
    print('Refusing to audit an empty index', file=sys.stderr)
    sys.exit(1)
stages = subprocess.check_output(['git', 'ls-files', '--stage', '-z'], cwd=root).decode().split('\0')
modes = {}
for stage in filter(None, stages):
    modes[stage.split("\t", 1)[1]] = stage.split(" ", 1)[0]
    if stage.startswith('160000 '):
        failures.append((stage.split('\t', 1)[1], 'submodule is not allowed'))
for name in filter(None, names):
    path = root / name
    if path.name.startswith('.env') or path.suffix.lower() in {'.key', '.pem'}:
        failures.append((name, 'credential-shaped file'))
    data = subprocess.check_output(['git', 'show', ':' + name], cwd=root)
    if modes.get(name) == '120000':
        # Validate the indexed link, never a different unstaged working copy.
        target = data.decode('utf-8', errors='strict')
        if name not in {'AGENTS.md', 'CLAUDE.md', 'GEMINI.md'} or target != 'rules.md':
            failures.append((name, 'unapproved symlink target'))
        continue
    if path.suffix.lower() in {'.sfc', '.smc', '.srm', '.sav', '.p12', '.pfx', '.blend', '.glb', '.pdf'}:
        failures.append((name, 'binary/content requires explicit independent review'))
    if b'\x00' in data:
        failures.append((name, 'unexpected binary'))
        continue
    text = data.decode('utf-8', errors='replace')
    patterns = [
        r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
        r'gh[pousr]_[A-Za-z0-9]{30,}',
        r'github_pat_[A-Za-z0-9_]{40,}',
        r'(?:/home/|/Users/)[A-Za-z0-9_.-]+/',
        r'[A-Za-z0-9.-]+\.ts\.net',
        r'git@github\.com:',
    ]
    if name != 'scripts/audit-publication.py' and any(re.search(p, text) for p in patterns):
        failures.append((name, 'private path or secret-shaped content'))
    if name == '.gitmodules':
        failures.append((name, 'submodules require explicit review'))
for name, reason in failures:
    print(f'{name}: {reason}', file=sys.stderr)
print(f'Publication index audit: {len(list(filter(None,names)))} files, {len(failures)} findings')
sys.exit(bool(failures))
