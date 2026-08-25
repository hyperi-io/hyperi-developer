"""The check must FAIL on a file left behind by a task move.

A check that only ever passes proves nothing, so every case here builds a role
tree that is wrong in one specific way and asserts the checker says so.
"""

from __future__ import annotations

import importlib.util
import pathlib
import sys

MODULE_PATH = pathlib.Path(__file__).resolve().parent.parent / "check_role_file_refs.py"


def load_checker(roles: pathlib.Path, playbooks: pathlib.Path):
    spec = importlib.util.spec_from_file_location("check_role_file_refs", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    sys.modules["check_role_file_refs"] = module
    spec.loader.exec_module(module)
    module.ROLES = roles
    module.PLAYBOOKS = playbooks
    return module


def build(tmp_path: pathlib.Path, task_body: str, files: dict[str, str] | None = None):
    roles = tmp_path / "ansible" / "roles"
    playbooks = tmp_path / "ansible" / "playbooks"
    playbooks.mkdir(parents=True)
    tasks = roles / "demo" / "tasks"
    tasks.mkdir(parents=True)
    (tasks / "main.yml").write_text(task_body, encoding="utf-8")
    for name, content in (files or {}).items():
        target = roles / "demo" / "files" / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8")
    return load_checker(roles, playbooks)


COPY = """---
- name: Deploy a thing
  ansible.builtin.copy:
    src: ghostty/config
    dest: /etc/thing
"""


def test_missing_file_fails(tmp_path, capsys):
    checker = build(tmp_path, COPY)
    assert checker.main() == 1
    assert "ghostty/config" in capsys.readouterr().out


def test_present_file_passes(tmp_path):
    checker = build(tmp_path, COPY, {"ghostty/config": "x"})
    assert checker.main() == 0


def test_templated_prefix_is_checked(tmp_path, capsys):
    body = """---
- name: Deploy defaults
  ansible.builtin.copy:
    src: "dconf-defaults-{{ ui_mode }}"
    dest: /etc/thing
"""
    checker = build(tmp_path, body)
    assert checker.main() == 1
    assert "dconf-defaults-" in capsys.readouterr().out


def test_templated_prefix_matching_a_file_passes(tmp_path):
    body = """---
- name: Deploy defaults
  ansible.builtin.copy:
    src: "dconf-defaults-{{ ui_mode }}"
    dest: /etc/thing
"""
    checker = build(tmp_path, body, {"dconf-defaults-winlike": "x"})
    assert checker.main() == 0


def test_fully_templated_src_is_skipped(tmp_path):
    body = """---
- name: Deploy whatever
  ansible.builtin.copy:
    src: "{{ some_var }}"
    dest: /etc/thing
"""
    checker = build(tmp_path, body)
    assert checker.main() == 0


def test_remote_src_is_not_a_controller_file(tmp_path):
    body = """---
- name: Unpack on the target
  ansible.builtin.unarchive:
    src: /tmp/thing.tar.gz
    dest: /opt
    remote_src: true
"""
    checker = build(tmp_path, body)
    assert checker.main() == 0


def test_template_module_looks_in_templates(tmp_path):
    body = """---
- name: Render a unit
  ansible.builtin.template:
    src: thing.service.j2
    dest: /etc/systemd/system/thing.service
"""
    checker = build(tmp_path, body)
    assert checker.main() == 1
    roles = tmp_path / "ansible" / "roles"
    (roles / "demo" / "templates").mkdir(parents=True)
    (roles / "demo" / "templates" / "thing.service.j2").write_text("x", encoding="utf-8")
    assert checker.main() == 0


def test_playbook_files_dir_is_the_second_lookup(tmp_path):
    checker = build(tmp_path, COPY)
    shared = tmp_path / "ansible" / "playbooks" / "files" / "ghostty"
    shared.mkdir(parents=True)
    (shared / "config").write_text("x", encoding="utf-8")
    assert checker.main() == 0
