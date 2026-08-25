"""Fail when a role task references a file its own role does not carry.

Ansible resolves `copy:`/`template:` `src:` against the CURRENT role's files/
(or templates/) directory and the playbook directory -- never a sibling role.
A file move that leaves the task behind, or a task move that leaves the file
behind, therefore breaks only at runtime, on the host, partway through a real
install. Neither ansible-lint nor a syntax check sees it.

That is exactly how the ghostty assets stayed in `developer` when their tasks
moved to `developer-gui` (issue #52): nine dead references that survived every
gate for three months.

Run: python3 tools/check_role_file_refs.py
"""

from __future__ import annotations

import pathlib
import re
import sys

ROLES = pathlib.Path(__file__).resolve().parent.parent / "ansible" / "roles"
PLAYBOOKS = pathlib.Path(__file__).resolve().parent.parent / "ansible" / "playbooks"

# `src: foo/bar` on its own line, including a templated one. A src that starts
# with a template resolves entirely at run time; one with a literal prefix
# (`dconf-defaults-{{ ui_mode }}`) is checked by globbing that prefix.
SRC = re.compile(r"^\s*src:\s*(?!['\"]?\{\{)['\"]?([^'\"\s{][^'\"\n]*?)['\"]?\s*$")

# The module decides which directory the src is looked up in.
MODULE_DIR = {"copy": "files", "template": "templates", "unarchive": "files"}
MODULE = re.compile(r"^\s*(?:ansible\.builtin\.)?(copy|template|unarchive):\s*$")


def module_for(lines: list[str], index: int) -> str | None:
    """Walk back from a src: line to the module key that owns it."""
    for j in range(index, max(index - 12, -1), -1):
        m = MODULE.match(lines[j])
        if m:
            return m.group(1)
        # A new task starts with "- name:" at any indent; stop there.
        if re.match(r"^\s*-\s+name:", lines[j]) and j != index:
            return None
    return None


def main() -> int:
    failures: list[str] = []
    checked = 0
    skipped = 0

    for role in sorted(p for p in ROLES.iterdir() if p.is_dir()):
        for task_file in sorted(role.rglob("tasks/*.yml")):
            lines = task_file.read_text(encoding="utf-8", errors="replace").splitlines()
            for i, line in enumerate(lines):
                m = SRC.match(line)
                if not m:
                    continue
                src = m.group(1).strip()
                # An absolute src is a path on the target, not a role asset.
                if src.startswith("/"):
                    continue
                module = module_for(lines, i)
                if module is None:
                    skipped += 1
                    continue
                # remote_src: true reads from the target, not the controller.
                window = "\n".join(lines[i : i + 8])
                if re.search(r"^\s*remote_src:\s*(true|yes)", window, re.MULTILINE):
                    continue

                subdir = MODULE_DIR[module]
                target = src.rstrip("/")
                rel = task_file.relative_to(ROLES.parent.parent)

                if "{{" in target:
                    prefix = target.split("{{", 1)[0]
                    if not prefix:
                        skipped += 1
                        continue
                    checked += 1
                    if any((role / subdir).glob(f"{prefix}*")):
                        continue
                    failures.append(
                        f"{rel}:{i + 1}  {module}: src: {target}\n"
                        f"    nothing matches {prefix}* in {(role / subdir).relative_to(ROLES.parent.parent)}"
                    )
                    continue

                checked += 1
                candidate = role / subdir / target
                if candidate.exists():
                    continue
                # The playbook directory is the documented second lookup.
                if (PLAYBOOKS / subdir / target).exists():
                    continue

                failures.append(
                    f"{rel}:{i + 1}  {module}: src: {src}\n"
                    f"    not found at {candidate.relative_to(ROLES.parent.parent)}"
                )

    if failures:
        print(f"{len(failures)} role file reference(s) resolve to nothing:\n")
        for failure in failures:
            print(failure)
        print(
            "\nAnsible looks in the CURRENT role's directory only. Move the file "
            "to the role that owns the task, or point the task at the role that "
            "owns the file."
        )
        return 1

    print(f"    ok ({checked} role file reference(s) resolve; {skipped} templated, not checked)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
