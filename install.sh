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
#   --profile PROFILE    Profiles to install (comma-separated: developer, core,
#                        rust, iac, gui_extras, openvpn, all). See --help for details.
#   --tags TAGS          Ad-hoc Ansible tags (overrides --profile if both given)
#   --tags-exclude TAGS  Exclude specific tags from running (comma-separated)
#   --core               DEPRECATED — alias for --profile core,rust,iac
#   --all                DEPRECATED — alias for --profile core,all
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

# ----- Profile definitions -----
declare -A VALID_PROFILES=(
    [developer]="developer"
    [core]="core"
    [rust]="rust"
    [iac]="iac"
    [gui_extras]="gui_extras"
    [openvpn]="openvpn"
    [all]="rust,iac,gui_extras"
)

parse_profile() {
    local input="$1"
    local -A selected
    local p
    IFS=',' read -ra profiles <<< "$input"
    for p in "${profiles[@]}"; do
        p="${p//[[:space:]]/}"
        [[ -z "$p" ]] && continue
        if [[ -z "${VALID_PROFILES[$p]+x}" ]]; then
            print_error "Unknown profile: $p"
            echo "Valid profiles: developer, core, rust, iac, gui_extras, openvpn, all"
            exit 1
        fi
        if [[ "$p" == "all" ]]; then
            local expanded
            IFS=',' read -ra expanded <<< "${VALID_PROFILES[all]}"
            local e
            for e in "${expanded[@]}"; do selected[$e]=1; done
        else
            selected[$p]=1
        fi
    done

    if [[ -n "${selected[openvpn]:-}" && -z "${selected[core]:-}" ]]; then
        print_error "--profile openvpn requires --profile core (OpenVPN config is Hyperi-specific)"
        exit 1
    fi

    # Always ensure a base tier is present. "core" implies "developer";
    # any other selection (or empty) defaults the base tier to "developer".
    selected[developer]=1

    local -a ordered=()
    local name
    for name in developer core rust iac gui_extras openvpn; do
        [[ -n "${selected[$name]:-}" ]] && ordered+=("$name")
    done
    RESOLVED_TAGS=$(IFS=','; echo "${ordered[*]}")
}

show_help() {
    cat << 'EOF'
Usage: ./install.sh [OPTIONS]

OPTIONS:
  --check              Run in check mode (dry-run, no changes)
  --profile PROFILE    Profiles to install (comma-separated). See below.
  --tags TAGS          Ad-hoc Ansible tags (overrides --profile if both given)
  --tags-exclude TAGS  Exclude specific tags (comma-separated)
  --branch BRANCH      Git branch to use (default: main)
  --region REGION      Apply regional settings (e.g. au, en_AU.UTF-8)
  --help               Show this help message

  DEPRECATED (still works, will be removed in next release):
    --core             Alias for --profile core,rust,iac
    --all              Alias for --profile core,all

PROFILES:
  developer       OSS-safe base for external contributors on DFE/ESH.
                  Installs: git, docker, Python (uv), aws/azure/gcloud/gh,
                  vscode, browsers, utilities, CI tooling.
  core            Hyperi internal tier (implies developer). Adds:
                  Slack, Linear CLI, JFrog CLI, rclone, WireGuard,
                  Hyperi branding.
  rust            Rust toolchain + cargo-installed dev tools.
  iac             Infrastructure-as-code (Terraform, Vault, Helm, k8s).
  gui_extras      Optional GUI/TUI extras: Freelens, Bruno, Podman Desktop,
                  DBeaver Community, lazygit.
  openvpn         Transitional legacy VPN (requires core). Scheduled for
                  removal once WireGuard migration completes.
  all             Shortcut for rust,iac,gui_extras (applied to whichever
                  base tier you selected; defaults to developer)

EXAMPLES:
  ./install.sh --profile developer          # external contributor
  ./install.sh --profile core               # Hyperi dev (minimal)
  ./install.sh --profile core,rust          # Hyperi + Rust
  ./install.sh --profile core,all           # Hyperi + everything (no openvpn)
  ./install.sh --profile core,openvpn       # Hyperi + legacy VPN
  ./install.sh --profile core --extra-vars install_slack=false
EOF
    exit 0
}

# Parse arguments
ANSIBLE_CHECK=""
ANSIBLE_TAGS=""
ANSIBLE_SKIP_TAGS=""
ANSIBLE_EXTRA_VARS=""
GIT_BRANCH="main"
RESOLVED_TAGS=""

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
        --profile)
            PROFILE_INPUT="$2"
            shift 2
            ;;
        --core)
            print_warning "--core is deprecated; use --profile core,rust,iac instead"
            PROFILE_INPUT="core,rust,iac"
            shift
            ;;
        --all)
            print_warning "--all is deprecated; use --profile core,all instead"
            PROFILE_INPUT="core,all"
            shift
            ;;
        --region)
            REGION_ARG="$2"
            shift 2
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

# ---- Resolve --profile input into Ansible tags ----
# (Must run before winlike/maclike and region blocks — both append to ANSIBLE_TAGS.)
if [[ -n "${PROFILE_INPUT:-}" ]]; then
    parse_profile "$PROFILE_INPUT"
    if [[ -n "$ANSIBLE_TAGS" ]]; then
        print_warning "Both --profile and --tags given; --profile wins"
    fi
    ANSIBLE_TAGS="--tags $RESOLVED_TAGS"
elif [[ -z "$ANSIBLE_TAGS" ]]; then
    parse_profile "developer"
    ANSIBLE_TAGS="--tags $RESOLVED_TAGS"
fi

# Short-circuit for bats tests
if [[ "${DFE_PROFILE_TEST:-}" == "1" ]]; then
    echo "RESOLVED_TAGS=${RESOLVED_TAGS}"
    exit 0
fi

# Handle winlike/maclike priority: maclike overrides winlike (since winlike is default in --all)
# If both are specified, remove winlike from tags
if [[ "$ANSIBLE_TAGS" == *"maclike"* ]] && [[ "$ANSIBLE_TAGS" == *"winlike"* ]]; then
    print_info "Both winlike and maclike specified - using maclike (maclike overrides default winlike)"
    ANSIBLE_TAGS="${ANSIBLE_TAGS//,winlike/}"
    ANSIBLE_TAGS="${ANSIBLE_TAGS//winlike,/}"
    ANSIBLE_TAGS="${ANSIBLE_TAGS//winlike/}"
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

# Install latest Ansible via pip
print_info "Installing latest Ansible via pip..."
"$TEMP_ANSIBLE_DIR/bin/pip" install --upgrade pip setuptools wheel >/dev/null 2>&1
"$TEMP_ANSIBLE_DIR/bin/pip" install ansible >/dev/null 2>&1 || {
    print_error "Failed to install Ansible via pip"
    rm -rf "$TEMP_ANSIBLE_DIR"
    exit 1
}

ANSIBLE_VERSION=$("$TEMP_ANSIBLE_DIR/bin/ansible" --version | head -1 | awk '{print $2}')
print_success "Ansible $ANSIBLE_VERSION installed (temporary venv)"

# Determine script directory and check for ansible directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

# Check if ansible directory exists, clone if not
if [[ ! -d "ansible" ]]; then
    print_warning "ansible/ directory not found"
    print_info "Cloning ansible directory from repository (branch: $GIT_BRANCH)..."

    # Download GitHub tarball (no git required)
    TARBALL_URL="https://github.com/hyperi-io/dfe-developer/archive/refs/heads/${GIT_BRANCH}.tar.gz"

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
