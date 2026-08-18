#!/usr/bin/env python3
"""hyperi-doctor -- read-only report on SOE drift.

Never applies anything and never needs sudo: it only reads the applied-state
stamp (ansible/playbooks/main.yml writes it) and queries the local package
manager. See tools/README.md.

Ported from the original bash implementation to remove the yq/jq dependency
chain -- PyYAML is the one non-stdlib import here, and it is already a hard
Ansible dependency on any box this tool runs on, so it adds nothing new to
the machine's footprint.

Licensed under the Apache License, Version 2.0
"""

from __future__ import annotations

import argparse
import json
import os
import platform
import shutil
import subprocess
import sys
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

try:
    import yaml
except ImportError:
    # A traceback here would point at PyYAML's absence, not this tool's
    # logic -- a one-line message is the actionable form of that failure.
    print(
        "hyperi-doctor: PyYAML is required (pip install pyyaml / uv add pyyaml) "
        "and was not found",
        file=sys.stderr,
    )
    sys.exit(1)

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
ROLES_DIR = REPO_ROOT / "ansible" / "roles"

MODULE_KEYS = {
    "ubuntu": "ansible.builtin.apt",
    "fedora": "ansible.builtin.dnf",
    "macos": "community.general.homebrew",
}
PLATFORM_LABELS = {
    "ubuntu": "Ubuntu (dpkg-query)",
    "fedora": "Fedora (rpm)",
    "macos": "macOS (brew)",
}

USAGE = """\
Usage: hyperi-doctor [--tags TAG[,TAG...]] [--quiet] [--help]

Read-only report on whether this host has drifted behind what this repo's
roles declare. Never applies anything, never needs sudo, and is safe to run
on any machine.

Reports:
  a. Applied-state stamp age and SHA vs this checkout's HEAD.
  b. Which packages the selected roles declare that are absent locally.
  c. Exits non-zero when a declared package is missing.

Options:
  --tags TAG[,TAG...]  Role tags to check, as passed to
                       'ansible-playbook --tags'. Defaults to the tags in
                       the applied-state stamp, or to 'developer' (the
                       bare-install default) when there is no stamp.
  --quiet              Print only problems (missing packages) and set the
                       exit code; suppress the stamp report and notes.
  --help               Show this message.
"""


class Reporter:
    """Two print channels matching the bash note()/problem() split.

    note() is suppressed under --quiet; problem() never is -- a quiet run
    that checked nothing and said nothing would be indistinguishable from a
    clean host, which is the exact failure this tool exists to catch.
    """

    def __init__(self, quiet: bool) -> None:
        self.quiet = quiet

    def note(self, message: str) -> None:
        if not self.quiet:
            print(message)

    def problem(self, message: str) -> None:
        print(message)


def die(message: str, code: int = 1) -> None:
    """Print an error and exit, mirroring the bash script's die()."""
    print(f"hyperi-doctor: {message}", file=sys.stderr)
    sys.exit(code)


def parse_args(argv: list[str]) -> argparse.Namespace:
    """Parse CLI args, keeping the exact error text scripts may match on.

    Deliberately not a bare argparse() call: argparse's own error wording
    differs, and "unknown argument: X (see --help)" is part of this tool's
    stable output contract.
    """
    tags = ""
    quiet = False
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg == "--tags":
            if i + 1 >= len(argv) or not argv[i + 1]:
                die("--tags requires an argument")
            tags = argv[i + 1]
            i += 2
        elif arg == "--quiet":
            quiet = True
            i += 1
        elif arg in ("-h", "--help"):
            print(USAGE, end="")
            sys.exit(0)
        else:
            die(f"unknown argument: {arg} (see --help)")
    return argparse.Namespace(tags=tags, quiet=quiet)


def detect_platform() -> str:
    """One module, one query tool per platform.

    The task files already carry platform-specific package names
    (protobuf-compiler vs protobuf), so there is no cross-platform name
    mapping to get wrong here -- just which manager to ask.
    """
    system = platform.system()
    if system == "Darwin":
        return "macos"
    if system == "Linux":
        if shutil.which("dpkg-query"):
            return "ubuntu"
        if shutil.which("rpm"):
            return "fedora"
        return "unknown"
    return "unknown"


