#!/usr/bin/env python3
"""Check that the supported-release matrix is declared once and mirrored.

`ansible/molecule/vars.yml` is the SSoT for which releases are supported, but
nothing read it. Two other files restated the same window and were kept in step
by hand-written comments, which is exactly how the drift its own header records
happened: vars.yml called Fedora 43 the n-1 slot while the role still pinned
min_fedora_version to 42, two months after 42 went EOL.

Molecule cannot include another YAML file, so `molecule/matrix/molecule.yml`
must repeat the image list. This makes that repetition checked rather than
trusted.

The playbook's own OS gate is a third copy, hardcoded in a `when:` because
pre_tasks run before role defaults are in scope. It is matched by pattern here
rather than rewritten, so the two gates cannot disagree again -- which is how
Fedora 42 kept passing this one after the role was fixed.

Not covered: the codename lists that track the same window
(docker_supported_suites, the git-core PPA series). Checking those needs a
version-to-codename map, which would be one more copy of the thing being
checked.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent
MATRIX_FILE = REPO_ROOT / "ansible/molecule/vars.yml"
MOLECULE_FILE = REPO_ROOT / "ansible/molecule/matrix/molecule.yml"
DEFAULTS_FILE = REPO_ROOT / "ansible/roles/developer/defaults/main.yml"
PLAYBOOK_FILE = REPO_ROOT / "ansible/playbooks/main.yml"
UPDATE_TEST_FILE = REPO_ROOT / "ansible/tests/update/test-hyperi-update.sh"

# The two comparisons inside the pre_tasks OS gate. Matched on the source text
# because the gate is a Jinja expression, not data.
GATE_PATTERNS = {
    "Fedora": re.compile(r"distribution_major_version[^|]*\|\s*int\s*<\s*(\d+)"),
    "Ubuntu": re.compile(r"is\s+version\(\s*'([\d.]+)'\s*,\s*'<'\s*\)"),
}

# The update test's own image list, a bash array rather than YAML.
IMAGES_ARRAY = re.compile(r"DEFAULT_IMAGES=\((.*?)\)", re.DOTALL)


def bare_image(image: str) -> str:
    """`docker.io/library/fedora:44` and `fedora:44` name the same image."""
    return image.rsplit("/", 1)[-1]


def load(path: Path) -> dict:
    return yaml.safe_load(path.read_text(encoding="utf-8")) or {}


def declared_matrix(data: dict) -> list[dict]:
    return data.get("molecule_matrix") or []


def platform_images(data: dict) -> list[str]:
    return [p["image"] for p in (data.get("platforms") or []) if "image" in p]


def oldest_supported(matrix: list[dict], distro: str) -> str | None:
    """The n-1 release for a distro, which IS the declared minimum."""
    for entry in matrix:
        if entry.get("distro") == distro and entry.get("rank") == "n-1":
            return str(entry.get("release"))
    return None


def gate_minimums(playbook_text: str) -> dict[str, str | None]:
    """The minimums the pre_tasks OS gate actually enforces."""
    found = {}
    for distro, pattern in GATE_PATTERNS.items():
        match = pattern.search(playbook_text)
        found[distro] = match.group(1) if match else None
    return found


def update_test_images(script_text: str) -> list[str] | None:
    """The image list the hyperi-update test sweeps, or None if unparsable."""
    match = IMAGES_ARRAY.search(script_text)
    if not match:
        return None
    return re.findall(r'"([^"]+)"', match.group(1))


def compare(
    matrix: list[dict],
    molecule: dict,
    defaults: dict,
    playbook_text: str = "",
    update_test_text: str = "",
) -> list[str]:
    problems: list[str] = []

    declared = {str(e["image"]) for e in matrix if "image" in e}
    used = set(platform_images(molecule))

    problems += [
        f"molecule/matrix declares {image}, absent from molecule_matrix"
        for image in sorted(used - declared)
    ]
    problems += [
        f"molecule_matrix declares {image}, not tested by molecule/matrix"
        for image in sorted(declared - used)
    ]

    # The declared minimum must BE the n-1 slot; anything else means one of the
    # two moved without the other.
    for distro, key, coerce in (
        ("Fedora", "min_fedora_version", str),
        ("Ubuntu", "min_ubuntu_version", str),
    ):
        expected = oldest_supported(matrix, distro)
        if expected is None:
            problems.append(f"molecule_matrix has no {distro} n-1 entry")
            continue
        actual = coerce(defaults.get(key, ""))
        if actual != expected:
            problems.append(
                f"{key} is {actual!r}, but molecule_matrix says {distro} n-1 is {expected!r}"
            )

    if playbook_text:
        gate = gate_minimums(playbook_text)
        for distro in ("Fedora", "Ubuntu"):
            expected = oldest_supported(matrix, distro)
            if expected is None:
                continue
            enforced = gate[distro]
            if enforced is None:
                problems.append(f"the playbook OS gate has no {distro} comparison to check")
            elif enforced != expected:
                problems.append(
                    f"the playbook OS gate admits {distro} {enforced}, "
                    f"but molecule_matrix says n-1 is {expected}"
                )

    if update_test_text:
        swept = update_test_images(update_test_text)
        if swept is None:
            problems.append("the hyperi-update test's DEFAULT_IMAGES list is unreadable")
        else:
            want = {bare_image(str(e["image"])) for e in matrix if "image" in e}
            got = {bare_image(i) for i in swept}
            problems += [
                f"the hyperi-update test sweeps {image}, absent from molecule_matrix"
                for image in sorted(got - want)
            ]
            problems += [
                f"molecule_matrix declares {image}, not swept by the hyperi-update test"
                for image in sorted(want - got)
            ]

    return problems


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--matrix-file", type=Path, default=MATRIX_FILE)
    parser.add_argument("--molecule-file", type=Path, default=MOLECULE_FILE)
    parser.add_argument("--defaults-file", type=Path, default=DEFAULTS_FILE)
    parser.add_argument("--playbook-file", type=Path, default=PLAYBOOK_FILE)
    parser.add_argument("--update-test-file", type=Path, default=UPDATE_TEST_FILE)
    args = parser.parse_args(argv)

    for path in (
        args.matrix_file,
        args.molecule_file,
        args.defaults_file,
        args.playbook_file,
        args.update_test_file,
    ):
        if not path.is_file():
            print(f"    FAILED: {path} is missing")
            return 1

    matrix = declared_matrix(load(args.matrix_file))
    if not matrix:
        print(f"    FAILED: {args.matrix_file} declares no molecule_matrix")
        return 1

    problems = compare(
        matrix,
        load(args.molecule_file),
        load(args.defaults_file),
        args.playbook_file.read_text(encoding="utf-8"),
        args.update_test_file.read_text(encoding="utf-8"),
    )

    for problem in problems:
        print(f"    DRIFT: {problem}")

    if problems:
        print(f"    {len(problems)} disagreement(s) with the declared release matrix.")
        print("    molecule/vars.yml is the SSoT -- bump it and mirror it, or the")
        print("    tests and the OS gate stop describing the same set of releases.")
        return 1

    print(f"    ok ({len(matrix)} release(s) declared, tested, and gated consistently)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
