#!/usr/bin/env python3
"""Check that hyperi_versions still mirrors hyperi-ci's tool pins.

`hyperi_versions` in the localhost group_vars exists so that a `--pinned` box
installs the same tool versions CI runs. Nothing enforced that: both files are
hand-edited, in two repos, and a bump on either side left the other behind
without saying so. Three of twelve had drifted before this existed.

Renovate cannot cover it either -- they are plain YAML strings in an Ansible
group_vars file, not a manifest format it has a manager for.

Reads hyperi-ci's pins through hyperi-ci's OWN interpreter rather than
importing them here: it is installed as an isolated uv tool, so `import
hyperi_ci` from any other Python fails. No network is involved.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent
PINS_FILE = REPO_ROOT / "ansible/inventories/localhost/group_vars/all.yml"

# Dumped through hyperi-ci's public accessors rather than reading its config
# file directly, so a change to that file's shape does not silently break this.
DUMP_PINS = (
    "import json; from hyperi_ci import versions; "
    "print(json.dumps({n: versions.tool_version(n) for n in versions.tool_names()}))"
)


def hyperi_ci_python() -> Path | None:
    """The interpreter of the installed hyperi-ci, or None if it is not there.

    A uv tool's entry point sits beside the venv's python, so resolving the
    binary through any symlinks gives the interpreter that can import it.
    """
    binary = shutil.which("hyperi-ci")
    if not binary:
        return None
    candidate = Path(os.path.realpath(binary)).parent / "python"
    return candidate if candidate.is_file() else None


def ci_pins(python: Path) -> dict[str, str]:
    proc = subprocess.run(
        [str(python), "-c", DUMP_PINS],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=120,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"hyperi-ci pins unreadable: {proc.stderr.strip()}")
    return json.loads(proc.stdout)


def local_pins(path: Path) -> dict[str, str]:
    data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    return data.get("hyperi_versions") or {}


def compare(local: dict[str, str], ci: dict[str, str]) -> tuple[list[str], list[str]]:
    """Return (problems, notes).

    A tool CI pins and we do not is fine -- an absent entry falls back to latest
    even under --pinned, which is the documented behaviour. The reverse is not:
    an entry with no counterpart pins a version CI never runs, which is the
    opposite of what this map is for.
    """
    problems = []
    for name in sorted(set(local) & set(ci)):
        if local[name] != ci[name]:
            problems.append(f"{name}: pinned {local[name]} here, {ci[name]} in hyperi-ci")

    problems += [
        f"{name}: pinned {local[name]} here, but hyperi-ci does not pin it at all"
        for name in sorted(set(local) - set(ci))
    ]
    notes = [
        f"{name}: hyperi-ci pins {ci[name]}, not mirrored here (falls back to latest)"
        for name in sorted(set(ci) - set(local))
    ]
    return problems, notes


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--pins-file",
        type=Path,
        default=PINS_FILE,
        help="group_vars file holding hyperi_versions (default: the repo's own)",
    )
    args = parser.parse_args(argv)

    python = hyperi_ci_python()
    if python is None:
        # Same bargain the Ansible checks make: absent tooling skips rather
        # than reddening a runner that was never going to have it.
        print("--> hyperi-ci not installed, skipping the pin comparison")
        return 0

    try:
        ci = ci_pins(python)
    except (RuntimeError, json.JSONDecodeError) as exc:
        print(f"    FAILED: {exc}")
        return 1

    local = local_pins(args.pins_file)
    problems, notes = compare(local, ci)

    for note in notes:
        print(f"    note: {note}")
    for problem in problems:
        print(f"    DRIFT: {problem}")

    if problems:
        print(f"    {len(problems)} pin(s) disagree with hyperi-ci.")
        print("    hyperi_versions must mirror hyperi-ci, or --pinned stops matching CI.")
        return 1

    print(f"    ok ({len(set(local) & set(ci))} pin(s) match hyperi-ci)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
