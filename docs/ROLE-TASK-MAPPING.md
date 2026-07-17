# Role/Task Mapping — Refactor Target

**Status:** Draft for review. Amend this file with the final scope; the implementation will follow whatever lands here.

**Companion plan:** [`plans/2026-05-01-role-refactor-and-trim-defaults.md`](plans/2026-05-01-role-refactor-and-trim-defaults.md)

This is the authoritative table for what every existing task migrates to and what new things get added. Everything is sized so that a non-HyperI developer can install `developer` and `developer-<lang>` without having anything HyperI-opinionated forced on them.

---

## Decision summary (2026-05-01)

- **Repo rename**: `dfe-developer` → `hyperi-developer` (separate work stream — see "Out-of-scope-but-tracked")
- **Submodule attachment**: hyperi-developer added as a submodule under hyperi-infra for in-flight development convenience (separate work stream)
- **Languages**: `rust`, `python`, `go`, `c`, `typescript` (TS depends on Node)
- **TypeScript**: includes Cursor in `developer-typescript-gui` (TS devs commonly want Cursor as their editor)
- **Docker on macOS**: install latest **Docker CLI** via Homebrew (NOT Docker Desktop). Docker Desktop's GUI/proprietary install is dropped entirely. On Linux, Docker Engine stays in `developer`.
- **Browser policies**: **removed entirely**, not migrated.
- **Removed entirely** (per user 2026-05-01):
  - Bitwarden — both CLI and GUI (confirmed)
  - JFrog CLI
  - Linear CLI
  - NetBird CLI
