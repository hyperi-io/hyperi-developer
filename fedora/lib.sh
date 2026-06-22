#!/bin/bash
# lib.sh - Common functions for Hyperi installation scripts
# Licensed under Apache License 2.0

# ============================================================================
# OUTPUT FUNCTIONS
# ============================================================================
print_header() {
    echo ""
    echo "============================================================================"
    echo "  $1"
    echo "============================================================================"
    echo ""
}

print_status() { echo "[INFO] $1"; }
print_error() { echo "[ERROR] $1" >&2; }
print_warning() { echo "[WARN] $1"; }
print_success() { echo "[OK] $1"; }
print_info() { echo "[INFO] $1"; }
print_ok() { echo "[OK] $1"; }

# ============================================================================
# VERIFICATION TRACKING
# ============================================================================
# Global verification counters
VERIFY_PASSED=0
VERIFY_WARNED=0
VERIFY_FAILED=0

reset_verify_counts() {
    VERIFY_PASSED=0
    VERIFY_WARNED=0
    VERIFY_FAILED=0
}

increment_verify_pass() {
    ((VERIFY_PASSED++)) || true
}

increment_verify_warn() {
    ((VERIFY_WARNED++)) || true
}

increment_verify_fail() {
    ((VERIFY_FAILED++)) || true
}

print_verify_section() {
    local icon="${1:-}"
    local title="${2:-}"
    echo ""
    [ -n "$title" ] && echo "$title"
}

print_verify_summary() {
    echo ""
    print_info "========================================="
    print_info "Verification Summary:"
    print_info "  Passed:   $VERIFY_PASSED"
    [ "$VERIFY_WARNED" -gt 0 ] && print_warning "  Warnings: $VERIFY_WARNED"
    [ "$VERIFY_FAILED" -gt 0 ] && print_error "  Failed:   $VERIFY_FAILED"
    echo ""
}

# Verify sysctl setting
verify_sysctl_setting() {
    local key="$1"
    local expected="$2"
    local description="${3:-$key}"
    local current
    current=$(sysctl -n "$key" 2>/dev/null || echo "")

    if [ "$current" = "$expected" ]; then
        echo "   [OK] $description: $current"
        return 0
    else
        echo "   [WARN] $description: $current (expected: $expected)"
        return 1
    fi
}

# Verify command exists
verify_command_exists() {
    local cmd="$1"
    local description="${2:-$cmd}"

    if command -v "$cmd" &>/dev/null; then
        echo "   [OK] $description installed"
        return 0
    else
        echo "   [FAIL] $description not found"
        return 1
    fi
}

# Verify service status
verify_service_status() {
    local service="$1"
    local description="${2:-$service}"

    if systemctl is-active "$service" &>/dev/null; then
        echo "   [OK] $description is running"
        return 0
    else
        echo "   [WARN] $description is not running"
        return 1
    fi
}

# Verify kernel module loaded
verify_module_loaded() {
    local module="$1"
    local description="${2:-$module}"

    if lsmod | grep -q "^$module "; then
        echo "   [OK] $description loaded"
        return 0
    else
        echo "   [WARN] $description not loaded"
        return 1
    fi
}

# Detect virtualization platform
detect_virtualization() {
    if command -v systemd-detect-virt &>/dev/null; then
        local virt_type
        virt_type=$(systemd-detect-virt 2>/dev/null || echo "none")
        echo "$virt_type"
    else
        echo "unknown"
    fi
}

# Create sysctl configuration file
create_sysctl_config() {
    local filename="$1"
    shift
    local description="$1"
    shift
    local settings=("$@")

    sudo tee "/etc/sysctl.d/${filename}.conf" >/dev/null <<EOF
# ${description}
$(printf '%s\n' "${settings[@]}")
EOF
    sudo sysctl --system >/dev/null 2>&1 || true
}

