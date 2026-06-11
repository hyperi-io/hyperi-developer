# Role Structure Refactor — Design

**Status:** Draft (rev 2 — two-tier split added)
**Date:** 2026-04-18
**Author:** Derek + Claude (brainstorming session)
**Scope:** Track 1 of the two-track April 2026 DFE refresh. Track 2 (Ubuntu 26.04 compatibility / DRAGONFLY gaps) has its own spec.

## Context

The DFE developer environment currently installs almost every tool unconditionally. The `developer` and `developer_core` roles between them carry ~40 task files, and the only filter is Ansible tags — which require the user to know the exact tag name in advance and pass `--tags-exclude` for anything they don't want.

Four pressures make this the right moment to refactor:

1. **Personas have emerged.** Different devs need different toolchains — Rust engineers don't need the Confluent CLI; infra engineers don't need a Rust compiler. One-size-fits-all installs waste time and disk, and the status quo makes it hard to extend (adding any tool means it runs for everyone).
2. **Two distinct user populations.** Hyperi-internal devs need Slack/Linear/JFrog/VPN-to-infra; external DFE/ESH contributors don't — and shouldn't be forced to install Hyperi-specific tooling. The current role layout blurs this line.
3. **VPN transition.** WireGuard is replacing OpenVPN as the default VPN in the next month or two. OpenVPN needs to become opt-in before the flip, without breaking in-flight users.
4. **Ubuntu 26.04 work (Track 2)** will touch many of the same files — cleaner to land a structural refactor first so the 26.04 bugfixes apply to a stable base.

## Goals

- Introduce a **two-tier base split**: `developer` (OSS-safe, for external contributors on DFE/ESH) and `core` (Hyperi-internal, layered on top of `developer`).
- Introduce **named profiles** (`rust`, `iac`, `openvpn`, `gui_extras`) that compose additively on top of either tier.
- Make each tier **lean but complete** — everything every dev in that tier genuinely needs, nothing they don't.
- Provide an **opt-out mechanism** for user-facing apps via `install_<name>: false` variables.
- Support the **WireGuard → OpenVPN transition** by placing WireGuard in `core` (default) and OpenVPN in a transitional opt-in profile.
- **Audit every version pin and external URL** during execution; bucket findings as fix-now / Track-2 / follow-up.
- **Document every tool** with a short rationale: what it does, why we picked it, what it's used for.

## Non-goals

- No new tooling added beyond what's named in this spec (Bruno, Podman Desktop, DBeaver, Freelens, lazygit, kcat, wl-clipboard).
- No "frontend" profile — deferred until there's real frontend-specific tooling.
- No macOS support changes. Existing `ansible_facts['distribution'] == 'MacOSX'` branches preserved.
- No per-cloud granularity. `aws`/`azure`/`gcloud` all live in the `developer` tier as universal CLIs.

## Design

### Invocation UX

```bash
./install.sh --profile developer                   # external contributor (OSS tier only)
./install.sh --profile core                        # Hyperi dev (developer + core)
./install.sh --profile core,rust                   # Hyperi + Rust
./install.sh --profile core,rust,iac               # Hyperi + Rust + infra
./install.sh --profile core,all                    # Hyperi + rust + iac + gui_extras (no openvpn)
./install.sh --profile core,openvpn                # Hyperi + legacy VPN (transition)
./install.sh --profile developer,rust              # external Rust contributor
./install.sh --extra-vars install_slack=false      # opt out of a user-facing app
```

- `--profile core` implies `developer` (hidden dependency — the Hyperi tier is always additive on the OSS tier).
- `--profile all` expands to `rust,iac,gui_extras` on whichever base tier is selected. OpenVPN stays out of `all` because it's a transitional, explicit-opt-in bucket.
- `--tags` remains available for ad-hoc runs.
- If no `--profile` is given, default is `developer` (lean, safe, public-friendly). Hyperi users are expected to pass `--profile core`; the Hyperi-facing README makes that prominent.

**Invocation edge-case rules:**
- `--profile developer,core` — treated as a no-op alias for `--profile core` (redundant but harmless; implementation deduplicates the base tier).
- `--profile all` alone — expands to `--profile developer,rust,iac,gui_extras` (the default base tier is `developer`).
- `--profile openvpn` alone — **hard validation error**: openvpn requires `core` (its peer config is Hyperi-specific). Error message: `"--profile openvpn requires --profile core"`.
- `--profile rust` / `--profile iac` / `--profile gui_extras` alone — valid; base tier defaults to `developer`.
- Unknown profile name — **hard validation error** listing valid profiles.

The `install.sh` script performs this validation before invoking Ansible, so errors surface early with clear messages.

### Role layout

