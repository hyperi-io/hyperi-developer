#!/bin/bash
# ============================================================================
# install.sh - DFE Developer Environment Bootstrap Script
# ============================================================================
# This script bootstraps the DFE developer environment by:
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
#   --branch BRANCH      Git branch to use (default: main)
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
BLUE='\033[0;34m'
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
  --corporate          Shortcut: HyperI staff workstation defaults
                       (generic dev + HyperI org tools, no IaC, no langs)
                       Equivalent to:
                       --tags developer,developer-gui,corporate,corporate-gui,cosmetic
  --list-apps          Print every per-app sub-tag (slack, vscode, claude, etc.)
                       for granular --tags X selection
  --help               Show this help message

NOTE:
  The role/tag taxonomy is being refactored — see
  docs/ROLE-TASK-MAPPING.md for the target structure (per-role + per-app
  tags, generic dev base + opt-in HyperI sections).

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
    ./install.sh --corporate --tags developer-rust

  HyperI SRE workstation:
    ./install.sh --corporate --tags infrastructure,infrastructure-gui

  Install with Australian region (locale, formats, spell-check):
    ./install.sh --region au

  Install RDP support for remote desktop access:
    ./install.sh --tags rdp

  Dry-run to see what would change:
    ./install.sh --check

NOTES:
  - winlike (Windows-style GNOME taskbar) is the default UI mode
  - If both winlike and maclike are specified, winlike wins
  - RDP configures GNOME Remote Desktop with default credentials (dfe/dfe)
  - Use --tags-exclude to skip specific tags within a chosen group
  - Use --list-apps to see every per-app sub-tag for granular installs
EOF
    exit 0
}

list_apps() {
    cat << 'EOF'
Per-app sub-tags — pass via --tags <name> to install just that one app.

Generic dev base (developer):
    apparmor          Ubuntu AppArmor userns fix
    repository        OS repo mirrors / fastestmirror
    docker            Docker (Engine on Linux, CLI on macOS — no Desktop)
    utilities         CLI utilities (htop, ripgrep, fd, fzf, jq, yq, ...)
    git               Latest Git via PPA / Fedora / brew
    region            Locale + hunspell (gated by --region too)
    chrome            Google Chrome  (opt-in via --tags chrome)
    brave             Brave browser  (opt-in via --tags brave)
    avatar            User avatar    (opt-in via --tags avatar)

Generic dev GUI (developer-gui):
    desktop           GNOME / ubuntu-desktop-minimal install if missing
    vscode            Visual Studio Code
    ghostty           Ghostty terminal + JetBrains Mono font
    dbeaver           DBeaver Community DB GUI

Languages (developer-<lang>):
    rust              rustup + cargo + sccache + mold + cargo-sweep
    uv                UV (Python package manager)
    go                Go toolchain + gopls + dlv
    c-tools           C/C++ build tools
    nodejs            Node.js LTS + pnpm
    typescript        typescript + tsx + ts-node (depends on nodejs)
    cursor            Cursor editor (in developer-typescript-gui)

Infrastructure (infrastructure):
    cloud             HashiCorp tools + AWS CLI v2
    azure             Azure CLI
    gcloud            Google Cloud CLI
    k8s               kubectl + helm + k9s + minikube
    vector            Vector data pipeline tool
    lens              K8s desktop client (in infrastructure-gui)

Corporate / HyperI-specific (corporate, corporate-gui):
    auto-updates      unattended-upgrades / dnf-automatic
    bash-history      bash history auto-commit
    act               Run GitHub Actions locally
    claude            Claude Code CLI
    gitleaks          Secret scanner
    openvpn           OpenVPN 3 client
    telemetry-disable Disable Ubuntu Pro/ESM ads + telemetry
    slack             Slack desktop
    onlyoffice        OnlyOffice Desktop Editors
    nemo              Nemo file manager (replaces Nautilus)
    desktop-cleanup   Hide duplicate apps, dedupe Flatpak/apt
    gnome-extensions  GNOME extensions (Astra Monitor etc.)
    office            Office suite tasks

Targeted deployment:
    rdp               GNOME Remote Desktop (RDP server on port 3389)
    vm                VM guest optimisations (QEMU agent etc.)

macOS-only:
    bash-modern       Modern Bash via Homebrew (does NOT chsh)

Composability examples:
    ./install.sh --tags slack                    Just Slack
    ./install.sh --tags developer-gui            All of developer-gui
    ./install.sh --tags vscode,ghostty           VS Code + Ghostty only
    ./install.sh --corporate --tags developer-rust  Corporate + Rust
EOF
    exit 0
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
            if [[ -n "$ANSIBLE_TAGS" ]]; then
                # Append to existing tags
                CURRENT_TAGS="${ANSIBLE_TAGS#--tags }"
                ANSIBLE_TAGS="--tags ${CURRENT_TAGS},$2"
            else
                ANSIBLE_TAGS="--tags $2"
            fi
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
        --corporate)
            # HyperI staff workstation default: generic dev + HyperI org tools.
            # Excludes infrastructure (SRE-leaning, opt-in via --tags) and
            # specific languages (too personal — add --tags developer-rust etc.).
            CORPORATE_TAGS="developer,developer-gui,corporate,corporate-gui,cosmetic"
            if [[ -n "$ANSIBLE_TAGS" ]]; then
                CURRENT_TAGS="${ANSIBLE_TAGS#--tags }"
                ANSIBLE_TAGS="--tags ${CURRENT_TAGS},${CORPORATE_TAGS}"
            else
                ANSIBLE_TAGS="--tags ${CORPORATE_TAGS}"
            fi
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
    # Map short codes to full locale strings
    case "${REGION_ARG,,}" in
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
    if [[ -n "$ANSIBLE_TAGS" ]]; then
        CURRENT_TAGS="${ANSIBLE_TAGS#--tags }"
        ANSIBLE_TAGS="--tags ${CURRENT_TAGS},region"
    else
        ANSIBLE_TAGS="--tags region"
    fi

    # Pass desktop_region as extra var
    ANSIBLE_EXTRA_VARS="-e desktop_region=${DESKTOP_REGION}"
    print_info "Region: ${DESKTOP_REGION}"