def pkg_installed(platform_name: str, name: str) -> bool:
    """Query the platform's package manager for presence of `name`."""
    try:
        if platform_name == "ubuntu":
            result = subprocess.run(
                ["dpkg-query", "-W", "-f=${Status}", name],
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                check=False,
            )
            return result.stdout.strip() == "install ok installed"
        if platform_name == "fedora":
            result = subprocess.run(
                ["rpm", "-q", name],
                capture_output=True,
                encoding="utf-8",
                errors="replace",
                check=False,
            )
            return result.returncode == 0
        if platform_name == "macos":
            result = subprocess.run(
                ["brew", "list", "--versions", name],
                capture_output=True,
                encoding="utf-8",
                errors="replace",
                check=False,
            )
            return result.returncode == 0
    except FileNotFoundError:
        return False
    return False


# ============================================================================
# Section (a) -- applied-state stamp
# ============================================================================


def parse_stamp_timestamp(timestamp: str) -> datetime | None:
    """Parse the stamp's UTC ISO-8601 timestamp.

    Matches the one format ansible_date_time.iso8601 emits -- no GNU-date-vs-
    BSD-date branch needed since nothing here shells out to `date`.
    """
    try:
        return datetime.strptime(timestamp, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=UTC)
    except ValueError:
        return None


