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
absolute path. It also writes the cache caps described below.

sccache caches compiled crates, so a rebuild after `cargo clean`, a branch
switch or a dependency bump reuses work.

mold is still worth configuring, but the margin is smaller than it was: rustc
has used rust-lld by default on `x86_64-unknown-linux-gnu` since Rust 1.90, so
the config now overrides lld rather than GNU ld. mold remains ahead of lld on
upstream figures. `wild` is roughly twice mold again for iterative development,
but it is Linux-x86-64 only with no LTO support, so it is a candidate rather
than a default. Ubuntu, Debian, Fedora and macOS.

Note sccache does not cache incremental compilation, which the `dev` profile
enables by default; it passes those through. The wins show up on `--release`
and on clean rebuilds.

## Keeping the caches bounded

Three caches, three mechanisms, and only one of them is ours. Apply the lot
without a full toolchain converge with `--tags rust-cache`.

**The cargo global cache bounds itself.** Registry indexes and downloaded
sources are tracked by last-use; cargo deletes network-fetched files unused for
3 months and regenerable files unused for 1 month, checking daily. The role sets
nothing here, deliberately -- a `[cache]` key in the config would only restate
the default and would then have to be maintained against it.

**sccache and ccache evict LRU against a byte ceiling.** Both read it from the
environment, so `hyperi-rust-setup` writes it: `/etc/profile.d/hyperi-rust-cache.sh`
on Linux, a marked block in `~/.zshenv` on macOS. `.zshenv` rather than
`.zshrc` because zsh reads `.zshrc` only for interactive shells, and a build
launched from a script would miss a cap set there.

Each cache's LOCATION is left at its own default. Pointing them somewhere new
on a box that already has a populated cache orphans it rather than capping it.

`SCCACHE_BASEDIRS` is set alongside the caps. sccache keys on absolute paths, so
the same source built under a different root misses; the listed roots are
stripped before hashing. It defaults to the user's home, which covers a container
or CI runner that mounts the tree somewhere else. It does NOT unify sibling
checkouts of one repo -- those differ by directory name rather than by root, so
each would have to be listed explicitly.

Because the sccache server reads its ceiling once at startup and holds it,
changing the cap also stops the running server. The next build starts a fresh
one at the new value; nothing on disk is touched.

A server left running across an sccache upgrade is the failure to know about:
the old daemon answers the new client, the handshake fails, and compilation
silently stops being cached while `sccache` is still installed and configured.
`hyperi-rust-cache-prune` reports it rather than showing an empty ceiling, and
`sccache --stop-server` clears it.

## Bounding the build-artefact pool

**Build artefacts have no upstream cap at all.** Cargo does not track them
(rust-lang/cargo#13136), so nothing reclaims a `target/` ever, and one per repo
across a tree full of them is what actually fills a disk.

So `build.build-dir` points every project at a single pool
(`~/.cache/hyperi-rust-build`, or `~/Library/Caches` on macOS), keyed by
`{workspace-path-hash}` so two checkouts of one project cannot clobber each
other. Only INTERMEDIATES move. Each project's `target/` keeps its final
binaries, so `cargo run`, IDEs and anything globbing for a built artefact are
unaffected.

`hyperi-rust-cache-prune` then bounds that pool on a schedule -- a systemd timer
on Linux, a launchd agent on macOS, daily and at idle IO priority. It drops
workspaces not built for `rust_cache_max_age_days`, then evicts
least-recently-built ones until the pool is under `rust_cache_build_dir_max`.
It touches no project `target/`, and reports the self-capping caches without
pruning them.

The pool ceiling defaults to `auto`: a sixth of the filesystem's total size,
floor 40G. Total, not free -- free space shrinks as the pool grows, so a ceiling
derived from it chases itself downward. That puts a 692G build box at 115G and a
256G laptop at the floor, so one default suits both. Set
`rust_cache_build_dir_max` to an explicit size to override it.

**The ceiling binds while the tool runs, not between runs.** A pool that grows
faster than the schedule spends the gap above it, so the prune runs daily and an
hourly guard backs it up -- one statvfs while the disk has room, a prune to the
same ceiling once free space falls below `rust_cache_prune_free_floor` (20%).

A guard run that finds the pool already under its ceiling stops and says so. The
space went somewhere the prune does not own, and naming that is more use than
evicting artefacts that were not the cause. Set
`rust_cache_prune_guard_enabled: false` to drop the guard, or
`rust_cache_prune_schedule_weekday` to go back to weekly.

## Which sccache builds actually use

**sccache comes from upstream's release, not the distro.** Ubuntu ships 0.13.0
against an upstream on 0.17.x, and a wrapper four versions behind is what a
developer meets when a hand-run `sccache --show-stats` fails against the server
their build started. The setup tool fetches the latest `mozilla/sccache`
release to `/usr/local/bin/sccache` on every run, checked against the `.sha256`
published beside each asset, and removes the distro package so only one
packaged copy answers. Re-running is a no-op once the installed version matches
the latest tag, so install and upgrade are the same call. macOS keeps brew,
which already tracks upstream.

This does not reopen the objection in the SSoT note below: crates.io stays out
of the global `rustc-wrapper` path. The binary is the project's own release
artefact, digest-checked, not an unpinned `cargo install`.

**A cargo-installed sccache still shadows it.** `~/.cargo/bin` precedes
`/usr/local/bin` on PATH, so anything typed by hand reaches the cargo copy
while builds keep using the absolute path in the cargo config. That split is
what makes a failed `--show-stats` look like a dead cache when every build is
being cached normally. The prune reports which binary builds use and queries
that one; the setup tool prints the `cargo uninstall` line. Removing a binary a
developer installed is their call.

`build.build-dir` is stable from Rust 1.91. On an older toolchain the setup tool
says so and leaves the per-project layout alone, so the default stays safe.

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

**Move or symlink `target/` onto another disk.** The old script symlinked each
project's `target/` onto a cache disk. That is where both its data-loss bugs
lived, and it assumed one particular machine's layout.

`build.build-dir` is the supported route and is what the role uses now: new
builds simply write their intermediates elsewhere. Nothing is relocated, no
symlink is created, and a box on a pre-1.91 toolchain just keeps the default
layout. Per-project `build.target-dir` remains available for anyone who wants
the finals moved too.

**Set `build.jobs`.** Cargo already defaults to the logical CPU count. The old
script hardcoded `8`, which is wrong on a 4-core VM and wasteful on a 32-core
workstation.

**Install mold on macOS.** mold is an ELF linker with no Mach-O backend, so it
cannot link anything built natively on a Mac.

**Remove a cargo-installed sccache that shadows the packaged one.** The tool
detects the shadow and prints the `cargo uninstall` line. Removing a binary a
developer installed themselves is their call.

## Taking over an existing config

The tool manages exactly two tables, `[build]` and `[target]`. Every other table
in an existing `$CARGO_HOME/config.toml` is CARRIED ACROSS verbatim -- a private
registry, an alias table, a profile override. Dropping them was data loss:
nothing else on the box restores a registry definition.

Carrying happens as raw text rather than parse-and-reserialise, because a Cargo
config holds comments the parser discards and the standard library has no TOML
writer to round-trip them with. The rendered result is parsed before it is
written, and a config that would not parse is refused with a warning instead --
an invalid `config.toml` breaks every cargo command on the machine.

If the file was not written by us it is still backed up to
`config.toml.pre-hyperi-<timestamp>` first, so a takeover is always recoverable.

Neither the tool nor `--check` echoes the config. It can now contain carried-over
sections, a Cargo config can hold registry tokens inline, and this output ends up
in Ansible and CI logs.