fi

# Detect operating system
print_info "Detecting operating system..."

if [[ -f /etc/os-release ]]; then
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
TEMP_ANSIBLE_DIR=$(mktemp -d -t dfe-ansible.XXXXXX)
ANSIBLE_BIN="$TEMP_ANSIBLE_DIR/bin/ansible-playbook"

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
    rm -rf "$TEMP_ANSIBLE_DIR"
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
    curl -fsSL "$TARBALL_URL" -o /tmp/dfe-developer.tar.gz || {
        print_error "Failed to download repository tarball from branch: $GIT_BRANCH"
        exit 1
    }

    # Extract only the ansible directory
    # Note: Branch name slashes become hyphens in tarball archive directory
    ARCHIVE_DIR="dfe-developer-${GIT_BRANCH//\//-}"
    print_info "Extracting ansible directory from ${ARCHIVE_DIR}..."
    tar -xzf /tmp/dfe-developer.tar.gz --strip-components=1 "${ARCHIVE_DIR}/ansible" || {
        print_error "Failed to extract ansible directory from ${ARCHIVE_DIR}"
        rm -f /tmp/dfe-developer.tar.gz
        exit 1
    }

    # Cleanup
    rm -f /tmp/dfe-developer.tar.gz

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

# shellcheck disable=SC2086
"$ANSIBLE_BIN" \
    playbooks/main.yml \
    -i inventories/localhost/inventory.yml \
    $ANSIBLE_CHECK \
    $ANSIBLE_TAGS \
    $ANSIBLE_SKIP_TAGS_ARG \
    $ANSIBLE_EXTRA_VARS
ANSIBLE_EXIT_CODE=$?

# Clean up temporary Ansible venv
print_info "Cleaning up temporary Ansible venv..."
rm -rf "$TEMP_ANSIBLE_DIR"

if [[ $ANSIBLE_EXIT_CODE -ne 0 ]]; then
    print_error "Ansible playbook failed"
    exit 1
fi

print_success "DFE Developer Environment installation complete!"
print_info ""
print_info "Next steps:"
print_info "1. Log out and back in for group memberships to take effect (Docker)"
print_info "2. Verify installation: docker --version, kubectl version, python3 --version"
print_info "3. Configure your tools (Git, AWS CLI, Azure CLI)"
