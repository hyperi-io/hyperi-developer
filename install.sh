#!/bin/bash
# ============================================================================
# install.sh - Hyperi Developer Environment Bootstrap Script
# ============================================================================
# This script bootstraps the Hyperi developer environment by:
# 1. Detecting the operating system
# 2. Installing Ansible using the native package manager
# 3. Running the Ansible playbook to configure the system
#
# USAGE:
#   ./install.sh [OPTIONS]
#
# OPTIONS:
#   --check              Run in check mode (dry-run, no changes)
#   --tags TAGS          Include specific tags (alias for --tags-include)
#   --tags-include TAGS  Include specific tags to run (comma-separated)
#   --tags-exclude TAGS  Exclude specific tags from running (comma-separated)
#   --region REGION      Apply regional settings (e.g. au, en_AU.UTF-8)
#   --pinned             Pin manual binaries to CI-exact versions (default: latest)
#   --branch BRANCH      Git branch to use (default: main)
#   Personas: --soe / --contributor / --full-stack / --infra / --languages [list]
#   --help               Show this help message
#
# SUPPORTED PLATFORMS:
#   - Ubuntu 24.04 LTS and later
#   - Fedora 42 and later
#   - macOS (Homebrew)
#
# LICENSE:
#   Licensed under the Apache License, Version 2.0
#   See LICENSE file for full license text
# ============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Output functions
print_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
print_success() { echo -e "${GREEN}[OK]${NC} $1"; }
print_info() { echo -e "[INFO] $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }

show_help() {
    cat << 'EOF'
Usage: ./install.sh [OPTIONS]

OPTIONS:
  --check              Run in check mode (dry-run, no changes)
  --tags TAGS          Include specific tags (alias for --tags-include)
  --tags-include TAGS  Include specific tags to run (comma-separated)
  --tags-exclude TAGS  Exclude specific tags from running (comma-separated)
  --branch BRANCH      Git branch to use (default: main)
  --region REGION      Apply regional settings (e.g. au, en_AU.UTF-8)
  --pinned             Reproducible mode: pin the manual-binary tools to the
                       exact versions in group_vars (mirrors hyperi-ci) instead
                       of latest. Latest is the default.
  --soe                Shortcut: HyperI staff workstation defaults
                       (generic dev + CI toolchain + HyperI org policy;
                       no IaC, no language toolchains)
                       Equivalent to:
                       --tags developer-gui,soe,soe-gui,winlike
  --contributor        Shortcut: for outside contributors to HyperI products.
                       The dev base + the toolchain our CI runs, and none of
                       our org policy (no VPN, telemetry, branding, Slack).
                       Equivalent to: --tags contributor
  --full-stack         App dev, front-to-back: clean base + GUI editors + node +
                       typescript + python + infrastructure (kubectl/k9s).
  --infra              SRE / platform box: clean base + infrastructure
                       (cloud, IaC, k8s, the data group).
  --languages [LIST]   Language toolchains. Bare installs them all; or pass a
                       comma list, e.g. --languages rust,go
                       (rust/go/python/node/typescript/c).
  --list-apps          Print every per-app / per-group sub-tag (slack, vscode,
                       data, vpn-clients, ...) for granular --tags X selection
  --help               Show this help message

NOTE:
  Run --list-apps for the full per-role and per-app tag list.

  There is no longer a kitchen-sink shortcut. Pick what you want via
  --tags. Default (no flags) is the lightweight CLI dev base.

EXAMPLES:

  Default installation (lightweight CLI dev base):
    ./install.sh

  Generic dev base + GUI editors + Python:
    ./install.sh --tags developer,developer-gui,developer-python

  Just Slack and nothing else:
    ./install.sh --tags slack

  HyperI staff machine + Rust:
    ./install.sh --soe --tags developer-rust

  HyperI SRE workstation:
    ./install.sh --soe --tags infrastructure

  Outside contributor working on a HyperI product:
    ./install.sh --contributor

  Install with Australian region (locale, formats, spell-check):
    ./install.sh --region au

  SRE / platform workstation:
    ./install.sh --infra

  Rust + Go toolchains only:
    ./install.sh --languages rust,go

  Reproducible (CI-exact) install:
    ./install.sh --contributor --pinned

  Install the RDP server (GNOME Remote Desktop) for inbound access:
    ./install.sh --tags rdp-server

  Dry-run to see what would change:
    ./install.sh --check

NOTES:
  - winlike (Windows-style GNOME taskbar) is the default UI mode
  - If both winlike and maclike are specified, winlike wins
  - RDP configures GNOME Remote Desktop with a per-host random password (shown once)
  - Use --tags-exclude to skip specific tags within a chosen group
  - Use --list-apps to see every per-app sub-tag for granular installs
EOF
    exit 0
}

list_apps() {
    cat << 'EOF'
Per-app / per-group sub-tags - pass via --tags <name> to install just that set.

Generic dev base (developer) - the additive default:
    apparmor          Ubuntu AppArmor userns fix
    repository        OS repo mirrors / fastestmirror
    docker            Docker (Engine on Linux, CLI on macOS - no Desktop)
    utilities         CLI utilities (htop, ripgrep, fd, fzf, jq, yq, ...)
    git               Latest Git via PPA / Fedora / brew
    region            Locale + hunspell (gated by --region too)
    astral            Astral suite: uv + ruff + ty (base component)
    chrome            Google Chrome        (opt-in / soe)
    brave             Brave browser        (opt-in / soe)
    avatar            User avatar          (opt-in / soe)
    removals          Remove retired tools (opt-in / soe only)
    update_command    hyperi-update command + GUI launcher (opt-in / soe)
    admin-scripts     HyperI fleet admin scripts (opt-in / soe only)

Generic dev GUI (developer-gui):
    desktop           GNOME / ubuntu-desktop-minimal install if missing
    vscode            Visual Studio Code
    ghostty           Ghostty terminal + JetBrains Mono font
    dbeaver           DBeaver Community DB GUI

Languages (developer-<lang>; --languages [list] or developer-languages for all):
    developer-rust        rustup + cargo tools + protoc/librdkafka build deps
    developer-go          Go + gopls, dlv, golangci-lint, gosec, govulncheck
    developer-python      mypy (opt-in; ruff/ty ship in the base astral suite)
    developer-node        Node.js LTS + npm + pnpm/corepack
    developer-typescript  typescript + tsx + ts-node (pulls developer-node)
    developer-c           C/C++ build tools

Infrastructure (infrastructure):
    cloud             OpenTofu, OpenBao, AWS CLI v2, checkov
    azure             Azure CLI
    gcloud            Google Cloud CLI
    k8s               kubectl, helm, kubectx/kubens, k9s, kind, argocd,
                      kustomize, kubeconform, kube-linter, dive
    data              data group: clickhouse-client, rpk, valkey-cli, vector

Contributor (contributor) - to work ON a HyperI product, no org policy:
    hyperi-ci         hyperi-ci + semgrep, alint
    gitleaks          Secret scanner
    trivy             Vuln / IaC / secret scanner
    hadolint          Dockerfile linter
    pip-audit         Python dependency audit
    yamllint          YAML linter
    ansible-lint      Ansible linter
    pre-commit        pre-commit runner
    actionlint        GitHub Actions linter
    vulture           Dead-code finder
    typos             Source spell-checker
    maid              Mermaid diagram validator
    osv-scanner       OSV vulnerability scanner
    act               Run GitHub Actions locally

HyperI SOE (soe, soe-gui) - org policy, includes everything above:
    auto-updates      unattended-upgrades / dnf-automatic
    update-timer      Weekly hyperi-update systemd timer
    bash-history      bash history auto-commit
    claude            Claude Code CLI
    forgejo/codeberg  tea (Forgejo/Gitea CLI)
    colima            macOS container daemon + Apple container (macOS only)
    disk-attach       Sudo tool to mount a newly attached disk
    telemetry-disable Disable Ubuntu Pro/ESM ads + telemetry
    slack             Slack desktop
    office            LibreOffice org office suite
    nemo              Nemo file manager (replaces Nautilus)
    desktop-cleanup   Hide duplicate apps, dedupe Flatpak/apt
    gnome-extensions  GNOME extensions (winlike / maclike)

Groups / client bundles (own tag; soe pulls them by default):
    vpn-clients       OpenVPN 3 + WireGuard + Tunnelblick (macOS)
      openvpn         just OpenVPN 3
      wireguard       just WireGuard
      tunnelblick     just Tunnelblick (macOS)
    rdp-client        Remmina (Linux) / Thincast (macOS)

Targeted deployment:
    rdp-server        GNOME Remote Desktop (RDP server on port 3389)
    vm                VM guest optimisations (QEMU agent etc.)

macOS-only:
    bash-modern       Modern Bash via Homebrew (does NOT chsh)

Composability examples:
    ./install.sh --tags slack                    Just Slack
    ./install.sh --tags data                     The data-tools group
    ./install.sh --tags vscode,ghostty           VS Code + Ghostty only
    ./install.sh --soe --languages rust,go       SOE + Rust + Go
    ./install.sh --infra --pinned                SRE box, CI-exact versions
EOF
    exit 0
}

# Append comma-separated tags to ANSIBLE_TAGS, keeping the single --tags prefix.
# Used by --tags, --soe, --contributor and --region so the join logic lives once.
append_tags() {
    if [[ -n "$ANSIBLE_TAGS" ]]; then
        ANSIBLE_TAGS="--tags ${ANSIBLE_TAGS#--tags },$1"
    else
        ANSIBLE_TAGS="--tags $1"
    fi
}

# Append one `key=value` Ansible extra var, so --pinned and --region compose
# instead of clobbering each other.
append_extra_var() {
    if [[ -n "$ANSIBLE_EXTRA_VARS" ]]; then
        ANSIBLE_EXTRA_VARS="$ANSIBLE_EXTRA_VARS -e $1"
    else
        ANSIBLE_EXTRA_VARS="-e $1"
    fi
}

# Parse arguments
ANSIBLE_CHECK=""
ANSIBLE_TAGS=""
ANSIBLE_SKIP_TAGS=""
ANSIBLE_EXTRA_VARS=""
GIT_BRANCH="main"

while [[ $# -gt 0 ]]; do
    case $1 in
        --check)
            ANSIBLE_CHECK="--check"
            shift
            ;;
        --tags|--tags-include)
            append_tags "$2"
            shift 2
            ;;
        --tags-exclude)
            if [[ -n "$ANSIBLE_SKIP_TAGS" ]]; then
                ANSIBLE_SKIP_TAGS="$ANSIBLE_SKIP_TAGS,$2"
            else
                ANSIBLE_SKIP_TAGS="$2"
            fi
            shift 2
            ;;
        --branch)
            GIT_BRANCH="$2"
            shift 2
            ;;
        --region)
            REGION_ARG="$2"
            shift 2
            ;;
        --soe)
            # HyperI staff workstation default: generic dev + the CI toolchain
            # + HyperI org policy. Excludes infrastructure (SRE-leaning, opt-in
            # via --tags) and specific languages (too personal -- add --tags
            # developer-rust etc.).
            #
            # soe pulls contributor pulls developer via meta dependencies, so
            # naming soe here is enough; the others come with it.
            #
            # winlike gives the default GNOME taskbar -- soe-gui's UI-mode task
            # only fires when winlike or maclike is in the run tags, so without
            # it a --soe box gets the GUI apps but a bare shell. Spell the tags
            # out manually (drop --soe) if you want maclike instead.
            SOE_TAGS="developer-gui,soe,soe-gui,winlike"
            append_tags "$SOE_TAGS"
            shift
            ;;
        --contributor)
            # For someone outside HyperI working ON a HyperI product: the dev
            # base plus the toolchain our CI runs, and none of our org policy.
            CONTRIBUTOR_TAGS="contributor"
            append_tags "$CONTRIBUTOR_TAGS"
            shift
            ;;
        --full-stack)
            # App dev, front-to-back: clean base + GUI editors + node/typescript/
            # python + infrastructure CLIs. Resolves via the full-stack meta-role.
            append_tags "full-stack"
            shift
            ;;
        --infra)
            # SRE / platform box: clean base + infrastructure (cloud, IaC, k8s,
            # data). Resolves via the infra meta-role.
            append_tags "infra"
            shift
            ;;
        --languages)
            # Optional comma list: `--languages rust,go` installs just those
            # toolchains; bare `--languages` installs them all (the
            # developer-languages meta-role). Bash 3.2 safe (macOS bootstrap).
            if [[ -n "${2:-}" && "$2" != -* ]]; then
                LANG_TAGS=""
                IFS=',' read -ra _langs <<< "$2"
                for _l in "${_langs[@]}"; do
                    _l="$(printf '%s' "$_l" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
                    [[ -z "$_l" ]] && continue
                    case "$_l" in
                        rs|rust)          _role="developer-rust" ;;
                        go|golang)        _role="developer-go" ;;
                        py|python)        _role="developer-python" ;;
                        js|node|nodejs)   _role="developer-node" ;;
                        ts|typescript)    _role="developer-typescript" ;;
                        c|cpp|c++|c-tools) _role="developer-c" ;;
                        *)                _role="developer-$_l" ;;
                    esac
                    if [[ -n "$LANG_TAGS" ]]; then
                        LANG_TAGS="$LANG_TAGS,$_role"
                    else
                        LANG_TAGS="$_role"
                    fi
                done
                append_tags "$LANG_TAGS"
                shift 2
            else
                append_tags "developer-languages"
                shift
            fi
            ;;
        --pinned)
            # Opt-in reproducible mode: pin the manual-binary tools to the exact
            # versions in inventories/localhost/group_vars/all.yml (which mirrors
            # hyperi-ci) instead of /releases/latest. Latest stays the default.
            append_extra_var "hyperi_pinned=true"
            shift
            ;;
        --list-apps)
            list_apps
            ;;
        --help|-h)
            show_help
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Handle winlike/maclike priority: winlike wins (it's the default UI mode).
# If both are specified, drop maclike from tags so the taskbar stays winlike.
if [[ "$ANSIBLE_TAGS" == *"maclike"* ]] && [[ "$ANSIBLE_TAGS" == *"winlike"* ]]; then
    print_info "Both winlike and maclike specified - using winlike (winlike is default and wins)"
    ANSIBLE_TAGS="${ANSIBLE_TAGS//,maclike/}"
    ANSIBLE_TAGS="${ANSIBLE_TAGS//maclike,/}"
    ANSIBLE_TAGS="${ANSIBLE_TAGS//maclike/}"
fi

# Handle --region: resolve short codes to full locale, add tag and extra var
if [[ -n "${REGION_ARG:-}" ]]; then
    # Map short codes to full locale strings. Lowercase via tr, not ${x,,} --
    # that is a Bash 4+ expansion and macOS ships Bash 3.2, and this bootstrap
    # runs before any newer bash is installed.
    REGION_LC=$(printf '%s' "$REGION_ARG" | tr '[:upper:]' '[:lower:]')
    case "$REGION_LC" in
        au|en_au|en_au.utf-8|en_au.utf8)  DESKTOP_REGION="en_AU.UTF-8" ;;
        us|en_us|en_us.utf-8|en_us.utf8)  DESKTOP_REGION="en_US.UTF-8" ;;
        gb|en_gb|en_gb.utf-8|en_gb.utf8)  DESKTOP_REGION="en_GB.UTF-8" ;;
        nz|en_nz|en_nz.utf-8|en_nz.utf8)  DESKTOP_REGION="en_NZ.UTF-8" ;;
        *)
            # Accept any value as-is (assume full locale string)
            DESKTOP_REGION="${REGION_ARG}"
            ;;
    esac

    # Add region tag
    append_tags "region"

    # Pass desktop_region as extra var (append so --pinned survives)
    append_extra_var "desktop_region=${DESKTOP_REGION}"
    print_info "Region: ${DESKTOP_REGION}"
