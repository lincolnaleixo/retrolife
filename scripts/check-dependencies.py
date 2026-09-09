#!/usr/bin/env python3
"""Fail closed on unaudited SPDX identifiers in the locked Rust dependency graph."""
import json
import re
import subprocess
import sys

metadata = json.loads(subprocess.check_output(['cargo', 'metadata', '--locked', '--format-version', '1']))
allowed = {'MIT', 'Apache-2.0', 'BSD-2-Clause', 'BSD-3-Clause', 'ISC', 'Zlib',
           'Unicode-3.0', 'Unicode-DFS-2016', 'AGPL-3.0-only', 'CC0-1.0',
           'BSL-1.0', 'Unlicense', 'MPL-2.0'}
failures = []
for package in metadata['packages']:
    expression = package.get('license') or ''
    identifiers = set(re.findall(r'[A-Za-z0-9][A-Za-z0-9.+-]*', expression)) - {'AND', 'OR'}
    if not identifiers or not identifiers <= allowed:
        failures.append(package['name'])
if failures:
    print('Dependency license review required: ' + ', '.join(sorted(failures)), file=sys.stderr)
    sys.exit(1)
print(f"Reviewed SPDX identifiers for {len(metadata['packages'])} locked Rust packages")
