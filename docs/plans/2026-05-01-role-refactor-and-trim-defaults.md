# Role Refactor + Trim Defaults — Implementation Plan

**Status:** Design phase. Open decisions below need a decision before implementation.

**Goal:** Restructure dfe-developer Ansible roles so the **default install is much smaller**, opinionated tools are **opt-in via themed groups**, and the confusing `core` name is replaced with something that accurately describes its contents.

**Companion goal:** Add a clean, isolated path for installing modern bash on macOS without disturbing system bash or anything Apple ships.

**Trigger:** Conversation 2026-05-01. The current default install (`./install.sh` with no flags) actually runs *all* roles because empty `--tags` causes Ansible to ignore tag filtering — despite the help text claiming `developer,base` is the default.

---

## What runs today

### `developer,base` (no-flag default → in practice, runs everything)

| Category | Tasks |
|---|---|
| Desktop / GUI base | GNOME desktop, ubuntu-desktop-minimal, LibreOffice (Fedora), Nemo, GNOME extensions, wallpaper, avatar |
| Heavy tools | Docker, VS Code, Chrome, Brave, OnlyOffice, Ghostty + JetBrains Mono font, Vector, HashiCorp tools, AWS CLI v2, kubectl + Minikube, latest Git via PPA, UV |
| System config | AppArmor userns disable, OS repo mirrors, auto-updates, browser privacy policies, bash history auto-commit, locale, hunspell, CLI utilities, Flatpak |

### `core,advanced` (`--core` / `--all`)

`act`, Azure CLI, Bitwarden CLI+GUI, build-essentials/Xcode CLT, Claude Code, gcloud, Gitleaks, JFrog CLI, Linear CLI, NetBird, Node.js, OpenVPN, Rust, Slack, Office tasks, Telemetry, Wallpaper.

> **Drift bug:** `wallpaper.yml` exists in **both** `developer/tasks/` and `developer_core/tasks/`. Pick one.

---

## Proposed structure

### Rename `developer_core` → ?

`core` is misleading — it sounds basic but contains the most-advanced/most-org-specific tooling. Candidates:

| Name | Rationale |
|---|---|
| `work` / `business` | Slack, JFrog, Linear, Azure, Bitwarden — these *are* the work-account stack |
| `hyperi` | Org-branded, accurate. Less reusable if dfe-developer is shared outside org |
| `extras` / `extended` | Generic but pairs naturally with `base`/default |
| `pro` | Marketing-y, avoid |

**Decision needed:** which name. Author's pick: **`work`** (concrete) or **`hyperi`** (most explicit).

### New tag taxonomy (themed groups)

Re-tier from 2 levels (`base` + `core`) into themed groups, each with its own tag and ideally its own role file (or include_tasks bundle):

| Group | Contains | Default? |
|---|---|---|
| `core` | docker, git, uv-python, k8s, c-tools/build-essential, utilities | **default** |
| `desktop-base` (Linux only) | GNOME tweaks, Nemo, AppArmor userns fix, region, security updates, repo mirrors | **default** |
| `editors` | VS Code | opt-in |
| `terminals` | Ghostty + fonts | opt-in |
| `browsers` | Chrome, Brave, browser privacy policies | opt-in |
| `office` | OnlyOffice, LibreOffice (Fedora) | opt-in |
| `cloud-clis` | AWS, Azure, gcloud, JFrog, HashiCorp, Vector | opt-in |
| `org-tools` (or under `hyperi`) | Slack, Linear, Bitwarden, NetBird, OpenVPN | opt-in |
| `langs` | Node.js, Rust | opt-in |
| `ai` | Claude Code | opt-in |
| `cosmetic` | wallpaper, avatar | opt-in |
| `sec-tools` | Gitleaks, act | opt-in |
| `bash-modern` (macOS only — see below) | brew install bash + /etc/shells entry | opt-in |

`--all` keeps current meaning ("everything"). `--core` (the flag) probably gets renamed too — `--full` or `--workstation`?

**Decision needed:** is the conservative `core + desktop-base` default tight enough, or tighter still (e.g. drop `desktop-base`, make even GNOME tweaks opt-in)?

### Default behaviour fix

