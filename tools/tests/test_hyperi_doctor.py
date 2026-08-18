"""Tests for hyperi_doctor.py -- the Python port of tools/hyperi-doctor.

Hermetic by construction: every test builds its own fixture role tree under
tmp_path and points HYPERI_DOCTOR_ROLES_DIR / HYPERI_DOCTOR_STAMP at it, and
package presence is monkeypatched rather than read from this machine's real
dpkg database.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import hyperi_doctor


def make_role(roles_dir: Path, name: str, tasks_yaml: str, meta_yaml: str | None = None) -> None:
    """Write a fixture role with one tasks/main.yml (and optional meta)."""
    role_dir = roles_dir / name
    (role_dir / "tasks").mkdir(parents=True)
    (role_dir / "tasks" / "main.yml").write_text(tasks_yaml, encoding="utf-8")
    if meta_yaml is not None:
        (role_dir / "meta").mkdir(parents=True)
        (role_dir / "meta" / "main.yml").write_text(meta_yaml, encoding="utf-8")


def run(monkeypatch, tmp_path: Path, argv: list[str], stamp_path: Path | None = None) -> int:
    """Run main() against a fixture roles dir and (by default) no stamp."""
    monkeypatch.setenv("HYPERI_DOCTOR_ROLES_DIR", str(tmp_path / "roles"))
    monkeypatch.setenv(
        "HYPERI_DOCTOR_STAMP", str(stamp_path or (tmp_path / "no-such-stamp.json"))
    )
    return hyperi_doctor.main(argv)


def test_all_jinja_names_yield_zero_checked_and_exit_2(monkeypatch, tmp_path, capsys):
    """A role whose only package name is Jinja-built must never look clean."""
    make_role(
        tmp_path / "roles",
        "jinja-role",
        """\
- name: install templated package
  ansible.builtin.apt:
    name: "{{ some_package_var }}"
    state: present
""",
    )

    rc = run(monkeypatch, tmp_path, ["--tags", "jinja-role"])
    out = capsys.readouterr().out

    assert "Declared packages checked: 0" in out
    assert "UNRESOLVED: 1 package name(s) could not be checked." in out
    assert rc == 2


def test_unresolved_line_survives_quiet(monkeypatch, tmp_path, capsys):
    """The old bug: a quiet run with only Jinja names must not exit clean silently."""
    make_role(
        tmp_path / "roles",
        "jinja-role",
        """\
- name: install templated package
  ansible.builtin.apt:
    name: "{{ some_package_var }}"
    state: present
""",
    )

    rc = run(monkeypatch, tmp_path, ["--tags", "jinja-role", "--quiet"])
    out = capsys.readouterr().out

    # --quiet suppresses notes (including the stamp section and "Declared
    # packages checked"), but the unresolved line is a problem() and must
    # still be there -- a silent 0 would be the exact bug this tool exists
    # to prevent.
    assert "== Applied-state stamp ==" not in out
    assert "Declared packages checked" not in out
    assert "UNRESOLVED: 1 package name(s) could not be checked." in out
    assert rc == 2


def test_missing_package_exits_1(monkeypatch, tmp_path, capsys):
    make_role(
        tmp_path / "roles",
        "missing-role",
        """\
- name: install a package
  ansible.builtin.apt:
    name: definitely-not-installed-pkg
    state: present
""",
    )
    monkeypatch.setattr(hyperi_doctor, "pkg_installed", lambda platform, name: False)

    rc = run(monkeypatch, tmp_path, ["--tags", "missing-role"])
    out = capsys.readouterr().out

    assert "MISSING: definitely-not-installed-pkg  (declared by role 'missing-role')" in out
    assert rc == 1


def test_clean_role_exits_0(monkeypatch, tmp_path, capsys):
    make_role(
        tmp_path / "roles",
        "clean-role",
        """\
- name: install a package
  ansible.builtin.apt:
    name: some-installed-pkg
    state: present
""",
    )
    monkeypatch.setattr(hyperi_doctor, "pkg_installed", lambda platform, name: True)

    rc = run(monkeypatch, tmp_path, ["--tags", "clean-role"])
    out = capsys.readouterr().out

    assert "Declared packages checked: 1" in out
    assert "Missing: 0" in out
    assert "No declared packages missing for this scope." in out
    assert rc == 0


def test_missing_stamp_is_reported_not_an_error(monkeypatch, tmp_path, capsys):
    make_role(
        tmp_path / "roles",
        "clean-role",
        """\