- **Renamed**: `telemetry.yml` → `telemetry-disable.yml` (it disables telemetry/ads, doesn't add it — name was misleading)
- **Auto-updates**: **moved to `soe`** — not forced on non-HyperI users.
- **Bash history auto-commit**: **moved to `soe`** — opinionated workflow, not generic.
- **VPN (NetBird, OpenVPN)**: HyperI-specific. NetBird removed entirely; OpenVPN stays in `soe`.
- **Nemo + `desktop_cleanup.yml`**: **moved to `soe-gui`** — HyperI desktop opinions.
- **`--core` flag**: **removed** entirely.
- **`--all` flag**: **removed** entirely. No kitchen-sink shortcut. Pick what you want via `--tags`.
- **`--soe` flag**: **NEW** — single shortcut for "what a HyperI staff member typically wants on their machine". See "--soe flag composition" section below.
- **No-flag default**: `--tags developer` (lightweight CLI base only).
- **`/fedora/` directory**: **deleted** — deprecated bash-script installer, superseded by the Ansible playbook. (Fedora support stays in the Ansible tasks via `when: distribution == 'Fedora'`.)
- **Tagging scheme**: two-level — primary group tags (`developer`, `soe-gui`, etc.) + per-app sub-tags (`slack`, `vscode`, etc.) on every task. See "Tagging mechanism" section below.

---

## Tagging mechanism — primary tags + per-app sub-tags

To install a single app (e.g. just Slack, nothing else) without exploding the top-level tag list to a "bazillion entries", use **two-level tags**:

**Every task gets two tags:**
1. A **primary group tag** — the role/group the task belongs to (`developer`, `developer-gui`, `soe-gui`, etc.)
2. A **per-app sub-tag** — the specific task name (`slack`, `vscode`, `ghostty`, `claude`, `cursor`, `lens`, `dbeaver`, etc.)

**Implementation pattern in `playbooks/main.yml`:**

```yaml
- name: Install Slack
  ansible.builtin.include_tasks:
    file: slack.yml
    apply:
      tags: ['soe-gui', 'slack']
  tags: ['soe-gui', 'slack']
```

**User-facing behaviour:**

| Command | Result |
|---|---|
| `./install.sh` (no flags) | Just `developer` group |
| `./install.sh --tags soe-gui` | All soe-gui apps (Slack, Bitwarden GUI, OnlyOffice, etc.) |
| `./install.sh --tags slack` | **Only** Slack — skips everything else, including the rest of soe-gui |
| `./install.sh --tags slack,claude` | Just those two |
| `./install.sh --tags developer,developer-rust,vscode` | Generic dev base + Rust + just VS Code (no other GUI tools) |
| `./install.sh --all` | Everything (kitchen sink) |

**`--help` only shows primary group tags** (~12 entries, manageable). Per-app tags are listed in this `ROLE-TASK-MAPPING.md` doc under each role section. New helper flag `--list-apps` will dump the full per-app tag list for power users.

This is the standard Ansible pattern — `include_tasks` with multiple tags applied. No custom plumbing required.

---

## Role tree

```
developer                  Generic CLI dev base (any user)
├─ developer-gui           GUI editors + DB GUI + terminal
├─ developer-rust          Rust toolchain (CLI only)
├─ developer-python        Python toolchain (CLI only)
├─ developer-go            Go toolchain (CLI only)
├─ developer-c             C/C++ toolchain (CLI only)
├─ developer-node          Node.js / npm / pnpm (CLI only)
└─ developer-typescript    TypeScript (depends on developer-node)
   └─ developer-typescript-gui  Cursor editor

infrastructure             IaC + cloud CLIs (any IaC operator)
└─ infrastructure-gui      Lens (no DBeaver — DBeaver is in developer-gui)

contributor                What you need to work ON a HyperI product:
                           the CI toolchain (hyperi-ci + gitleaks, act,
                           semgrep, alint, osv-scanner). No org policy.
                           Depends on: developer

soe                        HyperI Standard Operating Environment — org
                           POLICY: VPN, telemetry-disable, bash history,
                           branding. Depends on: contributor
└─ soe-gui                 Org-specific tools (GUI)

rdp                        Remote desktop (single role, no -gui split)
vm_optimizer               VM-only optimisations (single role, no -gui split)

bash-modern                macOS only — modern bash via Homebrew (opt-in)

(opt-in, no role — just tag)
cosmetic                   wallpaper, avatar
chrome / brave             individual browser tags
```

---

## `developer` (CLI, default with no flags)

Universal lightweight dev base. Anyone can install this without it touching their existing environment hard.

| Task | Per-app tag | Source | What it does |
|---|---|---|---|
| `apparmor_userns.yml` | `apparmor` | (existing in `developer`) | Disable AppArmor unprivileged user-namespace restriction — Ubuntu 23.10+ regression that breaks Flatpak GUI apps. Generic Ubuntu bug fix. |
| `repository.yml` | `repository` | (existing) | OS repo mirror config / fastestmirror. Performance only, no opinion. |
| `git.yml` | `git` | (existing) | Latest Git via official PPA (Ubuntu) / Fedora / brew. |
| `utilities.yml` | `utilities` | (existing) | CLI utilities (htop, ripgrep, fd, fzf, jq, yq, etc.) + Flatpak runtime. |
| `docker.yml` | `docker` | (existing, trimmed) | **Linux:** Docker Engine. **macOS:** latest Docker CLI via brew (NOT Docker Desktop — no GUI/proprietary install). User picks their own daemon (colima/orbstack/podman). |
| `init.yml` | `init` | (existing) | Setup common variables. |
| `verify.yml` | `verify` | (existing) | Role-end verification. |

---

## `developer-gui` (opt-in)

GUI tooling for general devs. Requires a desktop environment to be present (or installs one if missing — see `desktop.yml`).

| Task | Per-app tag | Source | What it does |
|---|---|---|---|
| `desktop.yml` (Linux only) | `desktop` | from `developer/` | Install GNOME (Fedora) or `ubuntu-desktop-minimal` (Ubuntu) if not present. Only runs if `developer-gui` opted into. |
| `vscode.yml` | `vscode` | from `developer/` | VS Code editor. |
| `ghostty.yml` | `ghostty` | from `developer/` | Ghostty terminal + JetBrains Mono font. Theme fix already applied. |
| `dbeaver.yml` | `dbeaver` | **NEW** | DBeaver Community — DB GUI. (User decision: lives in developer-gui not infrastructure-gui.) |

---

## `developer-rust` (opt-in)

| Task | Per-app tag | Source | What it does |
|---|---|---|---|
| `rust.yml` | `rust` | from `developer_core/` | rustup-init + cargo + sccache + mold + cargo-sweep. |

---

## `developer-python` (opt-in)

| Task | Per-app tag | Source | What it does |
|---|---|---|---|
| `uv.yml` | `uv` | from `developer/` | UV (Astral's Python package manager + interpreter manager). |

---

## `developer-go` (opt-in, NEW)

| Task | Per-app tag | Source | What it does |
|---|---|---|---|
| `go.yml` | `go` | **NEW** | Go toolchain via package manager + gopls + dlv. |

---

## `developer-c` (opt-in)

| Task | Per-app tag | Source | What it does |
|---|---|---|---|
| `c_tools.yml` | `c-tools` | from `developer_core/` | `@c-development` (Fedora) / build-essential (Ubuntu) / Xcode CLT (macOS) + valgrind + gdb. |

---

## `developer-node` (opt-in)

| Task | Per-app tag | Source | What it does |
|---|---|---|---|
| `nodejs.yml` | `nodejs` | from `developer_core/` | Node.js (latest LTS via NodeSource or fnm) + pnpm. |

---

## `developer-typescript` (opt-in, **depends on `developer-node`**)

| Task | Per-app tag | Source | What it does |
|---|---|---|---|
| `typescript.yml` | `typescript` | **NEW** | `npm install -g typescript ts-node tsx` (or pnpm equivalents). |

---

## `developer-typescript-gui` (opt-in, **depends on `developer-typescript`**)

| Task | Per-app tag | Source | What it does |
|---|---|---|---|
| `cursor.yml` | `cursor` | **NEW** | Cursor editor (cursor.sh — VS Code fork with AI built-in). Linux: AppImage / .deb. macOS: brew cask. |

---

## `infrastructure` (CLI, opt-in)

Generic IaC + cloud — not HyperI-specific.

| Task | Per-app tag | Source | What it does |
|---|---|---|---|
| `cloud.yml` | `cloud` | from `developer/` | OpenTofu + OpenBao (the OSS forks; no HashiCorp BUSL tools) + AWS CLI v2. |
| `azure.yml` | `azure` | from `developer_core/` | Azure CLI. |
| `gcloud.yml` | `gcloud` | from `developer_core/` | Google Cloud CLI. |
| `k8s.yml` | `k8s` | from `developer/` | kubectl + helm + k9s + minikube. |
| `data_tools.yml` (Vector) | `vector` | from `developer/` | Vector data pipeline tool. (Niche; debatable. Possibly remove entirely?) |

---

## `infrastructure-gui` (opt-in, NEW)

| Task | Per-app tag | Source | What it does |
|---|---|---|---|
| `lens.yml` | `lens` | **NEW** | Lens — K8s desktop client. |

(DBeaver is in `developer-gui`, not here.)

---

## `soe` (CLI, opt-in — org-specific)

Things only HyperI users want imposed on their machine.

| Task | Per-app tag | Source | What it does |
|---|---|---|---|
| `security.yml` | `auto-updates` | from `developer/` (was always-run) | Configure auto-updates (`unattended-upgrades` / `dnf-automatic`). HyperI policy. **Now opt-in.** |
| `shell_config.yml` | `bash-history` | from `developer/` (was always-run) | Bash history auto-commit. HyperI workflow. **Now opt-in.** |
| `act.yml` | `act` | from `developer_core/` | act — run GH Actions locally (HyperI heavy CI user). |
| `claude.yml` | `claude` | from `developer_core/` | Claude Code (HyperI uses it heavily). |
| `gitleaks.yml` | `gitleaks` | from `developer_core/` | Gitleaks — secret scanner. (HyperI security policy.) |
| `openvpn.yml` | `openvpn` | from `developer_core/` | OpenVPN client (HyperI VPN). |
| `telemetry-disable.yml` | `telemetry-disable` | renamed from `telemetry.yml` | Disable Ubuntu Pro/ESM ads, MOTD news, crash reporting, telemetry. Privacy hardening. |
| ❌ `bitwarden.yml` (CLI part) | — | **REMOVED** | User decision 2026-05-01 |
| ❌ `jfrog.yml` | — | **REMOVED** | User decision 2026-05-01 |
| ❌ `linear.yml` | — | **REMOVED** | User decision 2026-05-01 |
| ❌ `netbird.yml` | — | **REMOVED** | User decision 2026-05-01 |

---

## `soe-gui` (opt-in — org-specific GUI apps)

| Task | Per-app tag | Source | What it does |
|---|---|---|---|
| `slack.yml` | `slack` | from `developer_core/` | Slack desktop. |
| `onlyoffice.yml` | `onlyoffice` | from `developer/` | OnlyOffice Desktop Editors. |
| `office.yml` | `office` | from `developer_core/` | Office suite tasks (need to read what this does). |
| `nemo.yml` | `nemo` | from `developer/` (was always-run) | Nemo file manager (replaces Nautilus). HyperI desktop choice. |
| `desktop_cleanup.yml` | `desktop-cleanup` | from `developer/` (was always-run) | Hide Nautilus from menus + dedupe Flatpak/apt versions. |
| `gnome.yml` | `gnome-extensions` | from `developer/` (was always-run) | GNOME extensions (Astra Monitor etc.). |
| ❌ `bitwarden_gui.yml` | — | **REMOVED** | User decision 2026-05-01 (confirmed) |
| ❌ `browser_policies.yml` | — | **DELETED** | Privacy policies. Drop entirely. |

---

## `bash-modern` (opt-in, macOS only, NEW)

| Task | Source | What it does |
|---|---|---|
| `brew_bash.yml` | **NEW** | `brew install bash` + add `/opt/homebrew/bin/bash` to `/etc/shells`. **Does NOT chsh** — that's a deliberate user choice. |

---

## Opt-in cosmetic / per-app tags (no full role)

These are single-task tags, not full roles.

| Tag | Task | Notes |
|---|---|---|
| `cosmetic` | `wallpaper.yml` + `avatar.yml` | The duplicated `wallpaper.yml` in `developer_core/` will be deleted; only the one in this group survives. |
| `chrome` | `chrome.yml` | Google Chrome. |
| `brave` | `brave.yml` | Brave browser. |
| `region` | `region.yml` | Locale + hunspell — already gated by `--region` flag. |

---

## Removed entirely

| Task | Why |
|---|---|
| `browser_policies.yml` | User decision — opinionated org policy, not migrating |
| Docker Desktop install on macOS | User decision — drop entirely; users install colima/orbstack/podman themselves |
| Duplicated `developer_core/wallpaper.yml` | One copy will live in cosmetic tag; the other is deleted |

---

## "Always-run" (no tag — system bootstrap, runs unconditionally)

After moving things out, the always-run list is **smaller** than today:

| Task | Why universal |
|---|---|
| `apparmor_userns.yml` | Ubuntu 23.10+ bug — breaks Flatpak GUI apps for everyone, not opinionated |
| `repository.yml` | Mirror config — performance only, no opinion |

That's it. Everything else moves into a role or tag.

Note: `region.yml` is "always run" today but only fires if `--region <code>` is passed; that mechanism stays.

---

## Default install (`./install.sh`, no flags)

→ `--tags developer` only. Just the lightweight CLI base + the system-bootstrap tasks above.

Anyone wanting more does `--tags developer,developer-gui` or `--tags developer,developer-python` etc.

`--all` keeps current "kitchen sink" semantics for those who want everything.

---

## Sanity check — what does a non-HyperI Python dev get with `./install.sh --tags developer,developer-gui,developer-python`?

| Tag | Installs |
|---|---|
| (always-run) | AppArmor userns fix, repo mirrors |
| `developer` | git, CLI utilities, Docker (Engine on Linux / CLI-only via brew on macOS — no Docker Desktop) |
| `developer-gui` | desktop env if missing, VS Code, Ghostty + JetBrains Mono, DBeaver |
| `developer-python` | UV |

What they DON'T get:
- ❌ No auto-updates configured (HyperI policy)
- ❌ No Nemo replacing Nautilus
- ❌ No GNOME extensions
- ❌ No bash history auto-commit
- ❌ No Slack, OpenVPN, Claude Code (HyperI org-tools)
- ❌ No browser privacy policies (deleted entirely)
- ❌ No wallpaper or avatar
- ❌ No Rust, Go, C, Node toolchains (separate language tags)
- ❌ No Docker Desktop, no Cursor (Cursor lives under `developer-typescript-gui`)

Lightweight, no surprises, no org-imposing. macOS users still get a working modern Docker CLI (just not the Desktop GUI/proprietary).

---

## `--soe` flag composition (discussion)

Single shortcut for "HyperI staff member's typical workstation". Avoids forcing a kitchen-sink install but gets all the org-relevant stuff in one switch.

**Proposed default mapping:**

```bash
--soe ≡ --tags developer-gui,soe,soe-gui,cosmetic   (soe pulls contributor pulls developer)
```

That gives a HyperI staffer:
- Generic CLI dev base + GUI editor/terminal/DBeaver
- HyperI auto-updates, bash-history, claude code, gitleaks, openvpn, telemetry-disable, act
- HyperI desktop opinions (Slack, OnlyOffice, Nemo file manager, GNOME extensions)
- HyperI wallpaper + avatar

**What `--soe` does NOT include (deliberate):**
- Languages — too personal. Add `--tags developer-rust` etc. as needed.
- Infrastructure — only some HyperI staff are SRE/IaC. Add `--tags infrastructure,infrastructure-gui` as needed.
- RDP / VM optimizer — only relevant if you're building a VM template.
- macOS modern bash — opt-in by design.
- Region — pass `--region au` explicitly.

**Composability:**
- HyperI Rust dev: `--soe --tags developer-rust`
- HyperI Python dev: `--soe --tags developer-python`
- HyperI SRE: `--soe --tags infrastructure,infrastructure-gui`
- HyperI Aussie staff: `--soe --region au`

**Open question:** should `--soe` *default* include `infrastructure` (since most HyperI staff probably want at least some k8s/cloud tooling), or stay strictly persona-agnostic? Recommend: stay agnostic, force the SRE-leaning folks to add it explicitly. Avoids bloating the default.

---

## Out-of-scope-but-tracked (separate work streams)

These are bigger pieces that follow this refactor but aren't part of the role/tag work:

### Repo rename: `dfe-developer` → `hyperi-developer` (DONE on GitHub)

- ✅ GitHub repo renamed (`gh repo rename hyperi-developer`, run by user 2026-05-01)
- ✅ GitHub repo description updated
- ✅ Local git remote URL updated
- ⏳ Update `package.json` `name` field
- ⏳ Update README + CHANGELOG headers
- ⏳ Update VERSION metadata if it embeds the name
- ⏳ Update CI release config if it references the repo name
- ⏳ Update consumers — `hyperi-infra/packer/templates/ubuntu-desktop.pkr.hcl` references `https://github.com/hyperi-io/dfe-developer.git`; needs swap (GitHub redirects so it still works, but should be cleaned up)
- ⏳ User to rename the local checkout dir if desired (`mv /projects/dfe-developer /projects/hyperi-developer`) — git operations and IDE windows will need attention

### Submodule attachment in hyperi-infra

- `git submodule add https://github.com/hyperi-io/hyperi-developer.git subprojects/hyperi-developer` (or wherever)
- Update `hyperi-infra/CLAUDE.md` to document the new submodule and how it relates to the desktop build pipeline
- Decide: does the desktop Packer template clone fresh from URL (current behaviour) or pull from the submodule path? Probably stays URL-based for build reproducibility, with submodule as a dev-convenience path.

### Delete `/fedora/` directory

- Deprecated bash-script installer (still says "HyperSec"), superseded by Ansible roles
- Files: `fedora/{QUICKSTART.md,default-background.svg,install-*.sh,lib.sh,tests/}` — all go
- Update README + CHANGELOG to remove references
- Fedora support stays via `when: ansible_facts['distribution'] == 'Fedora'` conditionals in tasks

---

## Open questions for you to amend before implementation

- [x] ~~Bitwarden GUI~~: confirmed remove both CLI and GUI 2026-05-01
- [ ] **Languages**: confirmed rust, python, go, c, node, typescript. (Java? Ruby? — assume not unless added.)
- [ ] **Vector** in `infrastructure`: keep, or drop entirely (niche)?
- [ ] **`office.yml`** in `soe-gui`: I haven't read its contents yet — will check during implementation; might be redundant with `onlyoffice.yml`.
- [ ] **Auto-updates in `soe`**: actively configure auto-updates, or just ensure the package is present and let the user enable? (Currently configures.)
- [ ] **Cosmetic split**: should `wallpaper` and `avatar` be one tag (`cosmetic`) or two (`wallpaper`, `avatar`)? (Per-app tags exist either way; this is about the group label.)
- [ ] **Always-run additions/removals**: anything you'd add or take off the "always-run" list of 2 items (apparmor + repository)?
- [ ] **Submodule path**: where in hyperi-infra should hyperi-developer attach? `subprojects/hyperi-developer` (matches mail-migration / atlassian-decom pattern)?

Edit this file with your decisions, then I'll execute.
