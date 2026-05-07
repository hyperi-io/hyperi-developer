# Role/Task Mapping — Refactor Target

**Status:** Draft for review. Amend this file with the final scope; the implementation will follow whatever lands here.

**Companion plan:** [`plans/2026-05-01-role-refactor-and-trim-defaults.md`](plans/2026-05-01-role-refactor-and-trim-defaults.md)

This is the authoritative table for what every existing task migrates to and what new things get added. Everything is sized so that a non-HyperI developer can install `developer` and `developer-<lang>` without having anything HyperI-opinionated forced on them.

---

## Decision summary (2026-05-01)

- Languages: `rust`, `python`, `go`, `c`, `typescript` (TS depends on Node)
- TypeScript: includes Cursor in `developer-typescript-gui` (TS devs commonly want Cursor as their editor)
- Docker Desktop: **removed entirely** from the build (any platform). On macOS, no container runtime is installed by default; document `colima` / `orbstack` / `podman` as user-installed options. On Linux, Docker Engine stays in `developer`.
- Browser policies: **removed entirely**, not migrated.
- Auto-updates: **moved to `hyperi`** — not forced on non-HyperI users.
- Bash history auto-commit: **moved to `hyperi`** — opinionated workflow, not generic.
- Nemo (replaces Nautilus) and `desktop_cleanup.yml` (hide Nautilus + dedupe Flatpak) **moved to `hyperi-gui`** — these are HyperI's desktop opinions.
- `--core` flag: **removed** entirely.
- No-flag default: `--tags developer` (lightweight CLI base only).

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

hyperi                     HyperI org-specific tools (CLI)
└─ hyperi-gui              HyperI org-specific tools (GUI)

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

| Task | Source | What it does |
|---|---|---|
| `apparmor_userns.yml` | (existing in `developer`) | Disable AppArmor unprivileged user-namespace restriction — Ubuntu 23.10+ regression that breaks Flatpak GUI apps. Generic Ubuntu bug fix. |
| `repository.yml` | (existing) | OS repo mirror config / fastestmirror. Performance only, no opinion. |
| `git.yml` | (existing) | Latest Git via official PPA (Ubuntu) / Fedora / brew. |
| `utilities.yml` | (existing) | CLI utilities (htop, ripgrep, fd, fzf, jq, yq, etc.) + Flatpak runtime. |
| `docker.yml` (Linux only) | (existing, trimmed) | Docker Engine on Linux. **macOS branch deleted** (no Docker Desktop). |
| `init.yml` | (existing) | Setup common variables. |
| `verify.yml` | (existing) | Role-end verification. |

---

## `developer-gui` (opt-in)

GUI tooling for general devs. Requires a desktop environment to be present (or installs one if missing — see `desktop.yml`).

| Task | Source | What it does |
|---|---|---|
| `desktop.yml` (Linux only) | from `developer/` | Install GNOME (Fedora) or `ubuntu-desktop-minimal` (Ubuntu) if not present. Only runs if `developer-gui` opted into. |
| `vscode.yml` | from `developer/` | VS Code editor. |
| `ghostty.yml` | from `developer/` | Ghostty terminal + JetBrains Mono font. Theme fix already applied. |
| `dbeaver.yml` | **NEW** | DBeaver Community — DB GUI. (User decision: lives in developer-gui not infrastructure-gui.) |

---

## `developer-rust` (opt-in)

| Task | Source | What it does |
|---|---|---|
| `rust.yml` | from `developer_core/` | rustup-init + cargo + sccache + mold + cargo-sweep. |

---

## `developer-python` (opt-in)

