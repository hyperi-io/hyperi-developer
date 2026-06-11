#!/usr/bin/env python3
# tests/audit/urls_and_pins.py — scan Ansible tasks for external references
# and version pins. Emits a well-quoted CSV to stdout.

import csv
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2] / "ansible" / "roles"

PATTERNS = [
    ("url",     re.compile(r'^\s*(url|baseurl|gpgkey|key|src):\s*(.+)$')),
    ("repo",    re.compile(r'^\s*repo:\s*(.+)$')),
    ("apt_key", re.compile(r'^\s*apt_key:\s*(.+)$')),
    ("rpm_key", re.compile(r'^\s*rpm_key:\s*(.+)$')),
    ("ppa",     re.compile(r'^\s*.*?ppa:[\w.-]+/[\w.-]+')),
    ("version", re.compile(r'^\s*(\w+_version|version):\s*["\']?[\d.]+')),
]

writer = csv.writer(sys.stdout)
writer.writerow(["file", "line", "type", "match"])

for yml in sorted(ROOT.rglob("*.yml")):
    for idx, line in enumerate(yml.read_text().splitlines(), start=1):
        for kind, pat in PATTERNS:
            if pat.search(line):
                writer.writerow([str(yml.relative_to(ROOT.parent.parent)), idx, kind, line.strip()])
                break
