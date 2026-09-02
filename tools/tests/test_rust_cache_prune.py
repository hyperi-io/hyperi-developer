"""Tests for hyperi-rust-cache-prune's config reading and size resolution.

The script ships as an extensionless executable in an Ansible role's files/,
so it is loaded by path rather than imported by name.
"""

import importlib.util
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


def test_auto_size_is_a_share_of_the_disk_with_a_floor(prune, tmp_path):
    """`auto` derives from the filesystem total, and never drops below the floor."""
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
    with pytest.raises(Exception):
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