def report_stamp(stamp_path: Path, reporter: Reporter) -> list[str]:
    """Print the applied-state stamp section, return its recorded tags.

    A missing stamp is expected on every host provisioned before this
    existed -- reported plainly, never as a failure.
    """
    if not stamp_path.is_file():
        reporter.note("== Applied-state stamp ==")
        reporter.note(f"No stamp found at {stamp_path}.")
        reporter.note(
            "This host has either never been provisioned by this repo, or was"
        )
        reporter.note("provisioned before the stamp existed. Not treated as an error.")
        reporter.note("")
        return []

    try:
        data: dict[str, Any] = json.loads(stamp_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        die(f"could not read stamp at {stamp_path}: {exc}")

    sha = data.get("sha") or "unknown"
    timestamp = data.get("timestamp") or "unknown"
    tags_list = data.get("tags") or []
    tags = ",".join(tags_list) if isinstance(tags_list, list) else "unknown"
    target_user = data.get("target_user") or "unknown"
    warns = data.get("warnings")
    warns = "unknown" if warns is None else warns

    reporter.note("== Applied-state stamp ==")
    reporter.note(f"Stamp path:    {stamp_path}")
    reporter.note(f"Applied SHA:   {sha}")
    reporter.note(f"Applied at:    {timestamp}")
    reporter.note(f"Tags applied:  {tags or '(none recorded)'}")
    reporter.note(f"Target user:   {target_user}")

    # Optional components warn and continue, so a run can finish with tools
    # missing. A stamp is not a clean bill of health on its own.
    if warns != "unknown" and warns != 0:
        reporter.note(
            f"Warnings:      {warns} component(s) warned on that run -- it did"
        )
        reporter.note("               NOT install everything it was asked to.")
    else:
        reporter.note(f"Warnings:      {warns}")

    stamp_dt = parse_stamp_timestamp(timestamp) if timestamp != "unknown" else None
    if stamp_dt is not None:
        age_days = (datetime.now(UTC) - stamp_dt).days
        reporter.note(f"Stamp age:     {age_days} day(s)")
    else:
        reporter.note(f"Stamp age:     could not parse timestamp '{timestamp}'")

    _report_head_comparison(sha, reporter)
    reporter.note("")
    return tags_list if isinstance(tags_list, list) else []


def _report_head_comparison(applied_sha: str, reporter: Reporter) -> None:
    """Compare the stamp's SHA against this checkout's HEAD, via git."""
    if not (REPO_ROOT / ".git").is_dir() or shutil.which("git") is None:
        reporter.note("Checkout HEAD: unavailable (not a git checkout)")
        return

    head = subprocess.run(
        ["git", "-C", str(REPO_ROOT), "rev-parse", "HEAD"],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    head_sha = head.stdout.strip()
    if not head_sha:
        return

    reporter.note(f"Checkout HEAD: {head_sha}")
    if applied_sha == head_sha:
        reporter.note("This host matches the current checkout.")
        return

    behind = subprocess.run(
        ["git", "-C", str(REPO_ROOT), "rev-list", "--count", f"{applied_sha}..{head_sha}"],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    behind_count = behind.stdout.strip()
    if behind.returncode == 0 and behind_count:
        reporter.note(f"This host is {behind_count} commit(s) behind this checkout.")
    else:
        reporter.note(
            "Applied SHA differs from this checkout's HEAD (commit count unknown --"
        )
        reporter.note(
            "the applied SHA may not be reachable from this checkout's history)."
        )


# ============================================================================
# Section (b) -- role scope and package resolution
# ============================================================================


def resolve_roles(seed_csv: str, roles_dir: Path, reporter: Reporter) -> list[str]:
    """Recursively expand seed tags through each role's meta/main.yml deps.

    Walks the same dependency graph `ansible-playbook --tags` does. Returns
    resolved role names in discovery order, deduplicated.
    """
    queue: list[str] = [t.strip() for t in seed_csv.split(",") if t.strip()]
    resolved: list[str] = []
    seen: set[str] = set()

    while queue:
        role = queue.pop(0)
        if not role or role in seen:
            continue

        role_dir = roles_dir / role
        if not role_dir.is_dir():
            # stderr: this function's return value IS the resolved role
            # list, so a stray print to stdout here would corrupt it.
            if not reporter.quiet:
                print(
                    f"note: tag '{role}' has no matching role directory "
                    "under ansible/roles -- skipped",
                    file=sys.stderr,
                )
            continue

        resolved.append(role)
        seen.add(role)
        queue.extend(_load_meta_dependencies(role_dir / "meta" / "main.yml"))

    return resolved


def _load_meta_dependencies(meta_file: Path) -> list[str]:
    """Extract dependent role names from a role's meta/main.yml."""
    if not meta_file.is_file():
        return []
    try:
        data = yaml.safe_load(meta_file.read_text(encoding="utf-8"))
    except yaml.YAMLError:
        return []
    if not isinstance(data, dict):
        return []
    deps = data.get("dependencies")
    if not isinstance(deps, list):
        return []

    names = []
    for dep in deps:
        if isinstance(dep, dict):
            role_name = dep.get("role")
            if isinstance(role_name, str) and role_name:
                names.append(role_name)
        elif isinstance(dep, str) and dep:
            names.append(dep)
    return names


def is_jinja(value: object) -> bool:
    """True for a string carrying a Jinja expression -- cannot be resolved."""
    return isinstance(value, str) and "{{" in value


def find_task_files(role_dir: Path) -> list[Path]:
    """Every YAML file under any 'tasks' directory in the role, sorted.

    Any file with a 'tasks' path component anywhere above it counts, not
    just direct children of role/tasks/ -- task trees can nest further.
    """
    return sorted(
        p for p in role_dir.rglob("*.yml") if p.is_file() and "tasks" in p.parts
    )


def _iter_maps(node: object):
    """Yield every dict anywhere in a nested YAML structure.

    block/rescue task lists are just nested lists, so recursing through
    lists as well as dicts finds tasks inside them without special-casing.
    """
    if isinstance(node, dict):
        yield node
        for value in node.values():
            yield from _iter_maps(value)
    elif isinstance(node, list):
        for item in node:
            yield from _iter_maps(item)


def extract_role_packages(role: str, roles_dir: Path, module_key: str) -> list[dict]:
    """Package task records ({name, state, role}) for one role.

    Deliberately does not evaluate `when:` -- a task gated on something
    other than distribution (a feature flag, a GNOME check) is still listed
    if its module matches this platform.
    """
    records = []
    for task_file in find_task_files(roles_dir / role):
        try:
            text = task_file.read_text(encoding="utf-8")
        except OSError:
            continue
        try:
            documents = list(yaml.safe_load_all(text))
        except yaml.YAMLError:
            # A malformed task file must not sink the whole scan -- it is
            # still reported by ansible-lint / ansible-playbook separately.
            continue
        for doc in documents:
            for node in _iter_maps(doc):
                if module_key not in node:
                    continue
                module = node[module_key]
                if isinstance(module, dict):
                    name = module.get("name")
                    state = module.get("state")
                else:
                    name = None
                    state = None
                records.append({"name": name, "state": state, "role": role})
    return records


def reduce_packages(records: list[dict]) -> tuple[list[dict], int]:
    """Fold task records into checked packages plus an unresolved count.

    Evaluation order is load-bearing:
      - a null name skips the record entirely (nothing to report either way)
      - a Jinja-templated state makes the whole task's name(s) unresolved
        (the intended state cannot be known statically)
      - state: absent drops the record (a removal, not a declaration)
      - each remaining name is checked unless it is itself unresolvable
    """
    packages: dict[tuple[str, str], dict] = {}
    unresolved = 0

    for record in records:
        name = record["name"]
        if name is None:
            continue

        state = record["state"] if record["state"] is not None else "present"
        if is_jinja(state):
            unresolved += len(name) if isinstance(name, list) else 1
            continue
        if state == "absent":
            continue

        names = name if isinstance(name, list) else [name]
        for candidate in names:
            # Anything that is not a plain resolvable string counts as
            # unresolved, not just a Jinja one -- never treat an
            # unrecognised name shape as "fine".
            if not isinstance(candidate, str) or is_jinja(candidate):
                unresolved += 1
                continue
            key = (candidate, record["role"])
            packages.setdefault(key, {"name": candidate, "role": record["role"]})

    sorted_packages = sorted(packages.values(), key=lambda p: (p["name"], p["role"]))
    return sorted_packages, unresolved


def report_packages(
    roles: list[str],
    scope_source: str,
    platform_name: str,
    roles_dir: Path,
    reporter: Reporter,
) -> tuple[int, int]:
    """Print section (b) and return (missing_count, unresolved_count)."""
    module_key = MODULE_KEYS[platform_name]
    platform_label = PLATFORM_LABELS[platform_name]

    records: list[dict] = []
    for role in roles:
        records.extend(extract_role_packages(role, roles_dir, module_key))

    packages, unresolved = reduce_packages(records)

    reporter.note(f"== Package check: {platform_label} ==")
    reporter.note(f"Role scope: {' '.join(roles)}  (source: {scope_source})")
    reporter.note(f"Declared packages checked: {len(packages)}")

    missing_count = 0
    for pkg in packages:
        if not pkg_installed(platform_name, pkg["name"]):
            reporter.problem(f"MISSING: {pkg['name']}  (declared by role '{pkg['role']}')")
            missing_count += 1

    reporter.note(f"Missing: {missing_count}")
    reporter.note("")

    # Printed through problem(), not note(), so --quiet cannot hide it. A
    # quiet run that checked nothing and said nothing is indistinguishable
    # from a clean host, which is the exact failure this tool exists to
    # report.
    if unresolved > 0:
        reporter.problem(
            f"UNRESOLVED: {unresolved} package name(s) could not be checked."
        )
        reporter.note(
            "These are loop-, variable-, or Jinja-built package names this static"
        )
        reporter.note(
            "YAML scan cannot evaluate. They are NOT checked above -- a clean report"
        )
        reporter.note("does not mean these are present. Inspect the role task files directly.")
    else:
        reporter.note("Unresolved package name(s): 0")
    reporter.note("")

    return missing_count, unresolved


# ============================================================================
# main
# ============================================================================


def main(argv: list[str] | None = None) -> int:
    # Block-buffered stdout would let a stderr warning (the unresolved-tag
    # note in resolve_roles) land ahead of already-printed stdout lines
    # whenever both streams are merged into one file or pipe -- line
    # buffering keeps their relative order what a reader actually sees.
    # Guarded: a test harness capturing stdout/stderr may swap in a stream
    # that does not support reconfigure().
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(line_buffering=True, encoding="utf-8", errors="replace")
    if hasattr(sys.stderr, "reconfigure"):
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")

    args = parse_args(list(argv) if argv is not None else sys.argv[1:])
    reporter = Reporter(quiet=args.quiet)

    # Overridable for testing against a stamp file that is not actually
    # root-owned system state, and against fixture roles that are not this
    # repo's real ansible/roles -- both read fresh here so a test process
    # can point them at tmp_path without reimporting the module.
    stamp_path = Path(
        os.environ.get("HYPERI_DOCTOR_STAMP", "/var/lib/hyperi-developer/applied.json")
    )
    roles_dir = Path(os.environ.get("HYPERI_DOCTOR_ROLES_DIR", str(ROLES_DIR)))

    platform_name = detect_platform()
    if platform_name not in MODULE_KEYS:
        die(
            f"unsupported or undetected platform ({platform.system()}) -- "
            "cannot map to apt/dnf/homebrew"
        )
    if platform_name == "macos" and shutil.which("brew") is None:
        die("'brew' is required and was not found on PATH")

    stamp_tags = report_stamp(stamp_path, reporter)

    if args.tags:
        scope_source = "--tags flag"
        roles_csv = args.tags
    elif stamp_tags:
        scope_source = "applied-state stamp"
        roles_csv = ",".join(stamp_tags)
    else:
        scope_source = "default (no --tags given, no stamp tags recorded)"
        roles_csv = "developer"

    roles = resolve_roles(roles_csv, roles_dir, reporter)
    if not roles:
        die(f"no role directories resolved from tags '{roles_csv}' -- nothing to check")

    missing_count, unresolved_count = report_packages(
        roles, scope_source, platform_name, roles_dir, reporter
    )

    # Three outcomes, not two. "Nothing missing" and "could not check
    # everything" are different answers, and collapsing them into exit 0 is
    # what lets a drift check pass a host it never looked at.
    if missing_count > 0:
        return 1
    if unresolved_count > 0:
        reporter.note("Nothing missing among the names that could be resolved.")
        return 2
    reporter.note("No declared packages missing for this scope.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
