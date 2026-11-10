"""Tests for hyperi-rust-setup's hand-over on a Python without tomllib.

macOS's python3 is 3.9, which has no tomllib. The script is run here with
tomllib hidden, which is the same import failure.
"""

import os
import subprocess
import sys
from pathlib import Path

SCRIPT = (
    Path(__file__).resolve().parents[2]
    / "ansible/roles/developer-rust/files/hyperi-rust-setup"
)

RUN_WITHOUT_TOMLLIB = (
    "import runpy, sys; sys.modules['tomllib'] = None; "
    "sys.argv = sys.argv[1:]; runpy.run_path(sys.argv[0], run_name='__main__')"
)


def run_without_tomllib(home: Path) -> subprocess.CompletedProcess:
    env = {**os.environ, "HOME": str(home)}
    return subprocess.run(
        [sys.executable, "-c", RUN_WITHOUT_TOMLLIB, str(SCRIPT), "--check"],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        env=env,
        check=False,
    )


def test_it_hands_over_to_the_uv_python_with_the_same_arguments(tmp_path):
    bin_dir = tmp_path / ".local" / "bin"
    bin_dir.mkdir(parents=True)
    fake = bin_dir / "python3.14"
    fake.write_text('#!/bin/sh\necho "handed over: $*"\n', encoding="utf-8")
    fake.chmod(0o755)

    result = run_without_tomllib(tmp_path)

    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == f"handed over: {SCRIPT} --check"


def test_it_names_the_python_it_needs_when_there_is_none(tmp_path):
    result = run_without_tomllib(tmp_path)

    assert result.returncode == 2
    assert "needs Python 3.11 or later" in result.stderr
    assert "Traceback" not in result.stderr


def test_a_dangling_uv_python_is_not_handed_over_to(tmp_path):
    bin_dir = tmp_path / ".local" / "bin"
    bin_dir.mkdir(parents=True)
    (bin_dir / "python3.14").symlink_to(tmp_path / "gone" / "python3.14")

    result = run_without_tomllib(tmp_path)

    assert result.returncode == 2
    assert "needs Python 3.11 or later" in result.stderr
