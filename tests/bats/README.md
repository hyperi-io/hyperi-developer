# install.sh bats tests

These tests exercise `install.sh` argument parsing for the `--profile`
interface without running Ansible. They short-circuit `install.sh` via the
`DFE_PROFILE_TEST=1` environment variable: when set, `install.sh` resolves
profiles/tags, prints `RESOLVED_TAGS=...`, and exits 0 before touching the
system.

## Install bats

- Ubuntu / Debian: `sudo apt-get install -y bats`
- Fedora: `sudo dnf install -y bats`
- macOS (Homebrew): `brew install bats-core`

## Run

From the repo root:

```bash
bats tests/bats/install_profile.bats
```

Or run everything under `tests/bats/`:

```bash
bats tests/bats/
```

## Layout

- `helpers.bash` - shared `profile_parse` helper; sourced by `load helpers`.
- `install_profile.bats` - argument parser tests for `--profile`,
  deprecation aliases (`--core`, `--all`), implicit rules, and error
  handling.
