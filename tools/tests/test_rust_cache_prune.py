"""Tests for hyperi-rust-cache-prune's config reading and size resolution.

The script ships as an extensionless executable in an Ansible role's files/,
so it is loaded by path rather than imported by name.
"""

import argparse
import fcntl
import importlib.util
import os
import sys
import time
from pathlib import Path
from types import SimpleNamespace

import pytest

SCRIPT = (
    Path(__file__).resolve().parents[2]
    / "ansible/roles/developer-rust/files/hyperi-rust-cache-prune"
)


def load_module():
    spec = importlib.util.spec_from_loader(
        "hyperi_rust_cache_prune",
        importlib.machinery.SourceFileLoader("hyperi_rust_cache_prune", str(SCRIPT)),
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope="module")
def prune():
    return load_module()


def write_cargo_config(tmp_path, body):
    cargo_home = tmp_path / ".cargo"
    cargo_home.mkdir(parents=True, exist_ok=True)
    (cargo_home / "config.toml").write_text(body, encoding="utf-8")
    return cargo_home


def test_wrapper_comes_from_the_cargo_config_not_path(prune, tmp_path, monkeypatch):
    """The report must follow the binary cargo wraps builds with.

    A cargo-installed sccache shadows a packaged one on PATH and the two are
    routinely different versions, so asking PATH talks the wrong protocol at
    the server cargo actually started.
    """
    cargo_home = write_cargo_config(
        tmp_path,
        '[build]\nrustc-wrapper = "/usr/bin/sccache"\n',
    )
    monkeypatch.setenv("CARGO_HOME", str(cargo_home))
    assert prune.configured_wrapper() == Path("/usr/bin/sccache")


def test_wrapper_is_none_when_the_wrapper_is_not_sccache(prune, tmp_path, monkeypatch):
    cargo_home = write_cargo_config(
        tmp_path,
        '[build]\nrustc-wrapper = "/usr/bin/some-other-wrapper"\n',
    )
    monkeypatch.setenv("CARGO_HOME", str(cargo_home))
    assert prune.configured_wrapper() is None


def test_wrapper_is_none_without_a_config(prune, tmp_path, monkeypatch):
    monkeypatch.setenv("CARGO_HOME", str(tmp_path / "absent"))
    assert prune.configured_wrapper() is None


def test_pool_strips_cargos_path_template(prune, tmp_path, monkeypatch):
    cargo_home = write_cargo_config(
        tmp_path,
        '[build]\nbuild-dir = "/home/someone/.cache/pool/{workspace-path-hash}"\n',
    )
    monkeypatch.setenv("CARGO_HOME", str(cargo_home))
    assert prune.configured_pool() == Path("/home/someone/.cache/pool")


def test_malformed_config_does_not_raise(prune, tmp_path, monkeypatch):
    """An unparseable config must not take the prune down with it."""
    cargo_home = write_cargo_config(tmp_path, "this is not = valid toml [[[\n")
    monkeypatch.setenv("CARGO_HOME", str(cargo_home))
    assert prune.cargo_config() == {}
    assert prune.configured_pool() is None