Today: `./install.sh` (no flags) → empty `--tags` → Ansible runs **all** roles.

Should be: `./install.sh` (no flags) → `--tags core,desktop-base` → only the new minimal default fires.

`--all` and `--core`/`--full` shortcuts retain user-friendly bulk options.

---

## #4 — Modern bash on macOS

### Problem

Apple ships `/bin/bash` 3.2 (last GPLv2 release, frozen ~2007 for licensing). Modern bash is 5.x. Many dev scripts assume newer features (`mapfile`, `${var^^}`, `&>`, etc.).

### Standard practice

```bash
brew install bash
# Lands at /opt/homebrew/bin/bash (Apple Silicon) or /usr/local/bin/bash (Intel).
# /bin/bash is untouched — Apple-managed scripts unaffected.
```

To use it as login shell (user-opt-in):

```bash
sudo bash -c "echo /opt/homebrew/bin/bash >> /etc/shells"
chsh -s /opt/homebrew/bin/bash
```

### Why this is safe

- Scripts using `#!/bin/bash` keep getting Apple's 3.2 (compatibility preserved).
- Scripts using `#!/usr/bin/env bash` get whichever bash is first on PATH — Homebrew bin is normally before `/bin`, so they get bash 5.x.
- Apple's own scripts hardcode `#!/bin/bash` — isolated by construction.

### Proposed dfe-developer task (`bash-modern` tag, macOS only)

1. `brew install bash` (idempotent — no-op if installed)
2. Add `/opt/homebrew/bin/bash` (or `/usr/local/bin/bash` on Intel) to `/etc/shells` if missing
3. **Do NOT** `chsh` automatically — that's a deliberate user choice; document it instead
4. Optionally: install `bash-completion@2` (the modern completion suite) at the same time

**Decision needed:** should this be in default `core` for macOS, or strictly opt-in via `--tags bash-modern`? Author leans toward opt-in (additive but not everyone wants their PATH-first bash to change).

---

## Implementation sequence

When work resumes:

1. **Decisions** — confirm name for `developer_core` rename, confirm group split, confirm bash-modern is opt-in.
2. **Refactor `playbooks/main.yml`** — break the monolithic role-tag pairing into the new themed groups. Each group becomes its own include_tasks bundle (cheaper than splitting roles further).
3. **Rename role directory** `ansible/roles/developer_core/` → `ansible/roles/<chosen-name>/`. Update playbook references. Update install.sh tag list + `--core` flag's tag list.
4. **Fix the no-flag bug** in `install.sh` — when neither `--tags`, `--all`, nor `--core` given, set `ANSIBLE_TAGS="--tags core,desktop-base"` (or whatever is decided).
5. **De-duplicate `wallpaper.yml`** — delete one of the two copies, fold into the `cosmetic` group.
6. **Add `bash-modern` task** for macOS path with `brew install bash` + `/etc/shells` registration.
7. **Update help text** in `install.sh` to match new taxonomy. Add examples for each group.
8. **Update `README.md`** if it advertises specific tags.
9. **Test against Ubuntu 26.04 (resolute)** — see hyperi-infra plan: build VMID 9043 desktop with this branch passed via `--branch <new-feature-branch>` to the rebuild pipeline.

---

## What's already done in this branch (`feat/ghostty-update-and-trim-defaults`)

- Fixed `developer/files/ghostty/config` theme line: `Builtin Solarized` → `iTerm2 Solarized` (Ghostty renamed/removed the Builtin variants in a recent release).

That's the only edit so far. Everything else above is design pending decisions.

---

## Open decisions checklist

- [ ] Name for `developer_core` rename (recommend: `work` or `hyperi`)
- [ ] Default group set: `core,desktop-base` (recommend) vs tighter
- [ ] Is `bash-modern` default on macOS, or strictly opt-in (recommend: opt-in)
- [ ] Rename for `--core` shortcut flag (e.g. `--full` or `--workstation`)
- [ ] What to do with the duplicated `wallpaper.yml` (delete the developer_core one; fold into a `cosmetic` group)
- [ ] Order of testing: just rebuild 9043 (resolute) with the new branch, or test on a throwaway VM first
