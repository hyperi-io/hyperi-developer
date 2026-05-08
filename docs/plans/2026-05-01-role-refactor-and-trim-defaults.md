# Role Refactor + Trim Defaults — Implementation Plan

**Status:** Design phase. Open decisions below need a decision before implementation.

**Repo positioning** (set in repo description + README):
> *Standardised modern auto-updating developer environment with opt-in HyperI-specific sections.*

The implementation must actually deliver on that — anyone (non-HyperI, contractor, external) can use the generic base without having HyperI-specific tooling, VPN setup, auto-update policies, or workflow opinions imposed on them. The HyperI bits are explicitly opt-in.

**Goal:** Restructure dfe-developer Ansible roles around three orthogonal axes:

1. **Audience** — `developer` for anyone, `infrastructure` for IaC people, `corporate` for org-specific
2. **Specialisation** — `developer-<lang>` so a Python dev doesn't get a Cargo environment
3. **CLI vs GUI** — every role split into `<role>` (CLI) and `<role>-gui` where GUI tools exist

Plus: remove tools that don't belong in the auto-build (e.g. Docker Desktop).

**HyperI-specific items confirmed for `corporate` / `corporate-gui` (not generic):**
- VPN (NetBird CLI, OpenVPN client) — both in `corporate`
- Auto-updates configuration — moved out of always-run, into `corporate`
- Bash history auto-commit — moved out of always-run, into `corporate`
- Slack, Linear, JFrog, Bitwarden GUI, OnlyOffice, Claude Code — `corporate-gui` / `corporate`
- Browser privacy policies — **deleted entirely** (not migrated)
- Nemo file manager swap, GNOME extensions, desktop cleanup — `corporate-gui`

**Trigger:** Conversation 2026-05-01. Original proposal (themed groups within a single `developer` role) was rejected in favour of multi-role separation by audience + specialisation + GUI/CLI axis.

---

## What runs today (for reference)

### `developer,base` (no-flag default → in practice runs everything because empty `--tags` skips filtering)

Desktop / GUI base, heavy tools (Docker, VS Code, Chrome, Brave, OnlyOffice, Ghostty, Vector, HashiCorp, AWS CLI, kubectl, Minikube), system config (AppArmor, mirrors, auto-updates, browser policies, history, locale, utilities, Flatpak), UV.

### `core,advanced` (`--core` / `--all`)

`act`, Azure CLI, Bitwarden, build-essentials, Claude Code, gcloud, Gitleaks, JFrog CLI, Linear CLI, NetBird, Node.js, OpenVPN, Rust, Slack, etc.

> **Drift bug:** `wallpaper.yml` exists in **both** `developer/tasks/` and `developer_core/tasks/`. Pick one.

---

## Proposed structure (new)

### Role hierarchy

| Role | Audience / scope | CLI variant | GUI variant |
|---|---|---|---|
| `developer` | **Anyone** — generic dev base, lightweight, low disruption to existing env | git, shell config, core CLI utilities (ripgrep, fd, fzf, htop), build basics (gcc/make/clang), Flatpak runtime, latest-version repos wired up | VS Code, Ghostty + JetBrains Mono — *that's it* on the GUI side |
| `developer-rust` | Rust dev only | rustup, sccache, mold, cargo-sweep | (none) |
| `developer-python` | Python dev only | uv, system Python deps | (none) |
| `developer-node` | Node dev only | Node.js, pnpm | (none) |
| `developer-go` | Go dev only | go toolchain, gopls, dlv | (none) |
| `developer-c` | C/C++ dev only | build-essential / @c-development / Xcode CLT, valgrind, gdb | (none) |
| `infrastructure` | IaC operators / SREs — generic, not org-specific | terraform, kubectl, helm, k9s (TUI), aws-cli, azure-cli, gcloud, hashicorp tools, ansible, packer | Lens (K8s GUI), DBeaver |
| `corporate` | HyperI-specific stack | JFrog CLI, Linear CLI, NetBird CLI, Bitwarden CLI, Claude Code, gitleaks, act, OpenVPN, telemetry-config | Slack, Bitwarden GUI, OnlyOffice |
| `rdp` | Targeted deployment (remote-desktop hosts) | (no CLI variant — single role) | n/a — already its own thing |
| `vm_optimizer` | Targeted deployment (VMs only) | n/a | n/a |
| (system-only) | Always runs | apparmor-userns fix, OS repo mirrors, auto-updates, locale, region, history, fastestmirror | (n/a) |

### What *moves out* of the auto-build (#5)