def test_auto_size_is_a_share_of_the_disk_with_a_floor(prune, tmp_path, monkeypatch):
    """`auto` derives from the filesystem total, and never drops below the floor."""
    monkeypatch.setenv("HOME", str(tmp_path))
    rep = prune.Reporter()
    resolved = prune.resolve_max_size("auto", tmp_path, rep)
    floor = prune.parse_size(prune.AUTO_FLOOR)
    assert resolved >= floor

    import shutil

    total = shutil.disk_usage(tmp_path).total
    assert resolved == max(total // prune.AUTO_FRACTION, floor)


def test_an_explicit_size_overrides_auto(prune, tmp_path):
    rep = prune.Reporter()
    assert prune.resolve_max_size(prune.parse_size("64G"), tmp_path, rep) == prune.parse_size("64G")


def test_parse_size_accepts_auto_and_sizes(prune):
    assert prune.parse_size_or_auto("auto") == "auto"
    assert prune.parse_size_or_auto("  AUTO ") == "auto"
    assert prune.parse_size_or_auto("40G") == prune.parse_size("40G")


# ---------------------------------------------------------------------------
# The free-space guard
# ---------------------------------------------------------------------------


def fake_usage(total, free):
    """Stand in for shutil.disk_usage, which only .total and .free are read from."""
    return SimpleNamespace(total=total, used=total - free, free=free)


def test_floor_accepts_a_percentage(prune):
    assert prune.parse_size_or_percent("20%") == ("percent", 20.0)
    assert prune.parse_size_or_percent("  7.5 % ") == ("percent", 7.5)


def test_floor_accepts_a_byte_count(prune):
    assert prune.parse_size_or_percent("80G") == ("bytes", prune.parse_size("80G"))


@pytest.mark.parametrize("text", ["0%", "100%", "-5%", "abc", ""])
def test_floor_rejects_what_cannot_be_a_floor(prune, text):
    """0 and 100 are rejected as well as junk: neither can gate anything."""
    with pytest.raises(argparse.ArgumentTypeError):
        prune.parse_size_or_percent(text)


def test_guard_does_nothing_while_there_is_room(prune, tmp_path, monkeypatch):
    """The whole point of the guard is being cheap when it has no work.

    Above the floor it must answer from one statvfs and never reach the pool.
    """
    monkeypatch.setattr(prune.shutil, "disk_usage", lambda _: fake_usage(1000, 500))
    assert prune.above_free_floor(tmp_path, ("percent", 20.0), prune.Reporter()) is True


def test_guard_lets_the_prune_through_when_space_is_short(prune, tmp_path, monkeypatch):
    monkeypatch.setattr(prune.shutil, "disk_usage", lambda _: fake_usage(1000, 100))
    assert prune.above_free_floor(tmp_path, ("percent", 20.0), prune.Reporter()) is False


def test_guard_takes_a_byte_floor_as_well(prune, tmp_path, monkeypatch):
    monkeypatch.setattr(prune.shutil, "disk_usage", lambda _: fake_usage(1000, 100))
    assert prune.above_free_floor(tmp_path, ("bytes", 50), prune.Reporter()) is True
    assert prune.above_free_floor(tmp_path, ("bytes", 150), prune.Reporter()) is False


def make_pool(tmp_path, sizes):
    """Build a pool at cargo's shard depth, one leaf per given byte size."""
    pool = tmp_path / "pool"
    for index, size in enumerate(sizes):
        leaf = pool / f"{index:02x}" / f"hash{index}"
        leaf.mkdir(parents=True)
        (leaf / "artefact.bin").write_bytes(b"\0" * size)
    return pool


def test_the_reported_total_counts_only_evictions_that_worked(prune, tmp_path, monkeypatch):
    """A failed rmtree must leave its bytes in the total.

    Crediting them anyway reports the pool back under its ceiling while it is
    still over, which is the one thing the guard's verdict rests on.
    """
    pool = make_pool(tmp_path, [200_000, 200_000, 200_000])

    def refuse(_path):
        raise OSError("permission denied")

    monkeypatch.setattr(prune.shutil, "rmtree", refuse)
    rep = prune.Reporter()
    remaining = prune_pool_at(prune, pool, rep, max_size=1)

    assert rep.freed == 0
    assert remaining > 1, "a pool whose evictions all failed is still over its ceiling"
    assert rep.warnings


def test_the_reported_total_drops_when_evictions_succeed(prune, tmp_path):
    pool = make_pool(tmp_path, [200_000, 200_000, 200_000])
    rep = prune.Reporter()
    before = prune_pool_at(prune, pool, rep, max_size=10**9)

    rep_two = prune.Reporter()
    after = prune_pool_at(prune, pool, rep_two, max_size=1)

    assert after < before
    assert rep_two.freed > 0


def prune_pool_at(prune, pool, rep, *, max_size):
    """prune_pool with the age pass held off, so only the size pass is in play."""
    return prune.prune_pool(pool, False, rep, max_size=max_size, max_age_days=10**6)


def test_an_unmeasurable_filesystem_prunes_rather_than_skipping(prune, tmp_path, monkeypatch):
    """Unknown free space must not be read as plenty.

    Treating a failed statvfs as room to spare would turn a broken probe into a
    cache nothing ever bounds again.
    """

    def explode(_):
        raise OSError("no")

    monkeypatch.setattr(prune.shutil, "disk_usage", explode)
    rep = prune.Reporter()
    assert prune.above_free_floor(tmp_path, ("percent", 20.0), rep) is False
    assert rep.warnings


# ---------------------------------------------------------------------------
# Pruning to a free-space target
# ---------------------------------------------------------------------------

ARTEFACT = 100_000
DISK_TOTAL = 10_000_000
DISK_FREE_AT_START = 50_000


def make_aged_pool(tmp_path, count):
    """A pool of workspaces laid out as cargo leaves them, index 0 the least recently built.

    Each has a build lock in its profile directory, where cargo keeps it.
    """
    pool = tmp_path / "pool"
    leaves = []
    now = time.time()
    for index in range(count):
        leaf = pool / f"{index:02x}" / f"hash{index}"
        profile = leaf / "debug"
        deps = profile / "deps"
        deps.mkdir(parents=True)
        (deps / "artefact.bin").write_bytes(b"\1" * ARTEFACT)
        (profile / ".cargo-build-lock").touch()
        built = now - (count - index) * 3600
        for path in (deps / "artefact.bin", profile / ".cargo-build-lock", deps, profile, leaf):
            os.utime(path, (built, built))
        leaves.append(leaf)
    return pool, leaves


def disk_that_tracks(prune, pool, free=DISK_FREE_AT_START):
    """A statvfs whose free space grows by exactly what has left the pool."""
    start = prune.tree_size(pool)

    def usage(_path):
        return fake_usage(DISK_TOTAL, free + start - prune.tree_size(pool))

    return usage


def workspace_bytes(prune, leaf):
    return prune.tree_size(leaf)


def target_needing(prune, leaves, evictions):
    """A free-space target reached only after the oldest `evictions` workspaces go."""
    one = workspace_bytes(prune, leaves[0])
    return DISK_FREE_AT_START + one * evictions - one // 2


def prune_to_target(prune, pool, rep, target_bytes, *, dry_run=False, max_size=None):
    target = prune.FreeSpaceTarget(pool, target_bytes, dry_run, rep)
    return prune.prune_pool(
        pool, dry_run, rep, max_size=max_size, max_age_days=10**6, target=target
    )


def test_free_target_evicts_oldest_first_until_enough_is_free(prune, tmp_path, monkeypatch):
    pool, leaves = make_aged_pool(tmp_path, 5)
    monkeypatch.setattr(prune.shutil, "disk_usage", disk_that_tracks(prune, pool))
    rep = prune.Reporter()

    prune_to_target(prune, pool, rep, target_needing(prune, leaves, 3))

    assert [leaf.exists() for leaf in leaves] == [False, False, False, True, True]


def test_free_target_evicts_past_a_ceiling_the_pool_is_inside(prune, tmp_path, monkeypatch):
    """The disk is short, not the pool, so the ceiling must not stop the eviction."""
    pool, leaves = make_aged_pool(tmp_path, 4)
    monkeypatch.setattr(prune.shutil, "disk_usage", disk_that_tracks(prune, pool))
    rep = prune.Reporter()

    prune_to_target(prune, pool, rep, target_needing(prune, leaves, 2), max_size=10**12)

    assert [leaf.exists() for leaf in leaves] == [False, False, True, True]


def test_a_disk_slow_to_report_freed_space_does_not_empty_the_pool(prune, tmp_path, monkeypatch):
    """A statvfs that lags the deletes must not drive the loop past the target."""
    pool, leaves = make_aged_pool(tmp_path, 5)
    monkeypatch.setattr(
        prune.shutil, "disk_usage", lambda _: fake_usage(DISK_TOTAL, DISK_FREE_AT_START)
    )
    rep = prune.Reporter()

    prune_to_target(prune, pool, rep, target_needing(prune, leaves, 2))

    assert [leaf.exists() for leaf in leaves] == [False, False, True, True, True]


def test_check_mode_stops_at_the_target_and_deletes_nothing(prune, tmp_path, monkeypatch, capsys):
    pool, leaves = make_aged_pool(tmp_path, 4)
    monkeypatch.setattr(
        prune.shutil, "disk_usage", lambda _: fake_usage(DISK_TOTAL, DISK_FREE_AT_START)
    )
    rep = prune.Reporter()

    prune_to_target(prune, pool, rep, target_needing(prune, leaves, 2), dry_run=True)

    assert all(leaf.exists() for leaf in leaves)
    assert capsys.readouterr().out.count("[check] would drop") == 2


def test_no_target_and_no_ceiling_leaves_a_fresh_pool_alone(prune, tmp_path):
    """The nightly run on a dedicated volume: only the age pass has anything to do."""
    pool, leaves = make_aged_pool(tmp_path, 3)
    rep = prune.Reporter()

    prune.prune_pool(pool, False, rep, max_size=None, max_age_days=14)

    assert all(leaf.exists() for leaf in leaves)
    assert not rep.warnings


def test_the_free_target_defaults_to_the_floor(prune, tmp_path, monkeypatch):
    monkeypatch.setattr(prune.shutil, "disk_usage", lambda _: fake_usage(1000, 100))
    rep = prune.Reporter()
    assert prune.resolve_free_target(None, ("percent", 15.0), tmp_path, rep) == 150


def test_a_free_target_below_the_floor_is_raised_to_it(prune, tmp_path, monkeypatch):
    """Stopping under the floor would leave the disk below it, so the floor wins."""
    monkeypatch.setattr(prune.shutil, "disk_usage", lambda _: fake_usage(1000, 100))
    rep = prune.Reporter()
    assert prune.resolve_free_target(("percent", 10.0), ("percent", 15.0), tmp_path, rep) == 150
    assert rep.warnings


def test_no_floor_and_no_target_means_no_target(prune, tmp_path):
    assert prune.resolve_free_target(None, None, tmp_path, prune.Reporter()) is None


# ---------------------------------------------------------------------------
# Never evict a workspace a build is using
# ---------------------------------------------------------------------------


def hold_lock(path):
    """Take the lock the way a running cargo does, on its own open file description."""
    fd = os.open(path, os.O_RDONLY)
    fcntl.flock(fd, fcntl.LOCK_EX)
    return fd


def test_a_workspace_a_build_holds_is_never_evicted(prune, tmp_path, monkeypatch):
    pool, leaves = make_aged_pool(tmp_path, 4)
    monkeypatch.setattr(prune.shutil, "disk_usage", disk_that_tracks(prune, pool))
    building = hold_lock(leaves[0] / "debug" / ".cargo-build-lock")
    try:
        rep = prune.Reporter()
        prune_to_target(prune, pool, rep, target_needing(prune, leaves, 2))
    finally:
        os.close(building)

    assert [leaf.exists() for leaf in leaves] == [True, False, False, True]
    assert rep.busy == [leaves[0].name]


def test_a_held_workspace_survives_the_ceiling_pass_too(prune, tmp_path):
    pool, leaves = make_aged_pool(tmp_path, 2)
    building = hold_lock(leaves[0] / "debug" / ".cargo-build-lock")
    try:
        rep = prune.Reporter()
        prune.prune_pool(pool, False, rep, max_size=1, max_age_days=10**6)
    finally:
        os.close(building)

    assert leaves[0].exists()
    assert not leaves[1].exists()


def test_the_lock_is_held_through_the_delete(prune, tmp_path, monkeypatch):
    """A build that starts mid-delete must wait, not write into a tree being removed."""
    pool, leaves = make_aged_pool(tmp_path, 1)
    lock = leaves[0] / "debug" / ".cargo-build-lock"
    real_rmtree = prune.shutil.rmtree
    seen = []

    def rmtree_while_probing(path):
        fd = os.open(lock, os.O_RDONLY)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            seen.append("free")
        except BlockingIOError:
            seen.append("held")
        finally:
            os.close(fd)
        real_rmtree(path)

    monkeypatch.setattr(prune.shutil, "rmtree", rmtree_while_probing)
    prune.prune_pool(pool, False, prune.Reporter(), max_size=1, max_age_days=10**6)

    assert seen == ["held"]
    assert not leaves[0].exists()


def test_locks_are_found_at_every_depth_cargo_writes_them(prune, tmp_path):
    leaf = tmp_path / "leaf"
    expected = {
        leaf / "debug" / ".cargo-build-lock",
        leaf / "x86_64-unknown-linux-gnu" / "release" / ".cargo-lock",
        leaf / "llvm-cov-target" / "x86_64-unknown-linux-gnu" / "debug" / ".cargo-build-lock",
    }
    for lock in expected:
        lock.parent.mkdir(parents=True, exist_ok=True)
        lock.touch()
    # Below a profile directory is cargo's own output, which is not searched.
    (leaf / "debug" / "deps").mkdir()
    (leaf / "debug" / "deps" / ".cargo-lock").touch()

    assert set(prune.build_locks(leaf)) == expected


def test_a_lock_held_deep_in_the_tree_protects_the_workspace(prune, tmp_path):
    leaf = tmp_path / "leaf"
    shallow = leaf / "debug" / ".cargo-build-lock"
    deep = leaf / "llvm-cov-target" / "x86_64-unknown-linux-gnu" / "debug" / ".cargo-build-lock"
    for lock in (shallow, deep):
        lock.parent.mkdir(parents=True)
        lock.touch()
    building = hold_lock(deep)
    try:
        assert prune.take_build_locks(leaf) is None
        # The lock already taken on the way must have been let go again.
        probe = os.open(shallow, os.O_RDONLY)
        try:
            fcntl.flock(probe, fcntl.LOCK_EX | fcntl.LOCK_NB)
        finally:
            os.close(probe)
    finally:
        os.close(building)


def test_a_workspace_with_no_lock_file_is_evictable(prune, tmp_path):
    """A pool on NFS carries no cargo lock at all, and must still be bounded."""
    leaf = tmp_path / "leaf"
    (leaf / "debug").mkdir(parents=True)
    held = prune.take_build_locks(leaf)
    assert held == []


# ---------------------------------------------------------------------------
# `auto` on a filesystem of its own
# ---------------------------------------------------------------------------


def stat_on_another_device(monkeypatch, prune, moved):
    """Report `moved` as sitting on a different device, as a dedicated volume does."""
    real_stat = os.stat

    def stat(path, *args, **kwargs):
        result = real_stat(path, *args, **kwargs)
        if isinstance(path, (str, os.PathLike)) and Path(path) == moved:
            fields = list(result[:10])
            fields[2] = result.st_dev + 1
            return os.stat_result(fields)
        return result

    monkeypatch.setattr(prune.os, "stat", stat)


def test_same_filesystem_reads_the_device(prune, tmp_path):
    (tmp_path / "a").mkdir()
    assert prune.same_filesystem(tmp_path / "a", tmp_path) is True


@pytest.mark.skipif(not Path("/proc/self").exists(), reason="needs procfs")
def test_same_filesystem_tells_two_real_filesystems_apart(prune, tmp_path):
    assert prune.same_filesystem(Path("/proc"), tmp_path) is False


def test_same_filesystem_is_unknown_for_a_missing_path(prune, tmp_path):
    assert prune.same_filesystem(tmp_path / "absent", tmp_path) is None


def test_auto_means_no_ceiling_when_the_pool_has_its_own_filesystem(prune, tmp_path, monkeypatch):
    home = tmp_path / "home"
    pool = tmp_path / "pool"
    home.mkdir()
    pool.mkdir()
    monkeypatch.setenv("HOME", str(home))
    stat_on_another_device(monkeypatch, prune, pool)

    assert prune.resolve_max_size("auto", pool, prune.Reporter()) is None


def test_auto_keeps_the_ceiling_on_the_home_filesystem(prune, tmp_path, monkeypatch):
    home = tmp_path / "home"
    pool = tmp_path / "pool"
    home.mkdir()
    pool.mkdir()
    monkeypatch.setenv("HOME", str(home))

    assert prune.resolve_max_size("auto", pool, prune.Reporter()) >= prune.parse_size(
        prune.AUTO_FLOOR
    )


def test_an_unreadable_home_keeps_the_ceiling(prune, tmp_path, monkeypatch):
    """Not knowing where home is must not be read as a dedicated volume."""
    monkeypatch.setenv("HOME", str(tmp_path / "absent"))
    assert prune.resolve_max_size("auto", tmp_path, prune.Reporter()) is not None


def test_an_explicit_size_still_applies_on_a_dedicated_volume(prune, tmp_path, monkeypatch):
    home = tmp_path / "home"
    pool = tmp_path / "pool"
    home.mkdir()
    pool.mkdir()
    monkeypatch.setenv("HOME", str(home))
    stat_on_another_device(monkeypatch, prune, pool)

    size = prune.parse_size("64G")
    assert prune.resolve_max_size(size, pool, prune.Reporter()) == size


# ---------------------------------------------------------------------------
# Docker fallback, against a stand-in docker on PATH
# ---------------------------------------------------------------------------

DOCKER_STUB = """#!/bin/sh
echo "$*" >> "{log}"
case "$1" in
  info)
    {info}
    ;;
  *)
    {prune}
    ;;
esac
"""
PRUNE_OK = "echo 'Total reclaimed space: 1.5GB'"


def install_docker(tmp_path, monkeypatch, *, info, prune=PRUNE_OK):
    """Put a stand-in docker alone on PATH, so no real daemon on the runner is ever reached."""
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir(exist_ok=True)
    log = tmp_path / "docker.log"
    stub = bin_dir / "docker"
    stub.write_text(DOCKER_STUB.format(log=log, info=info, prune=prune), encoding="utf-8")
    stub.chmod(0o755)
    monkeypatch.setenv("PATH", str(bin_dir))
    return log


def docker_calls(log):
    return log.read_text(encoding="utf-8").splitlines() if log.exists() else []


def prune_calls(log):
    return [call for call in docker_calls(log) if "prune" in call]


def short_until(log, prunes_needed):
    """A disk that reaches the target once Docker has run this many prunes."""

    def usage(_path):
        done = len(prune_calls(log))
        return fake_usage(DISK_TOTAL, DISK_TOTAL if done >= prunes_needed else 0)

    return usage


def docker_target(prune, pool, rep, *, dry_run=False):
    return prune.FreeSpaceTarget(pool, DISK_TOTAL // 2, dry_run, rep)


def test_docker_fallback_does_nothing_without_docker(prune, tmp_path, monkeypatch):
    empty = tmp_path / "empty-bin"
    empty.mkdir()
    monkeypatch.setenv("PATH", str(empty))
    monkeypatch.setattr(prune.shutil, "disk_usage", lambda _: fake_usage(DISK_TOTAL, 0))
    rep = prune.Reporter()

    prune.docker_fallback(tmp_path, docker_target(prune, tmp_path, rep), False, rep)

    assert not rep.warnings


def test_docker_fallback_leaves_a_daemon_it_cannot_reach_alone(prune, tmp_path, monkeypatch):
    """No docker group means no access, and the fix is never sudo."""
    log = install_docker(
        tmp_path,
        monkeypatch,
        info=(
            "echo 'permission denied while trying to connect to the Docker daemon socket' >&2; "
            "exit 1"
        ),
    )
    monkeypatch.setattr(prune.shutil, "disk_usage", lambda _: fake_usage(DISK_TOTAL, 0))
    rep = prune.Reporter()

    prune.docker_fallback(tmp_path, docker_target(prune, tmp_path, rep), False, rep)

    assert prune_calls(log) == []
    assert docker_calls(log) == ["info --format {{.DockerRootDir}}"]


def test_docker_fallback_skips_a_data_root_on_another_filesystem(prune, tmp_path, monkeypatch):
    root = tmp_path / "docker-root"
    root.mkdir()
    log = install_docker(tmp_path, monkeypatch, info=f"echo '{root}'")
    stat_on_another_device(monkeypatch, prune, root)
    monkeypatch.setattr(prune.shutil, "disk_usage", lambda _: fake_usage(DISK_TOTAL, 0))
    rep = prune.Reporter()

    prune.docker_fallback(tmp_path, docker_target(prune, tmp_path, rep), False, rep)

    assert prune_calls(log) == []


def test_docker_fallback_skips_a_data_root_inside_a_vm(prune, tmp_path, monkeypatch):
    """Docker Desktop and colima report a path that exists only inside their VM."""
    log = install_docker(tmp_path, monkeypatch, info=f"echo '{tmp_path / 'not-on-this-host'}'")
    monkeypatch.setattr(prune.shutil, "disk_usage", lambda _: fake_usage(DISK_TOTAL, 0))
    rep = prune.Reporter()

    prune.docker_fallback(tmp_path, docker_target(prune, tmp_path, rep), False, rep)

    assert prune_calls(log) == []


def test_docker_fallback_stops_once_the_build_cache_is_enough(prune, tmp_path, monkeypatch):
    root = tmp_path / "docker-root"
    root.mkdir()
    log = install_docker(tmp_path, monkeypatch, info=f"echo '{root}'")
    monkeypatch.setattr(prune.shutil, "disk_usage", short_until(log, 1))
    rep = prune.Reporter()

    prune.docker_fallback(tmp_path, docker_target(prune, tmp_path, rep), False, rep)

    assert prune_calls(log) == ["builder prune -f --filter until=72h"]


def test_docker_fallback_moves_on_to_images_when_still_short(prune, tmp_path, monkeypatch):
    root = tmp_path / "docker-root"
    root.mkdir()
    log = install_docker(tmp_path, monkeypatch, info=f"echo '{root}'")
    monkeypatch.setattr(prune.shutil, "disk_usage", short_until(log, 2))
    rep = prune.Reporter()

    prune.docker_fallback(tmp_path, docker_target(prune, tmp_path, rep), False, rep)

    assert prune_calls(log) == [
        "builder prune -f --filter until=72h",
        "image prune -af --filter until=168h",
    ]
    assert not rep.warnings


def test_docker_fallback_warns_and_carries_on_when_a_prune_fails(prune, tmp_path, monkeypatch):
    root = tmp_path / "docker-root"
    root.mkdir()
    log = install_docker(
        tmp_path, monkeypatch, info=f"echo '{root}'", prune="echo 'daemon busy' >&2; exit 1"
    )
    monkeypatch.setattr(prune.shutil, "disk_usage", lambda _: fake_usage(DISK_TOTAL, 0))
    rep = prune.Reporter()

    prune.docker_fallback(tmp_path, docker_target(prune, tmp_path, rep), False, rep)

    assert len(prune_calls(log)) == 2
    assert len(rep.warnings) == 2


def test_docker_fallback_in_check_mode_runs_no_prune(prune, tmp_path, monkeypatch, capsys):
    root = tmp_path / "docker-root"
    root.mkdir()
    log = install_docker(tmp_path, monkeypatch, info=f"echo '{root}'")
    monkeypatch.setattr(prune.shutil, "disk_usage", lambda _: fake_usage(DISK_TOTAL, 0))
    rep = prune.Reporter()

    prune.docker_fallback(tmp_path, docker_target(prune, tmp_path, rep, dry_run=True), True, rep)

    out = capsys.readouterr().out
    assert prune_calls(log) == []
    assert "would run: docker builder prune -f --filter until=72h" in out
    assert "then, if still short, would run: docker image prune -af --filter until=168h" in out


# ---------------------------------------------------------------------------
# The whole run, as the guard's unit invokes it
# ---------------------------------------------------------------------------


def run_main(prune, monkeypatch, argv):
    monkeypatch.setattr(sys, "argv", ["hyperi-rust-cache-prune", *argv])
    return prune.main()


def hermetic(tmp_path, monkeypatch):
    """No real home, cargo config or sccache reaches the run."""
    home = tmp_path / "home"
    home.mkdir()
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.setenv("CARGO_HOME", str(tmp_path / "no-cargo"))


def test_guard_run_prunes_to_the_target_and_leaves_docker_alone(prune, tmp_path, monkeypatch):
    pool, leaves = make_aged_pool(tmp_path, 5)
    hermetic(tmp_path, monkeypatch)
    log = install_docker(tmp_path, monkeypatch, info=f"echo '{tmp_path}'")
    one = workspace_bytes(prune, leaves[0])
    total = 20 * one
    # One workspace's worth free, a floor of two and a target of four, so three must go.
    start = prune.tree_size(pool)
    monkeypatch.setattr(
        prune.shutil,
        "disk_usage",
        lambda _: fake_usage(total, one + start - prune.tree_size(pool)),
    )

    code = run_main(
        prune,
        monkeypatch,
        ["--yes", "--pool", str(pool), "--if-free-below", "10%", "--free-target", "20%"],
    )

    assert code == 0
    assert [leaf.exists() for leaf in leaves] == [False, False, False, True, True]
    assert docker_calls(log) == []


def test_no_docker_switches_the_fallback_off(prune, tmp_path, monkeypatch, capsys):
    pool, leaves = make_aged_pool(tmp_path, 2)
    hermetic(tmp_path, monkeypatch)
    log = install_docker(tmp_path, monkeypatch, info=f"echo '{tmp_path}'")
    monkeypatch.setattr(prune.shutil, "disk_usage", lambda _: fake_usage(DISK_TOTAL, 0))

    code = run_main(
        prune,
        monkeypatch,
        [
            "--yes",
            "--pool",
            str(pool),
            "--if-free-below",
            "10%",
            "--free-target",
            "50%",
            "--no-docker",
        ],
    )

    assert code == 0
    assert not any(leaf.exists() for leaf in leaves)
    assert docker_calls(log) == []
    assert "still below the" in capsys.readouterr().out


def test_guard_run_with_room_to_spare_never_walks_or_asks_docker(prune, tmp_path, monkeypatch):
    pool, leaves = make_aged_pool(tmp_path, 2)
    hermetic(tmp_path, monkeypatch)
    log = install_docker(tmp_path, monkeypatch, info=f"echo '{tmp_path}'")
    monkeypatch.setattr(prune.shutil, "disk_usage", lambda _: fake_usage(DISK_TOTAL, DISK_TOTAL))

    def no_walk(_pool):
        raise AssertionError("the pool was walked with the disk above its floor")

    monkeypatch.setattr(prune, "find_workspaces", no_walk)

    assert (
        run_main(prune, monkeypatch, ["--yes", "--pool", str(pool), "--if-free-below", "15%"]) == 0
    )
    assert all(leaf.exists() for leaf in leaves)
    assert docker_calls(log) == []