```
ansible/roles/
├── developer/         # OSS tier — reworked from existing "developer" role
├── core/              # NEW — Hyperi internal tier
├── rust/              # NEW — extracted from developer_core
├── iac/               # NEW — extracted from developer + developer_core
├── gui_extras/        # NEW — optional GUI/TUI extras
├── openvpn/           # NEW — opt-in, transitional (extracted from developer_core)
├── rdp/               # unchanged
├── vm_optimizer/      # unchanged
└── system_cleanup/    # unchanged
```

The `developer_core` role dissolves entirely — its task files redistribute. The existing `developer` role is reworked (not renamed) to strictly contain the OSS-safe tier.

### `developer` tier — OSS-safe, external-contributor-ready

Everything useful for general dev work on an open-source project (DFE, ESH). No Hyperi-specific tooling, branding, or credentials.

**OS plumbing:**
- `init.yml`, `repository.yml`, `security.yml`, `apparmor_userns.yml`, `telemetry.yml`, `region.yml`

**Desktop:**
- `desktop.yml`, `gnome.yml`, `nemo.yml`, `ghostty.yml`, `shell_config.yml`

**Core CLI:**
- `utilities.yml` — jq, ripgrep, fzf, tmux, bat, fd-find, rsync, httpie, shellcheck, **wl-clipboard** *(new)*, etc.
- `git.yml`, `docker.yml`, `c_tools.yml`

**Python (always):**
- `uv.yml` — uv, python3, venv, pytest, pipx

**Editor/browsers:**
- `vscode.yml`, `chrome.yml`, `brave.yml`, `browser_policies.yml`

**Generic cloud CLIs:**
- aws, azure, gcloud, gh

**Release/CI automation:**
- `nodejs.yml` (+ semantic-release), `act.yml`, `gitleaks.yml`

**Data tooling:**
- Confluent CLI (existing), **kcat** *(new — same auto-detect-latest pattern)*

**General user-facing apps (opt-outable):**
- Bitwarden (`install_bitwarden`), OnlyOffice (`install_onlyoffice`), Mailspring (`install_mailspring`), Claude Code CLI

**Final:**
- `verify.yml` — confirms every tool in the tier installed successfully

### `core` tier — Hyperi internal add-ons

Installed only when `--profile core` is selected. Implies (depends on) `developer`.

- **Slack** — Hyperi team comms
- **Linear CLI** — Hyperi project management
- **JFrog CLI** — Hyperi Artifactory / binary repos
- **WireGuard** + Hyperi peer config — default Hyperi infra VPN
- **Hyperi-branded wallpaper** (`wallpaper.yml`) and default avatar (`avatar.yml`)
- Any Hyperi-specific env/dotfiles baked in at install time

### Profile contents

**`rust`** — Rust toolchain and cargo-installed developer tooling.
- rustup, cargo, bacon, nextest, deny, tarpaulin, chef, cargo-sweep, sccache, mold

**`iac`** — Infrastructure-as-code tooling.
- terraform, vault, helm, kubectl, k9s, kubectx/kubens, minikube, argocd, dive

**`openvpn`** — Legacy VPN stack (transitional, requires `core`).
- openvpn3 CLI, `openvpn3-indicator` tray, `openvpn3-service-netcfg --config-set systemd-resolved yes`
- **Deletion target:** once WireGuard migration completes (~2026-06), this role is removed.

**`gui_extras`** — Optional GUI/TUI extras.
- **Freelens** — k8s cluster GUI
- **Bruno** — API client, local-first/git-native (FOSS Postman alternative)
- **Podman Desktop** — container GUI (FOSS Docker Desktop alternative, no license concerns)
- **DBeaver Community** — universal database client
- **lazygit** — TUI git helper (our only GitHub/git helper tool — skipped GitHub Desktop)

### Opt-out convention

Pattern: each opt-outable task declares an `install_<name>` variable that defaults to `true`. The include is gated with `when: install_<name> | default(true)`.

Opt-outable (minimum set — can be expanded later):
- `developer` tier: `install_bitwarden`, `install_onlyoffice`, `install_mailspring`, `install_brave`
- `core` tier: `install_slack`, `install_linear`

Foundational tools are deliberately **not** opt-outable: git, docker, uv, utilities, security, repository, shell_config.

### Tool documentation deliverable

A new docs file (`docs/TOOLS.md`) must be created as part of this refactor. For each tool in the `developer` tier, `core` tier, and every profile, it lists:

- **Name + upstream link**
- **Bucket** — developer (opt-outable or not), core, rust, iac, gui_extras, openvpn
- **What it does** — one sentence
- **Why it's installed** — what workflow it supports (build/CI/release/secrets/infra/comms/etc.)
- **Why this tool** — the rationale for picking it over alternatives (e.g. "Bruno over Postman because local-first and no account required"; "Podman Desktop over Docker Desktop because no licensing concerns")
- **OSS-safe note** — whether the tool's inclusion in the `developer` tier is safe for external contributors (always yes for `developer` tier tools by definition — flagged as an audit checkpoint)

