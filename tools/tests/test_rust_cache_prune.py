"""Tests for hyperi-rust-cache-prune's config reading and size resolution.

The script ships as an extensionless executable in an Ansible role's files/,
so it is loaded by path rather than imported by name.
"""

import importlib.util
from pathlib import Path

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