fi

# Detect operating system
print_info "Detecting operating system..."

if [[ -f /etc/os-release ]]; then
    # shellcheck source=/dev/null
    . /etc/os-release
    OS_FAMILY=""

    case "$ID" in
        fedora)
            OS_FAMILY="fedora"
            print_info "Detected: Fedora $VERSION_ID"
            ;;
        ubuntu)
            OS_FAMILY="ubuntu"
            print_info "Detected: Ubuntu $VERSION_ID"
            ;;
        *)
            print_error "Unsupported Linux distribution: $ID"
            print_info "Supported: Ubuntu 24.04+, Fedora 42+, macOS"
            exit 1
            ;;
    esac
elif [[ "$(uname)" == "Darwin" ]]; then
    OS_FAMILY="macos"
    print_info "Detected: macOS $(sw_vers -productVersion)"
else
    print_error "Unable to detect operating system"
    exit 1
fi

# Check for sudo access
print_info "Verifying sudo access..."
if ! sudo -n true 2>/dev/null; then
    print_warning "Passwordless sudo not configured"
    print_info "You will be prompted for your password when needed"
    sudo -v || {
        print_error "Sudo access required"
        exit 1
    }
fi
print_success "Sudo access verified"

# Install latest Ansible in temporary Python venv (isolated from OS)
# This avoids circular dependency if playbook updates system Ansible
# The venv is created fresh each run and cleaned up after completion
TEMP_ANSIBLE_DIR=$(mktemp -d -t hyperi-ansible.XXXXXX)
ANSIBLE_BIN="$TEMP_ANSIBLE_DIR/bin/ansible-playbook"
# Remove the temp venv on ANY exit (success, failure, or early error). Without
# this, set -e aborts the script the instant the playbook fails, so a manual
# cleanup line below would never run and would leak the ~100s-MB venv in $TMPDIR.
trap 'rm -rf "$TEMP_ANSIBLE_DIR"' EXIT