- **Docker Desktop on macOS** — gone. Replace with `docker` CLI only via brew, or opt-in `colima` for the daemon. The user runs whatever container runtime they want.
- **Browser privacy policies** — too opinionated for a generic `developer` role. Move to `corporate` (it's an org policy enforcement).
- **Brave** — out of `developer-gui`. Available via opt-in tag `--tags brave` if anyone really wants it; not in the default kit.
- **Wallpaper, avatar** — cosmetic. Single opt-in tag `--tags cosmetic`.
- **OnlyOffice** — out of generic `developer-gui`, into `corporate-gui` (this is HyperI's office suite choice; not everyone wants 1.5GB of office suite).
- **Vector** — niche tool, out of generic. Into `infrastructure` (it's a data-pipeline tool, not a developer tool).

### What *stays* in always-run (system-only, no role tag)

- AppArmor user-namespace fix (Linux desktop apps need this — universal)
- OS repo mirror config / `fastestmirror` (performance, not a feature)
- Auto-updates (`unattended-upgrades` / `dnf-automatic`) — security baseline
- Locale + region (`--region au` etc.)
- bash history auto-commit

These run unconditionally as part of system bootstrap; they don't belong to any specific persona.

### macOS modern bash

New role/task: `bash-modern` (macOS only).
- `brew install bash` (lands at `/opt/homebrew/bin/bash` on Apple Silicon, `/usr/local/bin/bash` on Intel)
- Add path to `/etc/shells` if missing
- Do **NOT** `chsh` automatically — that's a deliberate user choice
- Apple's `/bin/bash` 3.2 is untouched; scripts using `#!/bin/bash` keep working

Default: opt-in (additive, but PATH-first behaviour change is non-trivial).

### Default behaviour fix

Today: no flag → empty `--tags` → Ansible runs everything.

Proposed: no flag → `--tags developer` → just the lightweight CLI dev base. Anyone wanting GUI does `--tags developer,developer-gui`. Anyone wanting languages adds `--tags developer-rust`, etc.

`--all` keeps current "everything" semantics. `--core` shortcut is renamed (see decision below).

---

## Implementation sequence

When work resumes:

### Stage 1 — Plumbing

1. Add new top-level roles directories: `developer-rust`, `developer-python`, `developer-node`, `developer-go`, `developer-c`, `infrastructure`, `corporate`. (Plus `-gui` companions where applicable per the table above.)
2. Update `playbooks/main.yml` with the new role list and tag mapping.
3. Update `install.sh` with the new tag taxonomy + helper flags (`--all`, `--minimal`, language shortcuts).
4. Fix the no-flag bug — default `ANSIBLE_TAGS="--tags developer"`.

### Stage 2 — Migrate tasks

5. Move existing tasks from `developer/tasks/` and `developer_core/tasks/` into the new roles. Map (current → new):
   - `git`, `shell_config`, `utilities`, `apparmor_userns` → `developer` (CLI)
   - `vscode`, `ghostty` → `developer-gui`
   - `rust` → `developer-rust`
   - `uv` → `developer-python`
   - `nodejs` → `developer-node`
   - `c_tools` → `developer-c`
   - `cloud` (HashiCorp + AWS), `k8s` (kubectl + minikube), `azure`, `gcloud`, `data_tools` (Vector) → `infrastructure`
   - (no Lens/DBeaver yet — add as new tasks in `infrastructure-gui`)
   - `jfrog`, `linear`, `netbird`, `bitwarden` (CLI), `claude`, `gitleaks`, `act`, `openvpn`, `telemetry` → `corporate`
   - `slack`, `bitwarden` (GUI), `onlyoffice`, `office` → `corporate-gui`
   - `desktop`, `gnome`, `nemo`, `desktop_cleanup`, `region`, `repository`, `security`, `browser_policies` → system-only (always-run, no tag)
   - `chrome`, `brave`, `wallpaper`, `avatar` → opt-in cosmetic tags
   - `docker.yml` → split: keep Linux Docker Engine in `developer` (or `infrastructure`?); remove Docker Desktop branch on macOS

### Stage 3 — Add new

6. New `bash-modern` role (macOS only).
7. New `infrastructure-gui/lens.yml`, `infrastructure-gui/dbeaver.yml` (or skip if not wanted).
8. De-duplicate `wallpaper.yml`.

### Stage 4 — Test

9. Lint: `ansible-lint` zero warnings on every new role.
10. Test against Ubuntu 26.04 (resolute) — see hyperi-infra plan: build VMID 9043 desktop with this branch passed via `--branch <new-feature-branch>` to the rebuild pipeline.
11. Update `README.md` with the new tag taxonomy and persona-based examples.

---

## What's already done in this branch (`feat/ghostty-update-and-trim-defaults`)

- Ghostty theme line fix: `Builtin Solarized` → `iTerm2 Solarized` (Ghostty renamed/removed Builtin variants in a recent release).
- This plan doc + TODO entry pointing to it.

That's it. Everything else above is design pending decisions.

---

## Open decisions checklist

- [ ] **Languages**: which `developer-<lang>` roles to create? Recommended set: `rust, python, node, go, c`. Drop any that aren't needed?
- [ ] **`-gui` variants**: which roles get a `-gui` companion? Recommended:
  - `developer-gui` (VS Code, Ghostty)
  - `infrastructure-gui` (Lens, DBeaver) — or skip if you don't want them
  - `corporate-gui` (Slack, Bitwarden GUI, OnlyOffice)
  - Language roles: no GUI variants (no universal language-specific GUIs worth bundling)
- [ ] **Where Docker lives** on Linux: `developer` (most devs use it) or `infrastructure` (it's container infra)? Recommended: `developer` (Linux Docker Engine is fine), `infrastructure` (separate `colima` opt-in for macOS)
- [ ] **macOS Docker default**: drop entirely (BYO container runtime), or default to `colima` (CLI-only)? Recommended: drop entirely, document `colima` / `orbstack` / `podman` as alternatives.
- [ ] **Always-run system tasks**: are `apparmor-userns`, `repository` (mirrors), `security` (auto-updates), `region`, `shell-config` correct as always-run? Or should some be opt-out?
- [ ] **`bash-modern`** default: opt-in (recommended) or default-on for macOS?
- [ ] **`--core` shortcut rename**: `--full`? `--workstation`? `--everything`? Recommended: drop the `--core` flag entirely; if you want everything use `--all`.
- [ ] **Wallpaper, avatar, chrome, brave, onlyoffice (default OnlyOffice)**: confirm these all become opt-in via tags like `--tags cosmetic` and `--tags browsers`.
- [ ] **Generic `developer` role naming** — keep `developer` or rename for clarity? (e.g. `dev-base`?). Probably keep `developer`.