# ============================================================================
# SYSTEM DETECTION
# ============================================================================
# Check if running on specific distro
is_fedora() { [[ -f /etc/fedora-release ]]; }
is_ubuntu() { [[ -f /etc/lsb-release ]] && grep -q Ubuntu /etc/lsb-release 2>/dev/null; }
is_debian() { [[ -f /etc/debian_version ]]; }
is_macos() { [[ "$(uname)" == "Darwin" ]]; }

# Check if GNOME desktop is running
is_gnome() {
    [[ "${XDG_CURRENT_DESKTOP:-}" == *"GNOME"* ]] || \
    [[ "${GDMSESSION:-}" == "gnome"* ]] || \
    pgrep -x gnome-shell >/dev/null 2>&1
}

# Require specific distro
require_distro() {
    local required="$1"
    local display_name="${2:-$1}"

    case "$required" in
        fedora)
            is_fedora || { print_error "This script requires $display_name"; exit 1; }
            ;;
        ubuntu)
            is_ubuntu || { print_error "This script requires $display_name"; exit 1; }
            ;;
        debian)
            is_debian || { print_error "This script requires $display_name"; exit 1; }
            ;;
        macos)
            is_macos || { print_error "This script requires $display_name"; exit 1; }
            ;;
        *)
            print_error "Unknown distro requirement: $required"
            exit 1
            ;;
    esac
}

# Detect if running in VM
detect_vm() {
    if command -v systemd-detect-virt &>/dev/null; then
        local virt
        virt=$(systemd-detect-virt 2>/dev/null)
        [[ "$virt" != "none" ]] && [[ -n "$virt" ]]
    else
        return 1
    fi
}

# Get VM type
get_vm_type() {
    if command -v systemd-detect-virt &>/dev/null; then
        systemd-detect-virt 2>/dev/null || echo "unknown"
    else
        echo "unknown"
    fi
}

# Check if running in container
is_container() {
    [[ -f /.dockerenv ]] || [[ -f /run/.containerenv ]] || [[ -n "${KUBERNETES_SERVICE_HOST:-}" ]]
}

# ============================================================================
# PACKAGE MANAGEMENT
# ============================================================================
# Check if command exists
is_installed() {
    command -v "$1" &>/dev/null
}

# Check if DNF package is installed (Fedora)
is_package_installed() {
    if command -v dnf &>/dev/null; then
        dnf list --installed "$1" &>/dev/null
    elif command -v apt &>/dev/null; then
        dpkg -l "$1" 2>/dev/null | grep -q "^ii"
    else
        return 1
    fi
}

# Install package based on distro
install_package() {
    local package="$1"

    if is_fedora; then
        sudo dnf install -y "$package"
    elif is_ubuntu || is_debian; then
        sudo apt-get install -y "$package"
    elif is_macos && command -v brew &>/dev/null; then
        brew install "$package"
    else
        print_error "Unable to install $package - unknown package manager"
        return 1
    fi
}

# ============================================================================
# SUDO OPERATIONS
# ============================================================================
# Configure passwordless sudo for developer (not used in scripts, utility only)
developer_sudoers() {
    local username="${1:-$USER}"
    local sudoers_file="/etc/sudoers.d/99-developer-$username"

    if [[ ! -f "$sudoers_file" ]]; then
        print_info "Creating passwordless sudo config for $username"
        echo "$username ALL=(ALL) NOPASSWD: ALL" | sudo tee "$sudoers_file" > /dev/null
        sudo chmod 0440 "$sudoers_file"
        print_success "Passwordless sudo configured for $username"
    else
        print_info "Passwordless sudo already configured for $username"
    fi
}

# ============================================================================
# FILE OPERATIONS
# ============================================================================
# Backup file with timestamp
backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        local backup
        backup="${file}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$file" "$backup"
        print_info "Backed up $file to $backup"
    fi
}

# Create directory if not exists
create_directory() {
    [[ -d "$1" ]] || mkdir -p "$1"
}

# Check if file contains string
file_contains() {
    local file="$1"
    local search="$2"
    [[ -f "$file" ]] && grep -q "$search" "$file" 2>/dev/null
}