Structure: table of contents by bucket, then one short subsection per tool. Target size: ~500-900 words per bucket's worth of tools.

The README's "What's installed" section is replaced with a short summary and a link to `docs/TOOLS.md`. The README must also clearly explain the `developer` vs `core` tier distinction and show invocation examples for both audiences.

### Audit — bundled into execution

During implementation, grep every task file for external references and hard-coded versions:
- `url:`, `baseurl:`, `gpgkey:`, `key:`, `repo:` (apt_repository), `src:` (download URLs)
- `version:` values, `*_version` set_fact variables
- PPA names, `apt_key`, `rpm_key` URLs

For each, evaluate: (a) still reachable? (b) pin justified? (c) upstream drifted?

**Bucket findings:**
- **Fix-now** (trivial, zero-risk): bad repo URL, accidental pin, obviously obsolete apt source → fix inline.
- **Flag for Track 2 (Ubuntu 26.04)**: anything that only breaks on 26.04 → note in Track 2 spec.
- **Defer to TODO.md**: larger follow-ups that need real investigation.

Known intentional pins (do not touch):
- `grd_patched_version` — we own the GRD patch.
- HashiCorp Ubuntu release fallback `>24.04 → noble` — deliberate.
- `min_*_version` in `init.yml` — gate checks, not pins.

## Backward compatibility

- Existing tag names preserved where sensible (`--tags rust`, `--tags azure`, `--tags vscode`). The refactor reorganizes file layout but keeps tag identifiers stable so long-running inventories don't break.
- `install.sh --core` → aliases to `--profile core,rust,iac` (old `--core` was "everything advanced") with a deprecation warning for one release, then removed.
- `install.sh --all` → aliases to `--profile core,all`.
- The `developer_core` role is removed from `playbooks/main.yml`. Any inventory/vars explicitly referencing it will fail loudly; migration notes in the README tell users to swap to `--profile core,rust,iac`.
- **`--tags developer_core` is not aliased** — scripts/CI passing that tag must be updated manually. The migration note in the README calls this out explicitly.

## Testing

- `test.sh` adds profile-matrix check-mode runs: `developer`-only, `core`-only, `core,rust`, `core,iac`, `core,all`, `developer,rust`. Catches playbook-level regressions before VM testing.
- Full end-to-end VM test on fresh Ubuntu 24.04:
  - Run 1: `--profile core,all` — Hyperi full install
  - Run 2: `--profile developer` — OSS baseline, confirm no Hyperi tooling leaks in. **Automated assertion:** post-run script greps `apt list --installed` and `which` for Slack, linear-cli, jfrog-cli, wireguard, and the Hyperi wallpaper/avatar paths — any hit fails the test. This makes the OSS-safe guarantee enforceable rather than a manual goal.
- macOS runs validated in check-mode only — existing posture.

## Risks and mitigations

- **Hyperi-specific tooling accidentally leaks into `developer` tier.** Mitigation: explicit audit checkpoint in the TOOLS.md review ("is this OSS-safe?") for every item in `developer`.
- **Inventory files referencing removed roles.** Mitigation: grep the repo for `developer_core` references (playbooks, vars, docs) during migration, update or delete.
- **Users expecting `install.sh` with no args to install everything.** Mitigation: the lean-`developer`-default is a behaviour change — README needs a clear migration note and `--profile core,all` shown prominently for Hyperi devs.
- **`core` tier grows to hide general-purpose tools.** Mitigation: the TOOLS.md rationale field ("why it's in core") forces the author to justify — if the justification is "everyone uses it," the tool moves to `developer`.
- **Opt-out variables overlooked during future work.** Mitigation: variable list centralized in `group_vars/all.yml` with defaults, so new tasks inherit the opt-out check by convention.
- **Audit findings balloon scope.** Mitigation: tri-state bucketing (fix-now / Track-2 / defer) is the guardrail — anything non-trivial escapes this spec.

## Open questions

None after brainstorming — all design decisions confirmed. Questions that might surface during implementation will be handled in the plan review.

## Related

- Track 2 spec (pending) — Ubuntu 26.04 compatibility + DRAGONFLY.md gaps. Will consume the layout defined here.
- `~/Downloads/DRAGONFLY.md` — source of several Track 2 findings, some of which (wl-clipboard, kcat) are pulled into Track 1.
- `docs/plans/2026-03-25-grd-30hz-patch.md` — previous planning doc, sibling format.
