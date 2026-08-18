"""Tests for the hyperi_versions / hyperi-ci pin comparison."""

import importlib.util
from pathlib import Path

import pytest

MODULE = Path(__file__).resolve().parents[1] / "check_version_pins.py"


def load_module():
    spec = importlib.util.spec_from_file_location("check_version_pins", MODULE)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope="module")
def check():
    return load_module()


def test_matching_pins_are_clean(check):
    problems, notes = check.compare({"gosec": "v2.28.0"}, {"gosec": "v2.28.0"})
    assert problems == []
    assert notes == []


def test_a_disagreeing_version_is_a_problem(check):
    """The drift that actually happened: hyperi-ci moved, this repo did not."""
    problems, _ = check.compare({"gosec": "v2.27.1"}, {"gosec": "v2.28.0"})
    assert len(problems) == 1
    assert "v2.27.1" in problems[0]
    assert "v2.28.0" in problems[0]


def test_drift_is_caught_in_either_direction(check):
    """A hand-edit here is as wrong as a missed bump from there."""
    ahead, _ = check.compare({"gosec": "v9.9.9"}, {"gosec": "v2.28.0"})
    behind, _ = check.compare({"gosec": "v1.0.0"}, {"gosec": "v2.28.0"})
    assert ahead and behind


def test_pinning_a_tool_ci_does_not_pin_is_a_problem(check):
    """An entry with no counterpart pins a version CI never runs."""
    problems, _ = check.compare({"ripgrep": "v14.0.0"}, {"gosec": "v2.28.0"})
    assert len(problems) == 1
    assert "does not pin it at all" in problems[0]


def test_a_tool_ci_pins_but_we_do_not_is_only_a_note(check):
    """An absent entry falls back to latest, which is documented behaviour."""
    problems, notes = check.compare({}, {"gosec": "v2.28.0"})
    assert problems == []
    assert len(notes) == 1
    assert "falls back to latest" in notes[0]


def test_local_pins_reads_the_group_vars_shape(check, tmp_path):
    pins = tmp_path / "all.yml"
    pins.write_text(
        "hyperi_pinned: false\nhyperi_versions:\n  gosec: v2.28.0\n  alint: v0.14.1\n",
        encoding="utf-8",
    )
    assert check.local_pins(pins) == {"gosec": "v2.28.0", "alint": "v0.14.1"}


def test_a_file_without_the_map_yields_nothing(check, tmp_path):
    """Absent is empty, not a crash -- the caller decides what that means."""
    pins = tmp_path / "all.yml"
    pins.write_text("hyperi_pinned: false\n", encoding="utf-8")
    assert check.local_pins(pins) == {}


def test_missing_hyperi_ci_skips_rather_than_fails(check, tmp_path, monkeypatch, capsys):
    """A runner without hyperi-ci must stay green, as the other checks do."""
    monkeypatch.setattr(check, "hyperi_ci_python", lambda: None)
    assert check.main(["--pins-file", str(tmp_path / "absent.yml")]) == 0
    assert "skipping" in capsys.readouterr().out


def test_drift_exits_non_zero(check, tmp_path, monkeypatch, capsys):
    pins = tmp_path / "all.yml"
    pins.write_text("hyperi_versions:\n  gosec: v2.27.1\n", encoding="utf-8")
    monkeypatch.setattr(check, "hyperi_ci_python", lambda: Path("/nonexistent/python"))
    monkeypatch.setattr(check, "ci_pins", lambda _python: {"gosec": "v2.28.0"})

    assert check.main(["--pins-file", str(pins)]) == 1
    assert "DRIFT" in capsys.readouterr().out


def test_matching_pins_exit_zero(check, tmp_path, monkeypatch):
    pins = tmp_path / "all.yml"
    pins.write_text("hyperi_versions:\n  gosec: v2.28.0\n", encoding="utf-8")
    monkeypatch.setattr(check, "hyperi_ci_python", lambda: Path("/nonexistent/python"))
    monkeypatch.setattr(check, "ci_pins", lambda _python: {"gosec": "v2.28.0"})

    assert check.main(["--pins-file", str(pins)]) == 0
