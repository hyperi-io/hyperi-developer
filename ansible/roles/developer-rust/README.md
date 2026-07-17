# developer-rust

Rust toolchain (rustup + components), cargo tools, and a build environment
tuned to make the edit-build-test loop bearable.

## hyperi-rust-setup

The build-acceleration half lives in `files/hyperi-rust-setup`, a standalone
script installed to `/usr/local/bin`. Ansible calls it with `--yes`; a
developer can run it by hand on any machine, including ones we do not manage:

```bash
hyperi-rust-setup --check    # show what would change, change nothing
hyperi-rust-setup            # ask first
hyperi-rust-setup --yes      # no prompt
```

It installs sccache, mold and clang from the system package manager, then
writes `$CARGO_HOME/config.toml` naming only the tools it actually found, by
absolute path.

sccache caches compiled crates, so a rebuild after `cargo clean`, a branch
switch or a dependency bump reuses work. mold links several times faster than
the default linker, which matters because linking dominates an incremental
build. Ubuntu, Debian, Fedora and macOS.

Note sccache does not cache incremental compilation, which the `dev` profile
enables by default; it passes those through. The wins show up on `--release`
and on clean rebuilds.

## SSoT

This role is the source of truth for the global Cargo config. It was
`hyperi-ci`'s `scripts/setup-rust-dev.py` until 2026-07-17.

That script is not what got ported. A review found it could not be adopted:

- It moved `target/` directories across filesystems with `os.rename`, which
  raises `EXDEV` and has no copy fallback. Proven on a real host where
  `/projects` and `/cache` are separate disks. The move was also lossy on a
  re-run, deleting source files it had skipped rather than copied.
- It wrote a config naming `sccache` and `clang` whether or not those installed
  (and it never installed clang at all), so a failed install left every
  `cargo build` on the box broken while the script exited 0.
- It edited TOML line-by-line. `rustflags = []` came out as `rustflags = [, ...]`.
- It installed sccache with an unpinned `cargo install` and wired it in as a
  global `rustc-wrapper`, so one bad crates.io release would intercept every
  rustc invocation on every workstation.

The rewrite installs from signed distro repos, verifies each tool runs before
naming it, resolves absolute paths (a cargo-installed binary earlier on PATH
would otherwise silently become the wrapper), and writes the config atomically.

## What it deliberately does not do

**Move `target/` onto another disk.** The old script symlinked each project's
`target/` onto a cache disk. That is where both its data-loss bugs lived, and
it assumed one particular machine's layout. Cargo supports `build.target-dir`
per project, which is the supported route and needs no symlinks.

**Set `build.jobs`.** Cargo already defaults to the logical CPU count. The old
script hardcoded `8`, which is wrong on a 4-core VM and wasteful on a 32-core
workstation.

**Install mold on macOS.** mold is an ELF linker with no Mach-O backend, so it
cannot link anything built natively on a Mac.

**Remove a cargo-installed sccache that shadows the packaged one.** The tool
detects the shadow and prints the `cargo uninstall` line. Removing a binary a
developer installed themselves is their call.

## Taking over an existing config

If `$CARGO_HOME/config.toml` exists and we did not write it, the tool backs it
up to `config.toml.pre-hyperi-<timestamp>` and names any sections it does not
manage so nothing disappears quietly. It does not echo the file: a Cargo config
can hold registry tokens inline, and this output ends up in Ansible and CI logs.