print_info "Creating temporary Ansible environment (isolated from OS)..."

# Ensure Python 3 and curl are installed (prerequisites)
case "$OS_FAMILY" in
    fedora)
        if ! command -v python3 &>/dev/null || ! command -v curl &>/dev/null; then
            sudo dnf install -y python3 python3-pip curl || {
                print_error "Failed to install Python 3 or curl"
                exit 1
            }
        fi
        ;;
    ubuntu)
        if ! command -v python3 &>/dev/null || ! command -v curl &>/dev/null; then
            sudo apt-get update -qq
            sudo apt-get install -y python3 python3-pip python3-venv curl || {
                print_error "Failed to install Python 3 or curl"
                exit 1
            }
        elif ! python3 -m venv --help &>/dev/null; then
            # Python exists but venv module missing
            sudo apt-get update -qq
            sudo apt-get install -y python3-venv || {
                print_error "Failed to install python3-venv"
                exit 1
            }
        fi
        ;;
    macos)
        if ! command -v python3 &>/dev/null; then
            print_error "Python 3 not found. Install from https://www.python.org or use: brew install python3"
            exit 1
        fi
        # curl pre-installed on macOS
        ;;
esac

# Create temporary Python venv
python3 -m venv "$TEMP_ANSIBLE_DIR" || {
    print_error "Failed to create Python venv"
    exit 1
}