| Task | Source | What it does |
|---|---|---|
| `uv.yml` | from `developer/` | UV (Astral's Python package manager + interpreter manager). |

---

## `developer-go` (opt-in, NEW)

| Task | Source | What it does |
|---|---|---|
| `go.yml` | **NEW** | Go toolchain via package manager + gopls + dlv. |

---

## `developer-c` (opt-in)

| Task | Source | What it does |
|---|---|---|
| `c_tools.yml` | from `developer_core/` | `@c-development` (Fedora) / build-essential (Ubuntu) / Xcode CLT (macOS) + valgrind + gdb. |

---

## `developer-node` (opt-in)

| Task | Source | What it does |
|---|---|---|
| `nodejs.yml` | from `developer_core/` | Node.js (latest LTS via NodeSource or fnm) + pnpm. |

---

## `developer-typescript` (opt-in, **depends on `developer-node`**)

| Task | Source | What it does |
|---|---|---|
| `typescript.yml` | **NEW** | `npm install -g typescript ts-node tsx` (or pnpm equivalents). |

---

## `developer-typescript-gui` (opt-in, **depends on `developer-typescript`**)

| Task | Source | What it does |
|---|---|---|
| `cursor.yml` | **NEW** | Cursor editor (cursor.sh — VS Code fork with AI built-in). Linux: AppImage / .deb. macOS: brew cask. |

---

## `infrastructure` (CLI, opt-in)

Generic IaC + cloud — not HyperI-specific.

| Task | Source | What it does |
|---|---|---|
| `cloud.yml` | from `developer/` | HashiCorp tools (Terraform, Vault, Packer) + AWS CLI v2. |
| `azure.yml` | from `developer_core/` | Azure CLI. |
| `gcloud.yml` | from `developer_core/` | Google Cloud CLI. |
| `k8s.yml` | from `developer/` | kubectl + helm + k9s + minikube. |
| `data_tools.yml` (Vector) | from `developer/` | Vector data pipeline tool. (Niche; debatable. Possibly remove entirely?) |

---

## `infrastructure-gui` (opt-in, NEW)

| Task | Source | What it does |
|---|---|---|
| `lens.yml` | **NEW** | Lens — K8s desktop client. |

(DBeaver is in `developer-gui`, not here.)

---

## `hyperi` (CLI, opt-in — org-specific)

Things only HyperI users want imposed on their machine.

| Task | Source | What it does |
|---|---|---|
| `security.yml` | from `developer/` (was always-run) | Configure auto-updates (`unattended-upgrades` / `dnf-automatic`). HyperI policy. **Now opt-in.** |
| `shell_config.yml` | from `developer/` (was always-run) | Bash history auto-commit. HyperI workflow. **Now opt-in.** |
| `act.yml` | from `developer_core/` | act — run GH Actions locally (HyperI heavy CI user). |
| `bitwarden.yml` (CLI part only) | from `developer_core/` | Bitwarden CLI. |
| `claude.yml` | from `developer_core/` | Claude Code (HyperI uses it heavily). |
| `gitleaks.yml` | from `developer_core/` | Gitleaks — secret scanner. (HyperI security policy.) |
| `jfrog.yml` | from `developer_core/` | JFrog CLI (HyperI Artifactory). |
| `linear.yml` | from `developer_core/` | Linear CLI (HyperI issue tracker). |
| `netbird.yml` | from `developer_core/` | NetBird CLI (HyperI mesh VPN). |
| `openvpn.yml` | from `developer_core/` | OpenVPN client (HyperI fallback VPN). |
| `telemetry.yml` | from `developer_core/` | HyperI telemetry config. |

---

## `hyperi-gui` (opt-in — org-specific GUI apps)

| Task | Source | What it does |
|---|---|---|
| `slack.yml` | from `developer_core/` | Slack desktop. |
| `bitwarden_gui.yml` | from `developer_core/bitwarden.yml` (split) | Bitwarden GUI (Flatpak). |
| `onlyoffice.yml` | from `developer/` | OnlyOffice Desktop Editors. |
| `office.yml` | from `developer_core/` | Office suite tasks (need to read what this does). |
| `nemo.yml` | from `developer/` (was always-run) | Nemo file manager (replaces Nautilus). HyperI desktop choice. |
| `desktop_cleanup.yml` | from `developer/` (was always-run) | Hide Nautilus from menus + dedupe Flatpak/apt versions. |
| `gnome.yml` | from `developer/` (was always-run) | GNOME extensions (Astra Monitor etc.). |
| `browser_policies.yml` | ❌ **DELETED** | Was applying privacy policies. User decision: drop entirely. |

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
| `developer` | git, CLI utilities, Docker Engine (Linux only) |
| `developer-gui` | desktop env if missing, VS Code, Ghostty + JetBrains Mono, DBeaver |
| `developer-python` | UV |

What they DON'T get:
- ❌ No auto-updates configured (HyperI policy)
- ❌ No Nemo replacing Nautilus
- ❌ No GNOME extensions
- ❌ No bash history auto-commit
- ❌ No Slack, Linear, JFrog, NetBird, OpenVPN, Bitwarden, Claude Code
- ❌ No browser privacy policies
- ❌ No wallpaper or avatar
- ❌ No Rust, Go, C, Node toolchains
- ❌ No Docker Desktop, no Cursor

Lightweight, no surprises, no org-imposing.

---

## Open questions for you to amend before implementation

- [ ] **Confirm language list**: rust, python, go, c, node, typescript. Drop any? Add any?
- [ ] **DBeaver**: confirm it's `developer-gui` (you said so above — recording)
- [ ] **Vector**: keep in `infrastructure`, or drop entirely (niche tool)
- [ ] **GNOME extensions** in `hyperi-gui`: keep, or move to opt-in `gnome-extensions` tag
- [ ] **Cosmetic split**: should `wallpaper` and `avatar` be one tag (`cosmetic`) or two (`wallpaper`, `avatar`)?
- [ ] **Auto-updates in hyperi**: actively configure auto-updates, or just ensure the package is present and let the user enable? (Currently configures.)
- [ ] **Always-run additions/removals**: anything you'd add or take off the "always-run" list of 2 items?

Edit this file with your decisions, then I'll execute.
