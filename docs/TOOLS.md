# DFE Developer Environment — Installed Tools

Per-tool rationale: what it is, why we installed it, why we picked it.

This document mirrors the Ansible role layout. Each profile maps to a role directory under `ansible/roles/`. Opt-out variables are documented at the end.

## Table of contents

- [developer tier (OSS-safe base)](#developer-tier-oss-safe-base)
- [core tier (Hyperi internal)](#core-tier-hyperi-internal)
- [rust profile](#rust-profile)
- [iac profile](#iac-profile)
- [gui_extras profile](#gui_extras-profile)
- [openvpn profile (transitional)](#openvpn-profile-transitional)
- [Opt-out variables](#opt-out-variables)

## developer tier (OSS-safe base)

The `developer` tier is the OSS-safe base — no Hyperi internals, safe for external
contributors on DFE or ESH. Installed by default with `./install.sh --profile developer`.

### Git (+ GitHub CLI, git-lfs)

**Upstream:** https://git-scm.com/, https://cli.github.com/
**What it does:** Distributed version control and a GitHub-aware CLI for PRs, issues, releases, and workflow runs.
**Why it's installed:** Git is the source of truth for every Hyperi repo; the `gh` CLI lets you script PR creation and CI debugging without a browser.
**Why this tool:** Git is non-negotiable. `gh` beats `hub` as the officially maintained GitHub client with first-party support for Actions, Codespaces, and the GraphQL API. `git-lfs` handles the occasional large binary in a few repos.

### Docker

**Upstream:** https://docs.docker.com/engine/
**What it does:** Container runtime and build tooling (Docker Engine + Compose).
**Why it's installed:** The default dev-time container runtime for Hyperi services; Compose covers local multi-service stacks.
**Why this tool:** Docker Engine is installed in preference to Docker Desktop on Linux — no license ambiguity, no extra VM layer, and it works cleanly under rootless mode. Compose v2 (plugin form) is installed instead of the legacy `docker-compose` Python script. Podman Desktop ships in `gui_extras` for users who prefer it.

### uv (+ python3, python3-pytest, pipx)

**Upstream:** https://github.com/astral-sh/uv
**What it does:** Fast Rust-based Python package + project manager (virtualenv, lock, install, run).
**Why it's installed:** Standard interpreter for glue scripts, plus the project/tooling manager Hyperi standardised on.
**Why this tool:** `uv` replaces the `pip`/`pip-tools`/`poetry`/`pyenv`/`virtualenv` stack with one binary that is 10–100x faster, handles interpreter management, and has a consistent lockfile format. `pipx` is kept around for isolated CLI installs that don't warrant a project layout.

### CLI utilities (jq, ripgrep, fzf, tmux, bat, fd-find, rsync, httpie, shellcheck, wl-clipboard, yq, sd, miller, htop, age, parallel)

**Upstream:** various (upstream URLs embedded in the task file)
**What it does:** The unix tool belt: JSON/YAML filtering, fast search, fuzzy selection, terminal multiplexing, syntax-highlighted paging, modern `find`, reliable file sync, readable HTTP client, shell linting, Wayland clipboard bridge, CSV/TSV processing.
**Why it's installed:** Baseline shell productivity; scripts in this repo (and most Hyperi repos) assume these are present.
**Why this tool:** Each picks the modern FOSS replacement where one exists — `ripgrep` over `grep -R`, `fd` over `find`, `bat` over `cat`, `httpie` over raw `curl` for one-shots, `wl-clipboard` (`wl-copy`/`wl-paste`) over `xclip` on Wayland, `sd` over `sed` for simple substitutions, `miller` for tabular pipelines without pulling in pandas. `shellcheck` runs pre-commit on every shell script. `age` is the standard pre-merge encryption tool for sharing secrets during incident work.

### c_tools (gcc/clang, make, autoconf/automake, pkg-config, linker stack)

**Upstream:** https://gcc.gnu.org/, https://llvm.org/, https://www.gnu.org/software/make/
**What it does:** The classic C/C++ toolchain: compilers, linker, `make`, build-system helpers.
**Why it's installed:** A lot of cargo crates, npm native modules, and research tooling compile from source and need a working C toolchain.
**Why this tool:** Distro packages only — no vendored toolchain. `clang` is installed alongside `gcc` because the Rust profile's mold linker integration pairs cleanly with `clang` as the driver. No pinning: tracking the distro's default toolchain keeps ABI drift low.

### VS Code

**Upstream:** https://code.visualstudio.com/
**What it does:** Editor / IDE.
**Why it's installed:** The default editor for the team; extensions for Rust, Python, Terraform, and Kubernetes are assumed by several internal runbooks.
**Why this tool:** Official Microsoft build (not VSCodium) — Remote SSH and the official Microsoft extensions work out of the box, which matters for mixed local/remote workflows. Installed via the upstream apt/dnf repo so that updates flow through the OS package manager.

### Google Chrome

**Upstream:** https://www.google.com/chrome/
**What it does:** Browser.
**Why it's installed:** Primary browser for most team members; needed for enterprise SSO flows and the Hyperi workspace.
**Why this tool:** Chrome is installed alongside Brave so users can pick. Policy hardening is applied via `browser_policies.yml` (telemetry off, safe search on, etc.).

### Brave

**Upstream:** https://brave.com/
**What it does:** Privacy-hardened Chromium browser.
**Why it's installed:** Secondary browser for privacy-sensitive browsing and for testing without Chrome's Google identity attached.
**Why this tool:** Brave over Firefox as the Chromium-family alternative — most internal webapps are tested against Blink, and Brave applies sensible ad/tracker defaults without third-party extensions. Opt out via `install_brave=false`.

### AWS CLI

**Upstream:** https://aws.amazon.com/cli/
**What it does:** Official AWS command-line client.
**Why it's installed:** Touching S3, IAM, EC2, and managed services during incident response and infra work.
**Why this tool:** Installed via the official v2 bundle (not the distro package, which lags). Handles SSO natively, which the apt/dnf packages historically did not.

### Azure CLI

**Upstream:** https://learn.microsoft.com/en-us/cli/azure/
**What it does:** Official Microsoft Azure CLI.
**Why it's installed:** Tenant admin and Graph API access — see the M365 notes in the team handbook.
**Why this tool:** Official Microsoft repo, handles device code auth and Graph rest calls. No third-party alternative worth the compatibility cost.

### Google Cloud CLI

**Upstream:** https://cloud.google.com/sdk/docs
**What it does:** `gcloud` + `gsutil` + bundled components.
**Why it's installed:** Touching GCP projects that host external integrations and partner workloads.
**Why this tool:** Official Google bundle. Distro packages are outdated and miss the component updater.

### Node.js + semantic-release

**Upstream:** https://nodejs.org/, https://github.com/semantic-release/semantic-release
**What it does:** JavaScript runtime + automated versioning/release tool that reads Conventional Commits and publishes to GitHub/npm.
**Why it's installed:** CI reuses `semantic-release` for tag + changelog generation; contributors occasionally run it locally to preview.
**Why this tool:** Node LTS via NodeSource repo (keeps up with security updates faster than distro packages). `semantic-release` is the de-facto tool for Conventional-Commit-driven releases and is what every Hyperi repo's `release.yml` workflow calls.

### act

**Upstream:** https://github.com/nektos/act
**What it does:** Runs GitHub Actions workflows locally using Docker.
**Why it's installed:** Reproduce CI failures without the GitHub Actions round-trip.
**Why this tool:** `act` is the only mature local GHA runner. Accepts the same workflow YAML; bind-mounts the repo; uses the same container images as GitHub-hosted runners.

### gitleaks

**Upstream:** https://github.com/gitleaks/gitleaks
**What it does:** Secrets scanner for git repos (pre-commit + CI).
**Why it's installed:** Catch accidental secret commits before they hit the remote.
**Why this tool:** `gitleaks` is faster than `trufflehog` for pre-commit use and has a cleaner rule format. Runs in both pre-commit hooks (local) and CI (as a GitHub Action).

### Bitwarden

**Upstream:** https://bitwarden.com/
**What it does:** Password manager desktop client.
**Why it's installed:** Default team password manager; vault access for shared credentials.
**Why this tool:** Bitwarden is FOSS, self-hostable (we use the cloud tier), and has the most usable CLI (`bw`) for scripted secret fetches. Opt out via `install_bitwarden=false`.

### Claude Code CLI

**Upstream:** https://docs.anthropic.com/en/docs/claude-code
**What it does:** Anthropic's official coding agent CLI.
**Why it's installed:** Team-standard AI assistant; installed via the official npm package so updates match upstream.
**Why this tool:** Claude Code is the in-house standard for agentic coding workflows. Installed from npm (not a vendored binary) so `npm update -g` keeps it current.

### Linear CLI

**Upstream:** https://linear.app/
**What it does:** CLI for Linear issue tracker.
**Why it's installed:** Create/update issues from the terminal; useful inside scripts that open tickets on failure.
**Why this tool:** This is actually split: an OSS Linear CLI lives in the developer tier (safe for external contributors working against their own Linear workspaces); the Hyperi-workspace-configured variant lives in `core`.

### OnlyOffice Desktop Editors

**Upstream:** https://www.onlyoffice.com/
**What it does:** Desktop office suite (docs/sheets/slides) with MS Office format fidelity.
**Why it's installed:** Review/author `.docx`/`.xlsx` attachments without Microsoft 365 roundtrips.
**Why this tool:** Higher MS Office format fidelity than LibreOffice; FOSS and self-installable (no account required). Opt out via `install_onlyoffice=false`.

### kcat (kafkacat)

**Upstream:** https://github.com/edenhill/kcat
**What it does:** Non-JVM CLI producer/consumer for Kafka topics.
**Why it's installed:** Quick topic inspection and message replay without spinning up a JVM client.
**Why this tool:** Way lighter than the Confluent `kafka-console-consumer` scripts; scriptable. Package availability varies (sometimes `kafkacat`, sometimes `kcat`, sometimes a COPR on Fedora) — the task is wrapped in `failed_when: false` pending real-VM verification.

### Confluent CLI

**Upstream:** https://docs.confluent.io/confluent-cli/current/overview.html
**What it does:** Manage Confluent Cloud + Confluent Platform (topics, schemas, connectors).
**Why it's installed:** Required by the data-platform workflows that use managed Kafka.
**Why this tool:** The Kafka GUI alternatives are heavier (Kafka UI, Conduktor); `confluent` is the official supported CLI and covers the schema-registry/connect APIs too.

## core tier (Hyperi internal)

The `core` tier implies `developer` and adds the Hyperi-internal toolchain (internal
package registry, chat/issue tracker, default VPN, branding).

### Slack

**Upstream:** https://slack.com/
**What it does:** Team chat client (desktop GUI).
**Why it's installed:** Primary async comms channel; shipped pre-configured for the Hyperi workspace.
**Why this tool:** Canonical team messaging app. Installed via the official snap/flatpak/rpm rather than the browser-wrapped web version so desktop notifications, screen share, and workspace switching work reliably. Opt out via `install_slack=false` if you prefer the web UI.

### Linear (Hyperi workspace)

**Upstream:** https://linear.app/
**What it does:** Issue tracker + project manager with a fast CLI and keyboard-first UI.
**Why it's installed:** The team's canonical issue tracker. Shipping the CLI inside `core` means ticket automation works out of the box with the Hyperi workspace context.
**Why this tool:** Linear replaced the previous Jira install — orders of magnitude faster, cleaner API, and the CLI is useful in scripts (auto-open a ticket on pipeline failure). Opt out via `install_linear=false`.

### JFrog CLI

**Upstream:** https://jfrog.com/getcli/
**What it does:** Client for JFrog Artifactory / Xray / Distribution.
**Why it's installed:** Pull and publish internal container images, OCI bundles, Helm charts, and cargo/npm packages from the Hyperi internal tier.
**Why this tool:** The internal package registry runs on Artifactory, and `jf` is the only first-party client with both authentication helpers and the upload/download semantics we rely on. The Docker Desktop Artifactory plug-in is GUI-only and not a substitute.

### rclone

**Upstream:** https://rclone.org/
**What it does:** Swiss-army CLI for object storage / cloud sync (S3, GCS, SFTP, WebDAV, plus many SaaS backends).
**Why it's installed:** Mount or sync the Hyperi internal file tier during day-to-day work. Replaces bespoke `aws s3 sync` / NFS-mount scripts that were in the previous install.
**Why this tool:** `rclone` is the only tool that handles every backend the team touches (S3-compatible MinIO, SMB, WebDAV, SSH) with consistent semantics. The crypt backend is also useful for storing backups at rest.

### WireGuard

**Upstream:** https://www.wireguard.com/
**What it does:** Kernel-mode VPN with modern crypto and minimal config surface.
**Why it's installed:** Default VPN for the Hyperi internal tier. Replaces OpenVPN 3 as the primary VPN; OpenVPN is now opt-in via the `openvpn` profile (transitional).
**Why this tool:** WireGuard is in-kernel on both Ubuntu and Fedora, dramatically faster than OpenVPN, and the config is a single `/etc/wireguard/*.conf` file. The peer config is supplied by the operator via `wireguard_peer_config` (deliberately not shipped in the repo).

### Wallpaper + avatar (Hyperi branding)

**Upstream:** n/a — branded assets shipped with this repo.
**What it does:** Sets the GNOME desktop wallpaper and default user avatar to the Hyperi-branded assets.
**Why it's installed:** Light-touch visual marker that you're on a Hyperi-managed workstation — useful in screenshots, shared screens, and onboarding.
**Why this tool:** In-repo asset + dconf write, not a third-party tool. Gated on `has_gnome` so it's a no-op on headless hosts. Trivial to skip via `--skip-tags wallpaper,avatar` if desired.

## rust profile

Rust toolchain plus the build-cache + linker stack used across Hyperi's Rust services.

### rustup + cargo (stable toolchain)

**Upstream:** https://rustup.rs/
**What it does:** Manages Rust toolchains (stable/beta/nightly/custom) and installs the cargo package manager.
**Why it's installed:** Every Hyperi Rust service builds against a current stable toolchain; `rustup` is the only supported way to track it.
**Why this tool:** Distro Rust packages are always months behind and frequently break `cargo install` from-source workflows. `rustup` is the upstream-recommended install path and lets you pin per-project toolchains via `rust-toolchain.toml`. Distro `rust`/`rustc`/`cargo`/`clippy`/`rustfmt` packages are removed before rustup install to avoid PATH conflicts.

### bacon

**Upstream:** https://github.com/Canop/bacon
**What it does:** Background Rust code checker — watches sources and re-runs `cargo check`/`clippy`/`test` on change.
**Why it's installed:** Tight feedback loop while editing; noticeably snappier than `cargo-watch`.
**Why this tool:** `bacon` renders diagnostics in a clean TUI with collapsible errors and has explicit support for running different jobs from keybindings. `cargo-watch` still works but is essentially unmaintained.

### cargo-nextest

**Upstream:** https://nexte.st/
**What it does:** Next-gen Rust test runner — parallel, per-test isolation, richer reporting.
**Why it's installed:** Standard test runner for Hyperi Rust projects; CI uses it too, so running it locally matches CI semantics.
**Why this tool:** 2–3x faster than `cargo test` on multi-core machines, reports per-test timings, and handles flaky-test retries cleanly. Drop-in — existing `#[test]` functions work unchanged.

### cargo-deny

**Upstream:** https://github.com/EmbarkStudios/cargo-deny
**What it does:** Lints the dependency graph for bans, license policy, duplicates, and advisories.
**Why it's installed:** Policy gate for dependency hygiene. Enforces the SPDX license allow-list and the RustSec advisory DB.
**Why this tool:** `cargo-deny` rolls up `cargo-audit` + license checking + dupe detection into one config file. CI runs it on every PR.

### cargo-tarpaulin (Linux only)

**Upstream:** https://github.com/xd009642/tarpaulin
**What it does:** Code coverage for Rust (ptrace-based).
**Why it's installed:** Report line/branch coverage on Rust services for the coverage target gates.
**Why this tool:** `tarpaulin` is the most accurate no-rebuild-with-instrumentation option on Linux. `cargo-llvm-cov` is an alternative but requires nightly for branch coverage; tarpaulin stays on stable. Linux-only because it uses `ptrace`; macOS coverage runs through llvm-cov in CI.

### cargo-chef

**Upstream:** https://github.com/LukeMathWalker/cargo-chef
**What it does:** Pre-caches dependency builds for multi-stage Docker image layers.
**Why it's installed:** Shave Docker rebuild time on Rust services by caching a dependency-only layer.
**Why this tool:** Chef is the accepted Rust-in-Docker caching recipe. Without it, any source change invalidates the full cargo build inside the Docker layer.

### cargo-sweep

**Upstream:** https://github.com/holmgr/cargo-sweep
**What it does:** Cleans stale compilation artifacts from `target/` across projects.
**Why it's installed:** Rust `target/` directories balloon quickly on a dev box; `cargo sweep --time 30` reclaims tens of gigabytes regularly.
**Why this tool:** Safer than `rm -rf target/` — keeps recent artifacts to avoid re-downloading + re-compiling. No GC built into cargo itself.

### sccache

**Upstream:** https://github.com/mozilla/sccache
**What it does:** Shared compilation cache that acts as a `rustc`/`cc` wrapper.
**Why it's installed:** Cache incremental builds across projects and across `cargo clean` cycles. Configured as `build.rustc-wrapper` in `~/.cargo/config.toml`.
**Why this tool:** Mozilla's `sccache` is the mature option with local-disk, S3, and GHA cache backends. Dramatically cuts cold-cache rebuild time after switching branches or running `cargo clean`.

### mold (Linux x86_64)

**Upstream:** https://github.com/rui314/mold
**What it does:** Modern linker — drop-in replacement for `ld`/`lld`, 5–10x faster on incremental builds.
**Why it's installed:** Linking is the long tail of Rust incremental builds; mold makes "change one line, rebuild, see result" feel instant.
**Why this tool:** Written by the author of LLVM's `lld` with performance as the explicit goal. Wired in via `rustflags = ["-C", "link-arg=-fuse-ld=mold"]` in the global `~/.cargo/config.toml`. Native x86_64 Linux only — cross-compile targets fall back to BFD.

## iac profile

Infrastructure-as-code: HashiCorp CLI set plus the Kubernetes operator kit.

### Terraform

**Upstream:** https://developer.hashicorp.com/terraform
**What it does:** Declarative infra provisioning — AWS, Azure, GCP, Kubernetes, etc.
**Why it's installed:** The IaC language for every provisioning workflow we maintain.
**Why this tool:** Keeping Terraform (not OpenTofu) for now because all the providers and modules Hyperi uses are still tracking the Terraform releases. Installed from the official HashiCorp repo so the CLI version stays current. If/when OpenTofu achieves provider/module parity for our modules, the switch is a one-line repo change.

### Vault

**Upstream:** https://developer.hashicorp.com/vault
**What it does:** Secrets management — KV, dynamic credentials, PKI, transit encryption.
**Why it's installed:** Client for the Vault server that fronts most internal credentials.
**Why this tool:** Vault is the established secrets backend. The `vault` CLI is the scriptable interface — `openbao` is API-compatible but we still pin the Vault binary to match server capabilities.

### Helm

**Upstream:** https://helm.sh/
**What it does:** Package manager for Kubernetes (templated manifests + release lifecycle).
**Why it's installed:** Required to install and operate most third-party Kubernetes workloads (Argo, cert-manager, external-secrets, etc.).
**Why this tool:** Helm is the de-facto standard; many charts (including the ones we consume) ship only as Helm charts. `helmfile` is not installed here — teams that need it install per-project.

### kubectl

**Upstream:** https://kubernetes.io/docs/reference/kubectl/
**What it does:** Kubernetes CLI — apply manifests, inspect resources, port-forward, exec, logs.
**Why it's installed:** The primary interface to every Kubernetes cluster we run.
**Why this tool:** `kubectl` version is auto-detected from `https://dl.k8s.io/release/stable.txt` at install time so the CLI tracks the latest stable release (Kubernetes' skew policy supports ±1 minor relative to the server).

### k9s

**Upstream:** https://k9scli.io/
**What it does:** Terminal UI for Kubernetes — live resource browsing, drill-down, context switching.
**Why it's installed:** Day-to-day cluster inspection without typing `kubectl get pods -n … -w` loops.
**Why this tool:** k9s is the mature TUI — fast, scriptable keybindings, and integrates with `kubectl` plug-ins. GUI alternatives live in `gui_extras` (Freelens).

### kubectx + kubens

**Upstream:** https://github.com/ahmetb/kubectx
**What it does:** Fast context and namespace switchers for `kubectl`.
**Why it's installed:** Switching between clusters and namespaces is constant; `kubectl config use-context` and `kubectl config set-context --current --namespace` are verbose.
**Why this tool:** `kubectx`/`kubens` are the widely-adopted standalone scripts. `kubie` is a Rust alternative but has narrower ecosystem support.

### minikube

**Upstream:** https://minikube.sigs.k8s.io/
**What it does:** Local single-node Kubernetes cluster in a VM or container.
**Why it's installed:** Spin up an isolated cluster for PR tests without touching a shared environment.
**Why this tool:** Minikube is the upstream-SIG project with the broadest driver support (kvm2, docker, podman, virtualbox). `kind` is also fine and some teams use it; minikube stays as the default because it supports more addons out of the box.

### ArgoCD CLI

**Upstream:** https://argo-cd.readthedocs.io/
**What it does:** Client for ArgoCD GitOps controller — sync apps, inspect resources, trigger rollouts.
**Why it's installed:** ArgoCD is the GitOps controller in the clusters we run; the CLI is how you script it.
**Why this tool:** Official ArgoCD CLI; no third-party alternative worth considering. Installed from GitHub releases directly (distro packages are absent).

### dive

**Upstream:** https://github.com/wagoodman/dive
**What it does:** Interactive Docker image layer explorer — shows file diffs per layer, wasted space, image efficiency.
**Why it's installed:** Image-size debugging (usually on Rust services where a sloppy Dockerfile adds hundreds of MB).
**Why this tool:** Dive is the only CLI that does this well. `docker image history` is useful but shows layers without per-file diffs.

## gui_extras profile

Optional desktop developer GUIs. Skipped on headless hosts (gated on `has_gnome`).

### Freelens

**Upstream:** https://github.com/freelensapp/freelens
**What it does:** GUI for Kubernetes clusters — resource browsing, log tailing, shell-in-pod, metrics.
**Why it's installed:** Visual alternative to k9s for multi-cluster browsing and quick triage. Useful during incident calls where you want to share a screen, not a terminal.
**Why this tool:** Freelens is the community-maintained continuation of the original OpenLens project after OpenLens was effectively abandoned. Lens Desktop (the commercial successor) requires a Mirantis account; Freelens is fully FOSS and account-free. Installed via Flatpak (Flathub) so it stays sandboxed and tracks upstream releases.

### Bruno

**Upstream:** https://www.usebruno.com/
**What it does:** Git-native, local-first API client for REST/GraphQL/gRPC/WebSocket.
**Why it's installed:** API exploration and testing without leaking requests to a cloud service.
**Why this tool:** Chosen over Postman and Insomnia because Bruno is truly local-first with no account requirement, stores collections as plain-text `.bru` files suitable for version control, and has no telemetry. Postman now requires an account even for local use and pushes cloud sync; Insomnia's post-Kong-acquisition direction follows the same pattern.

Install path note: upstream's apt repo (`https://usebruno.jfrog.io/artifactory/bruno-apt`) was decommissioned in early 2026, so Ubuntu installs via the official snap (`snap install bruno`). Fedora continues to use the Flathub flatpak.

### Podman Desktop

**Upstream:** https://podman-desktop.io/
**What it does:** GUI for Podman (and Docker) — manage containers, pods, images, volumes, compose stacks.
**Why it's installed:** Visual container management for users who prefer a GUI over `docker ps`/`podman ps`.
**Why this tool:** Podman Desktop is FOSS, handles both Podman and Docker Engine backends, and has first-class Kubernetes integration (generate pod manifests, play kube). Docker Desktop on Linux is licensed and fully containerised inside a VM, which is overkill given Docker Engine already runs natively. Installed via Flathub.

### DBeaver Community

**Upstream:** https://dbeaver.io/
**What it does:** Universal SQL database client (PostgreSQL, MySQL, ClickHouse, SQLite, and more).
**Why it's installed:** Day-to-day SQL exploration and schema inspection against the internal Postgres and ClickHouse instances.
**Why this tool:** DBeaver Community Edition is FOSS, covers every JDBC-speaking database the team touches, and the UI is consistent across backends. The commercial "DBeaver PRO" tier adds NoSQL and cloud-warehouse connectors that we don't need here. `pgcli` and `clickhouse-client` cover CLI use from the developer tier.

### lazygit

**Upstream:** https://github.com/jesseduffield/lazygit
**What it does:** Terminal UI for git — staging, committing, rebasing, cherry-pick, log inspection.
**Why it's installed:** Fast keyboard-driven git client for users who don't want to memorise all of git's porcelain.
**Why this tool:** `lazygit` is the mature Go-based TUI — single binary, works over SSH, handles interactive rebase cleanly (one of git's more awkward commands from the CLI). `tig` is a lighter alternative but read-mostly; `lazygit` has full edit capability.

## openvpn profile (transitional)

Legacy OpenVPN 3 stack. Opt-in only; `core` now defaults to WireGuard. Scheduled
for removal once the internal WireGuard migration completes.

This profile exists so operators who still have OpenVPN-only endpoints can install the client stack until those endpoints are cut over. New installs should prefer the WireGuard setup included in `core`.

### openvpn3 CLI

**Upstream:** https://openvpn.net/openvpn-3-linux/
**What it does:** Modern OpenVPN 3 client CLI — imports `.ovpn` profiles, manages sessions via a D-Bus daemon.
**Why it's installed:** Legacy OpenVPN endpoints during the WireGuard migration window.
**Why this tool:** OpenVPN 3 supersedes the older `openvpn` package — faster, runs as an unprivileged daemon, and supports session-based profile management. Installed from the official OpenVPN repos (Ubuntu) / packaged via dnf (Fedora).

### openvpn3-indicator (Ubuntu only)

**Upstream:** https://github.com/OpenVPN/openvpn3-indicator (community GTK tray)
**What it does:** GNOME/GTK status-tray indicator for openvpn3 sessions.
**Why it's installed:** Gives a visible up/down indicator on the desktop — useful because openvpn3 sessions aren't managed by NetworkManager and don't surface in the standard networking menu.
**Why this tool:** Only maintained tray integration for openvpn3 on modern GNOME. Ubuntu-only because the packaging targets GNOME on Ubuntu; Fedora users can run `openvpn3 sessions-list` from the shell.

### netcfg systemd-resolved fix

**Upstream:** n/a — in-repo workaround documented at https://community.openvpn.net/openvpn/wiki/OpenVPN3LinuxDNSSetup
**What it does:** Drops a config snippet so openvpn3's `netcfg` agent pushes DNS into systemd-resolved instead of trying to rewrite `/etc/resolv.conf` directly.
**Why it's installed:** On Ubuntu 24.04 + Fedora 42, systemd-resolved owns `/etc/resolv.conf`. Without this fix, openvpn3 reverts DNS to public resolvers and internal names fail to resolve over the VPN.
**Why this tool:** This is a config snippet, not a tool — the canonical workaround recommended by OpenVPN upstream. Idempotent; applied only on Linux.

**Removal plan:** this profile is flagged as transitional. Once the remaining OpenVPN-only endpoints are migrated to WireGuard, the `openvpn` profile and the `--profile core,openvpn` invocation will be removed in a follow-up release.

## Opt-out variables

Centralised in `ansible/inventories/localhost/group_vars/all.yml`. All default to `true`
(except `wireguard_peer_config`, which is unset by design).

| Variable | Default | Effect |
|----------|---------|--------|
| `install_bitwarden` | `true` | Bitwarden desktop password manager |
| `install_onlyoffice` | `true` | OnlyOffice desktop editors |
| `install_brave` | `true` | Brave browser |
| `install_slack` | `true` | Slack desktop (core tier only) |
| `install_linear` | `true` | Linear CLI (core tier only) |
| `wireguard_peer_config` | unset | Path to a WireGuard peer config file; operators set this |

Override examples:

    ./install.sh --profile developer --extra-vars "install_onlyoffice=false"
    ./install.sh --profile core --extra-vars "install_slack=false install_linear=false"