# Install latest Ansible + ansible-lint via pip
print_info "Installing latest Ansible + ansible-lint via pip..."
"$TEMP_ANSIBLE_DIR/bin/pip" install --upgrade pip setuptools wheel >/dev/null 2>&1
"$TEMP_ANSIBLE_DIR/bin/pip" install ansible ansible-lint >/dev/null 2>&1 || {
    print_error "Failed to install Ansible + ansible-lint via pip"
    exit 1
}

ANSIBLE_VERSION=$("$TEMP_ANSIBLE_DIR/bin/ansible" --version | head -1 | awk '{print $2}')
ANSIBLE_LINT_VERSION=$("$TEMP_ANSIBLE_DIR/bin/ansible-lint" --version 2>/dev/null | head -1 | awk '{print $2}')
print_success "Ansible $ANSIBLE_VERSION + ansible-lint $ANSIBLE_LINT_VERSION installed (temporary venv)"

# Determine script directory and check for ansible directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

# Check if ansible directory exists, clone if not
if [[ ! -d "ansible" ]]; then
    print_warning "ansible/ directory not found"
    print_info "Cloning ansible directory from repository (branch: $GIT_BRANCH)..."

    # Download GitHub tarball (no git required)
    TARBALL_URL="https://github.com/hyperi-io/hyperi-developer/archive/refs/heads/${GIT_BRANCH}.tar.gz"

    print_info "Downloading from $TARBALL_URL..."
    curl -fsSL "$TARBALL_URL" -o /tmp/hyperi-developer.tar.gz || {
        print_error "Failed to download repository tarball from branch: $GIT_BRANCH"
        exit 1
    }

    # Extract only the ansible directory
    # Note: Branch name slashes become hyphens in tarball archive directory
    ARCHIVE_DIR="hyperi-developer-${GIT_BRANCH//\//-}"
    print_info "Extracting ansible directory from ${ARCHIVE_DIR}..."
    tar -xzf /tmp/hyperi-developer.tar.gz --strip-components=1 "${ARCHIVE_DIR}/ansible" || {
        print_error "Failed to extract ansible directory from ${ARCHIVE_DIR}"
        rm -f /tmp/hyperi-developer.tar.gz
        exit 1
    }

    # Cleanup
    rm -f /tmp/hyperi-developer.tar.gz

    print_success "Ansible directory downloaded successfully"