# Append to file if not already present
append_if_missing() {
    local file="$1"
    local content="$2"

    if ! file_contains "$file" "$content"; then
        echo "$content" >> "$file"
        return 0
    fi
    return 1
}

# ============================================================================
# SERVICE MANAGEMENT
# ============================================================================
# Check if systemd service is active
is_service_active() {
    systemctl is-active "$1" &>/dev/null
}

# Check if systemd service is enabled
is_service_enabled() {
    systemctl is-enabled "$1" &>/dev/null
}

# Enable and start service
enable_service() {
    local service="$1"
    sudo systemctl enable "$service" 2>/dev/null
    sudo systemctl start "$service" 2>/dev/null
}

# ============================================================================
# NETWORK OPERATIONS
# ============================================================================
# Simple download with curl
download_file() {
    local url="$1"
    local output="$2"

    if command -v curl &>/dev/null; then
        curl -fsSL "$url" -o "$output"
    elif command -v wget &>/dev/null; then
        wget -q "$url" -O "$output"
    else
        print_error "Neither curl nor wget available"
        return 1
    fi
}

# Check if URL is reachable
url_exists() {
    local url="$1"

    if command -v curl &>/dev/null; then
        curl -fsS --head "$url" &>/dev/null
    elif command -v wget &>/dev/null; then
        wget -q --spider "$url" &>/dev/null
    else
        return 1
    fi
}

# ============================================================================
# VERSION MANAGEMENT
# ============================================================================
# Compare versions (simple)
version_gt() {
    # Returns 0 if version1 > version2
    local v1="$1"
    local v2="$2"

    # Simple comparison using sort -V
    [[ "$(printf '%s\n' "$v1" "$v2" | sort -V | head -n1)" != "$v1" ]]
}

# Get latest GitHub release tag
get_github_latest_release() {
    local repo="$1"  # Format: owner/repo

    curl -s "https://api.github.com/repos/$repo/releases/latest" | \
        grep '"tag_name"' | \
        sed -E 's/.*"([^"]+)".*/\1/'
}

# ============================================================================
# USER INTERACTION
# ============================================================================
# Ask yes/no question
confirm() {
    local prompt="${1:-Continue?}"
    local default="${2:-n}"  # Default to no

    if [[ "$default" == "y" ]]; then
        prompt="$prompt [Y/n]: "
        default_val=0
    else
        prompt="$prompt [y/N]: "
        default_val=1
    fi

    read -p "$prompt" -n 1 -r
    echo

    if [[ -z "$REPLY" ]]; then
        return $default_val
    elif [[ "$REPLY" =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

# ============================================================================
# SCRIPT INITIALIZATION
# ============================================================================
# Common initialization function for all scripts
init_script() {
    local script_name="${1:-}"

    # Check OS - must be Fedora
    require_distro "fedora" "Fedora Linux"

    # Print header if provided
    [[ -n "$script_name" ]] && print_header "$script_name"

    # Display version if available
    local version_file="${SCRIPT_DIR}/../VERSION"
    if [[ -f "$version_file" ]]; then
        local version
        version=$(cat "$version_file")
        print_info "Version: $version"
    fi
}

# ============================================================================
# VALIDATION HELPERS
# ============================================================================
# Check if running as root
is_root() { [[ $EUID -eq 0 ]]; }

# Require root privileges
require_root() {
    if ! is_root; then
        print_error "This script must be run with sudo or as root"
        exit 1
    fi
}

# Check if variable is set
is_set() { [[ -n "${1:-}" ]]; }

# Check if variable is empty
is_empty() { [[ -z "${1:-}" ]]; }

# ============================================================================
# PATH HELPERS
# ============================================================================
# Get absolute path
get_absolute_path() {
    echo "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
}

# Check if path is absolute
is_absolute_path() {
    [[ "$1" == /* ]]
}

# Get script directory (useful for sourcing other files)
get_script_dir() {
    echo "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
}