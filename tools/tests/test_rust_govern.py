"""Tests for hyperi-rust-govern, the cargo shim.

The shim is bash, so it is exercised as a subprocess against a fake cargo that
reports what it was handed. XDG_RUNTIME_DIR is removed from every run, which
forces the no-user-bus path on any host: the systemd scope path needs a live
user manager and is covered by the role's converge on a real machine, not here.
"""

import os
import shutil
import socket
import subprocess
import sys
from pathlib import Path

import pytest

SCRIPT = (
    Path(__file__).resolve().parents[2]
    / "ansible/roles/developer-rust/files/hyperi-rust-govern"
)

FAKE_CARGO = """#!/bin/sh
echo "nice=$(nice)"
echo "args=$*"
echo "governed=${HYPERI_RUST_GOVERNED:-unset}"
echo "jobs=${CARGO_BUILD_JOBS:-unset}"
echo "incremental=${CARGO_INCREMENTAL:-unset}"
exit 42
"""

pytestmark = pytest.mark.skipif(
    sys.platform == "win32"
    or shutil.which("bash") is None
    or shutil.which("nice") is None,
    reason="the shim is a POSIX bash script and needs nice(1)",
)


def parse(stdout):
    return dict(line.split("=", 1) for line in stdout.splitlines() if "=" in line)


@pytest.fixture
def host(tmp_path):
    """A fake cargo home, an empty config dir, and a minimal environment.

    Built from scratch rather than copied from the process: no XDG_RUNTIME_DIR
    means the no-user-bus path on every host, and nothing from the runner's
    environment (a CI secret, say) can reach a failure report.
    """
    cargo_home = tmp_path / "cargo-home"
    (cargo_home / "bin").mkdir(parents=True)
    fake = cargo_home / "bin" / "cargo"
    fake.write_text(FAKE_CARGO, encoding="utf-8", newline="\n")
    fake.chmod(0o755)
    env = {
        "PATH": os.environ["PATH"],
        "HOME": str(tmp_path),
        "CARGO_HOME": str(cargo_home),
    }
    return {"tmp": tmp_path, "cargo_home": cargo_home, "env": env}


def run(host, *args, env_extra=None, script=SCRIPT):
    """Run the shim under bash: role files are tracked 0644 and made executable at deploy."""
    env = dict(host["env"])
    if env_extra:
        for k, v in env_extra.items():
            if v is None:
                env.pop(k, None)
            else:
                env[k] = v
    return subprocess.run(
        ["bash", str(script), *args],
        env=env,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )


def baseline_nice(host):
    out = subprocess.run(
        ["nice"], env=host["env"], capture_output=True, text=True, check=True
    )
    return int(out.stdout.strip())


def write_conf(host, body):
    conf_dir = host["tmp"] / ".config" / "hyperi"
    conf_dir.mkdir(parents=True, exist_ok=True)
    (conf_dir / "rust-governor.conf").write_text(body, encoding="utf-8", newline="\n")


def test_governed_build_runs_at_nice_19_with_no_job_count(host):
    result = run(host, "cargo", "build", "--release")
    got = parse(result.stdout)
    assert result.returncode == 42, result.stderr
    assert got["nice"] == "19"
    assert got["args"] == "build --release"
    assert got["governed"] == "1"
    assert got["jobs"] == "unset"


def test_bypass_runs_the_real_tool_untouched(host):
    result = run(host, "cargo", "run", env_extra={"HYPERI_RUST_GOVERNOR": "off"})
    got = parse(result.stdout)
    assert result.returncode == 42
    assert got["nice"] == str(baseline_nice(host))
    assert got["governed"] == "unset"


def test_already_governed_tree_is_not_governed_twice(host):
    """cargo re-invokes cargo for build scripts and proxies; the marker stops recursion."""
    result = run(host, "cargo", "check", env_extra={"HYPERI_RUST_GOVERNED": "1"})
    got = parse(result.stdout)
    assert result.returncode == 42
    assert got["nice"] == str(baseline_nice(host))


def test_conf_turns_incremental_off_and_the_caller_still_wins(host):
    write_conf(
        host,
        'HYPERI_RUST_GOVERN_NO_INCREMENTAL="${HYPERI_RUST_GOVERN_NO_INCREMENTAL:-1}"\n',
    )
    assert parse(run(host, "cargo", "build").stdout)["incremental"] == "0"
    assert (
        parse(run(host, "cargo", "build", env_extra={"CARGO_INCREMENTAL": "1"}).stdout)[
            "incremental"
        ]
        == "1"
    )
    assert (
        parse(
            run(
                host,
                "cargo",
                "build",
                env_extra={"HYPERI_RUST_GOVERN_NO_INCREMENTAL": "0"},
            ).stdout
        )["incremental"]
        == "unset"
    )


def test_incremental_is_left_alone_without_a_conf(host):
    assert parse(run(host, "cargo", "build").stdout)["incremental"] == "unset"


def test_symlink_named_cargo_on_path_resolves_the_real_cargo(host):
    """The role installs the shim as ~/.local/bin/cargo; it must not exec itself."""
    shimbin = host["tmp"] / "shimbin"
    shimbin.mkdir()
    link = shimbin / "cargo"
    link.symlink_to(SCRIPT)
    result = run(
        host,
        "build",
        env_extra={"PATH": f"{shimbin}{os.pathsep}{host['env']['PATH']}"},
        script=link,
    )
    got = parse(result.stdout)
    assert result.returncode == 42, result.stderr
    assert got["nice"] == "19"
    assert got["args"] == "build"


def test_missing_real_tool_exits_127(host):
    result = run(host, "no-such-tool", "anything")
    assert result.returncode == 127
    assert "no real 'no-such-tool'" in result.stderr


def test_no_command_is_a_usage_error(host):
    result = run(host)
    assert result.returncode == 64
    assert "usage:" in result.stderr


def test_dead_user_bus_falls_back_to_nice(host):
    """A bus socket left behind by a dead session must not fail the build.

    The file passes the -S test; only the reachability probe tells the shim the
    manager is gone, and the build has to land on the plain nice path.
    """
    deadrun = host["tmp"] / "deadrun"
    deadrun.mkdir()
    sock = socket.socket(socket.AF_UNIX)
    sock.bind(str(deadrun / "bus"))
    sock.close()
    result = run(host, "cargo", "build", env_extra={"XDG_RUNTIME_DIR": str(deadrun)})
    got = parse(result.stdout)
    assert result.returncode == 42, result.stderr
    assert got["nice"] == "19"
    assert got["governed"] == "1"


def test_runs_with_home_unset(host):
    """A system unit or env -i has no HOME; set -u must not abort the shim."""
    result = run(host, "cargo", "build", env_extra={"HOME": None})
    assert result.returncode == 42, result.stderr
    assert parse(result.stdout)["nice"] == "19"