fi

# Build skip-tags argument if any
ANSIBLE_SKIP_TAGS_ARG=""
if [[ -n "$ANSIBLE_SKIP_TAGS" ]]; then
    ANSIBLE_SKIP_TAGS_ARG="--skip-tags $ANSIBLE_SKIP_TAGS"
fi

# Run Ansible playbook using temp venv Ansible
print_info "Running Ansible playbook (using isolated venv Ansible)..."
print_info "Command: $ANSIBLE_BIN playbooks/main.yml -i inventories/localhost/inventory.yml $ANSIBLE_CHECK $ANSIBLE_TAGS $ANSIBLE_SKIP_TAGS_ARG $ANSIBLE_EXTRA_VARS"

cd ansible || exit 1

# The EXIT trap set above removes the temp venv on any outcome. Run the
# playbook inside the `if` condition so set -e does not abort before we can
# report a friendly failure (and the trap still fires on exit).
# shellcheck disable=SC2086
if ! "$ANSIBLE_BIN" \
    playbooks/main.yml \
    -i inventories/localhost/inventory.yml \
    $ANSIBLE_CHECK \
    $ANSIBLE_TAGS \
    $ANSIBLE_SKIP_TAGS_ARG \
    $ANSIBLE_EXTRA_VARS; then
    print_error "Ansible playbook failed"
    exit 1
fi

print_success "Hyperi Developer Environment installation complete!"
print_info ""
print_info "Next steps:"
print_info "1. Log out and back in for group memberships to take effect (Docker)"
print_info "2. Verify installation: docker --version, kubectl version, python3 --version"
print_info "3. Configure your tools (Git, AWS CLI, Azure CLI)"