- name: install a package
  ansible.builtin.apt:
    name: some-installed-pkg
    state: present
""",
    )
    monkeypatch.setattr(hyperi_doctor, "pkg_installed", lambda platform, name: True)

    rc = run(monkeypatch, tmp_path, ["--tags", "clean-role"])
    out = capsys.readouterr().out

    assert "No stamp found at" in out
    assert "Not treated as an error." in out
    assert rc == 0


def test_stamp_present_renders_age_and_sha_comparison(monkeypatch, tmp_path, capsys):
    make_role(
        tmp_path / "roles",
        "clean-role",
        """\
- name: install a package
  ansible.builtin.apt:
    name: some-installed-pkg
    state: present
""",
    )
    monkeypatch.setattr(hyperi_doctor, "pkg_installed", lambda platform, name: True)

    stamp_path = tmp_path / "applied.json"
    stamp_path.write_text(
        """\
{
  "sha": "0000000000000000000000000000000000000000",
  "timestamp": "2026-08-01T00:00:00Z",
  "tags": ["clean-role"],
  "target_user": "fixture-user",
  "warnings": 0
}
""",
        encoding="utf-8",
    )

    rc = run(monkeypatch, tmp_path, [], stamp_path=stamp_path)
    out = capsys.readouterr().out

    assert "Applied SHA:   0000000000000000000000000000000000000000" in out
    assert "Stamp age:     " in out
    assert "day(s)" in out
    assert "Checkout HEAD: " in out
    # A bogus SHA is not an ancestor of this checkout's real HEAD, so the
    # comparison falls into the "commit count unknown" branch.
    assert "commit count unknown" in out
    # Scope resolution must have come from the stamp's tags, not a default.
    assert "source: applied-state stamp" in out
    assert rc == 0


def test_state_absent_excluded_from_declared(monkeypatch, tmp_path, capsys):
    make_role(
        tmp_path / "roles",
        "absent-role",
        """\
- name: remove a package
  ansible.builtin.apt:
    name: retired-pkg
    state: absent

- name: install a package
  ansible.builtin.apt:
    name: kept-pkg
    state: present
""",
    )
    monkeypatch.setattr(hyperi_doctor, "pkg_installed", lambda platform, name: True)

    rc = run(monkeypatch, tmp_path, ["--tags", "absent-role"])
    out = capsys.readouterr().out

    assert "Declared packages checked: 1" in out
    assert "retired-pkg" not in out
    assert rc == 0


def test_nested_block_and_rescue_tasks_found(monkeypatch, tmp_path, capsys):
    make_role(
        tmp_path / "roles",
        "nested-role",
        """\
- name: wrapper
  block:
    - name: install nested thing
      ansible.builtin.apt:
        name: nested-pkg
        state: present
  rescue:
    - name: install rescue thing
      ansible.builtin.apt:
        name: rescue-pkg
        state: present
""",
    )
    monkeypatch.setattr(hyperi_doctor, "pkg_installed", lambda platform, name: True)

    rc = run(monkeypatch, tmp_path, ["--tags", "nested-role"])
    out = capsys.readouterr().out

    assert "Declared packages checked: 2" in out
    assert "Missing: 0" in out
    assert rc == 0


def test_role_dependency_expansion_via_meta(monkeypatch, tmp_path, capsys):
    """--tags on a child role must also check its meta/main.yml dependency."""
    roles_dir = tmp_path / "roles"
    make_role(
        roles_dir,
        "base-role",
        """\
- name: install base package
  ansible.builtin.apt:
    name: base-pkg
    state: present
""",
    )
    make_role(
        roles_dir,
        "child-role",
        """\
- name: install child package
  ansible.builtin.apt:
    name: child-pkg
    state: present
""",
        meta_yaml="""\
---
dependencies:
  - role: base-role
""",
    )
    monkeypatch.setattr(hyperi_doctor, "pkg_installed", lambda platform, name: True)

    rc = run(monkeypatch, tmp_path, ["--tags", "child-role"])
    out = capsys.readouterr().out

    assert "Role scope: child-role base-role" in out
    assert "Declared packages checked: 2" in out
    assert rc == 0
