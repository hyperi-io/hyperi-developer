#!/bin/bash
# ============================================================================
# add-dev-user.sh - Add new developer user to Hyperi Developer SOE
# ============================================================================
# Creates a new developer user with full access to the environment:
# - Sudo access (passwordless)
# - GNOME desktop access
# - RDP access via gnome-remote-desktop
# - Docker group membership
# - Proper home directory setup
#
# USAGE:
#   sudo add-dev-user <username> [password]
#
# If password is not provided, it will be set to the username (insecure default).
#
# EXAMPLES:
#   sudo add-dev-user john              # Creates user 'john' with password 'john'
#   sudo add-dev-user john secretpass   # Creates user 'john' with password 'secretpass'
#
# SUPPORTED PLATFORMS:
#   - Ubuntu 24.04+
#   - Fedora 42+
#
# LICENSE:
#   Licensed under the Apache License, Version 2.0
# ============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check root
if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root (use sudo)"
    exit 1
fi

# Help function
show_help() {
    echo "Usage: add-dev-user [OPTIONS] <username> [password]"
    echo ""
    echo "Creates a new developer user with full Hyperi environment access:"
    echo "  - Passwordless sudo"
    echo "  - Docker group membership"
    echo "  - RDP access (if gnome-remote-desktop installed)"
    echo "  - npm global packages directory (~/.npm-global)"
    echo "  - Git, AWS, Azure CLI pre-configured directories"
    echo "  - Properly configured home directory"
    echo ""
    echo "Options:"
    echo "  --copy-ssh-keys          Copy SSH authorized_keys from current (sudo) user"
    echo "  --ssh-keys-from <src>    Copy SSH keys from specified source:"
    echo "                             - Local file: /path/to/authorized_keys"
    echo "                             - Local user: @username (from /home/username/.ssh/)"
    echo "                             - Stdin:      - (read keys from stdin, great for piping)"
    echo "                             - Remote SCP: user@host:/path (requires SSH access)"
    echo "  -h, --help               Show this help message"
    echo ""
    echo "Arguments:"
    echo "  username    Username for the new developer (required)"
    echo "  password    Password (optional, defaults to username)"
    echo ""
    echo "Examples:"
    echo "  sudo add-dev-user john"
    echo "  sudo add-dev-user john secretpass"
    echo "  sudo add-dev-user --no-ssh-keys john           # Don't copy SSH keys"
    echo "  sudo add-dev-user --ssh-keys-from /tmp/keys john"
    echo "  sudo add-dev-user --ssh-keys-from @otheruser john"
    echo "  cat ~/.ssh/id_rsa.pub | ssh root@srv 'add-dev-user --ssh-keys-from - john'"
    exit 0
}

# Parse options
# Default: do NOT copy SSH keys (user must explicitly request it)
COPY_SSH_KEYS=false
SSH_KEYS_SOURCE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            ;;
        --copy-ssh-keys)
            COPY_SSH_KEYS=true
            shift
            ;;
        --ssh-keys-from)
            if [[ -z "${2:-}" ]]; then
                print_error "--ssh-keys-from requires a path argument"
                exit 1
            fi
            SSH_KEYS_SOURCE="$2"
            COPY_SSH_KEYS=false  # Using explicit source, not default copy
            shift 2
            ;;
        -*)
            print_error "Unknown option: $1"
            echo "Run 'add-dev-user --help' for usage information."
            exit 1
            ;;
        *)
            break
            ;;
    esac
done

# Check arguments
if [[ $# -lt 1 ]]; then
    echo "Usage: add-dev-user <username> [password]"
    echo ""
    echo "Creates a new user with full Hyperi developer environment access."
    echo "If password is not provided, it defaults to the username."
    echo ""
    echo "Run 'add-dev-user --help' for more information."
    exit 1
fi

USERNAME="$1"
PASSWORD="${2:-$USERNAME}"

# Validate username
if [[ ! "$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
    print_error "Invalid username. Must start with lowercase letter or underscore,"
    print_error "and contain only lowercase letters, digits, underscores, or hyphens."
    exit 1
fi

# Check if user already exists
if id "$USERNAME" &>/dev/null; then
    print_error "User '$USERNAME' already exists"
    exit 1
fi

# Detect distribution
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    DISTRO="$ID"
else
    print_error "Cannot detect distribution"
    exit 1
fi

print_info "Creating user '$USERNAME' on $DISTRO..."

# ============================================================================
# CREATE USER
# ============================================================================

case "$DISTRO" in
    ubuntu|debian)
        # Create user with home directory and bash shell
        useradd -m -s /bin/bash -G sudo "$USERNAME"

        # Add to additional groups if they exist
        for group in docker adm plugdev lpadmin; do
            if getent group "$group" &>/dev/null; then
                usermod -aG "$group" "$USERNAME"
                print_info "Added to group: $group"
            fi
        done
        ;;
    fedora|rhel|centos)
        # Create user with home directory and bash shell
        useradd -m -s /bin/bash -G wheel "$USERNAME"

        # Add to docker group if it exists
        if getent group docker &>/dev/null; then
            usermod -aG docker "$USERNAME"
            print_info "Added to group: docker"
        fi
        ;;
    *)
        print_error "Unsupported distribution: $DISTRO"
        exit 1
        ;;
esac

# Set password
echo "$USERNAME:$PASSWORD" | chpasswd
print_info "Password set"

# ============================================================================
# CONFIGURE PASSWORDLESS SUDO
# ============================================================================

SUDOERS_FILE="/etc/sudoers.d/90-$USERNAME-nopasswd"
echo "$USERNAME ALL=(ALL) NOPASSWD: ALL" > "$SUDOERS_FILE"
chmod 440 "$SUDOERS_FILE"
print_info "Passwordless sudo configured"

# ============================================================================
# CONFIGURE RDP ACCESS
# ============================================================================

# Check if gnome-remote-desktop is installed
if command -v grdctl &>/dev/null; then
    print_info "Configuring RDP access..."

    # Set RDP credentials for the new user
    if grdctl --system rdp set-credentials "$USERNAME" "$PASSWORD" 2>&1 | grep -q "fallback\|success" || true; then
        print_info "RDP credentials set for $USERNAME"
    else
        # Try anyway, some versions don't output anything on success
        grdctl --system rdp set-credentials "$USERNAME" "$PASSWORD" 2>/dev/null || true
        print_info "RDP credentials configured (may need service restart)"
    fi

    # Restart RDP service to pick up new credentials
    systemctl restart gnome-remote-desktop.service 2>/dev/null || true
else
    print_warn "grdctl not found - RDP not configured (install gnome-remote-desktop)"
fi

# ============================================================================
# COPY SKELETON CONFIG FILES
# ============================================================================

USER_HOME="/home/$USERNAME"

# Copy bashrc/profile if not exists
if [[ ! -f "$USER_HOME/.bashrc" ]] && [[ -f /etc/skel/.bashrc ]]; then
    cp /etc/skel/.bashrc "$USER_HOME/"
    chown "$USERNAME:$USERNAME" "$USER_HOME/.bashrc"
fi

# Create .config directory
mkdir -p "$USER_HOME/.config"
chown "$USERNAME:$USERNAME" "$USER_HOME/.config"

# Create dconf directory (prevents snap Firefox symlink issues)
mkdir -p "$USER_HOME/.config/dconf"
chown "$USERNAME:$USERNAME" "$USER_HOME/.config/dconf"

# ============================================================================
# CONFIGURE DEVELOPER TOOLS
# ============================================================================

# Create standard directories
mkdir -p "$USER_HOME/.local/bin"
mkdir -p "$USER_HOME/.npm-global"
mkdir -p "$USER_HOME/.aws"
mkdir -p "$USER_HOME/.azure"
mkdir -p "$USER_HOME/.kube"
mkdir -p "$USER_HOME/.docker"
chown -R "$USERNAME:$USERNAME" "$USER_HOME/.local"
chown -R "$USERNAME:$USERNAME" "$USER_HOME/.npm-global"
chown -R "$USERNAME:$USERNAME" "$USER_HOME/.aws"
chown -R "$USERNAME:$USERNAME" "$USER_HOME/.azure"
chown -R "$USERNAME:$USERNAME" "$USER_HOME/.kube"
chown -R "$USERNAME:$USERNAME" "$USER_HOME/.docker"
print_info "Developer directories created"

# Configure npm to use user-local global directory (avoids sudo for npm -g)
NPMRC="$USER_HOME/.npmrc"
if [[ ! -f "$NPMRC" ]]; then
    echo "prefix=\${HOME}/.npm-global" > "$NPMRC"
    chown "$USERNAME:$USERNAME" "$NPMRC"
    print_info "npm configured for user-local global packages"
fi

# Configure Git with placeholder (user must set their own name/email)
GITCONFIG="$USER_HOME/.gitconfig"
if [[ ! -f "$GITCONFIG" ]]; then
    cat > "$GITCONFIG" << EOF
[user]
    # TODO: Set your name and email
    # name = Your Name
    # email = your.email@example.com
[init]
    defaultBranch = main
[pull]
    rebase = false
[core]
    autocrlf = input
    editor = vim
[alias]
    st = status
    co = checkout
    br = branch
    ci = commit
    lg = log --oneline --graph --decorate
EOF
    chown "$USERNAME:$USERNAME" "$GITCONFIG"
    print_info "Git configured (user must set name/email)"
fi

# ============================================================================
# CONFIGURE SHELL ENVIRONMENT
# ============================================================================

# Add common paths to .bashrc if not already present
BASHRC="$USER_HOME/.bashrc"
if ! grep -q "# Hyperi Developer paths" "$BASHRC" 2>/dev/null; then
    cat >> "$BASHRC" << 'EOF'

# Hyperi Developer paths
export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$HOME/bin:$PATH"

# npm global packages (user-local, no sudo needed)
export NPM_CONFIG_PREFIX="$HOME/.npm-global"

# UV Python manager
if [[ -f "$HOME/.local/bin/uv" ]]; then
    eval "$(uv generate-shell-completion bash 2>/dev/null)" || true
fi

# Claude Code CLI
if command -v claude &>/dev/null; then
    eval "$(claude completion bash 2>/dev/null)" || true
fi

# kubectl completion
if command -v kubectl &>/dev/null; then
    source <(kubectl completion bash 2>/dev/null) || true
fi

# helm completion
if command -v helm &>/dev/null; then
    source <(helm completion bash 2>/dev/null) || true
fi

# GitHub CLI completion
if command -v gh &>/dev/null; then
    eval "$(gh completion -s bash 2>/dev/null)" || true
fi
EOF
    chown "$USERNAME:$USERNAME" "$BASHRC"
    print_info "Shell environment configured"
fi

# ============================================================================
# COPY SSH AUTHORIZED KEYS (optional)
# ============================================================================

# Create .ssh directory with correct permissions
mkdir -p "$USER_HOME/.ssh"
chown "$USERNAME:$USERNAME" "$USER_HOME/.ssh"
chmod 700 "$USER_HOME/.ssh"

SSH_KEY_COPIED=false

# Option 1: --ssh-keys-from <source>
if [[ -n "$SSH_KEYS_SOURCE" ]]; then
    if [[ "$SSH_KEYS_SOURCE" == "-" ]]; then
        # Source is stdin (great for piping over SSH)
        cat > "$USER_HOME/.ssh/authorized_keys"
        if [[ -s "$USER_HOME/.ssh/authorized_keys" ]]; then
            print_info "SSH authorized_keys read from stdin"
            SSH_KEY_COPIED=true
        else
            print_error "No SSH keys received from stdin"
            exit 1
        fi
    elif [[ "$SSH_KEYS_SOURCE" == @* ]]; then
        # Source is a local user (@username)
        SOURCE_USER="${SSH_KEYS_SOURCE#@}"
        SOURCE_HOME=$(getent passwd "$SOURCE_USER" | cut -d: -f6)
        if [[ -n "$SOURCE_HOME" ]] && [[ -f "$SOURCE_HOME/.ssh/authorized_keys" ]]; then
            cp "$SOURCE_HOME/.ssh/authorized_keys" "$USER_HOME/.ssh/"
            print_info "SSH authorized_keys copied from user $SOURCE_USER"
            SSH_KEY_COPIED=true
        else
            print_error "Cannot find SSH keys for user $SOURCE_USER"
            exit 1
        fi
    elif [[ "$SSH_KEYS_SOURCE" == *:* ]]; then
        # Source is SCP path (user@host:/path)
        if scp -q "$SSH_KEYS_SOURCE" "$USER_HOME/.ssh/authorized_keys" 2>/dev/null; then
            print_info "SSH authorized_keys copied via SCP from $SSH_KEYS_SOURCE"
            SSH_KEY_COPIED=true
        else
            print_error "Failed to copy SSH keys via SCP from $SSH_KEYS_SOURCE"
            exit 1
        fi
    else
        # Source is a local file path
        if [[ -f "$SSH_KEYS_SOURCE" ]]; then
            cp "$SSH_KEYS_SOURCE" "$USER_HOME/.ssh/authorized_keys"
            print_info "SSH authorized_keys copied from $SSH_KEYS_SOURCE"
            SSH_KEY_COPIED=true
        else
            print_error "SSH keys file not found: $SSH_KEYS_SOURCE"
            exit 1
        fi
    fi

# Option 2: --copy-ssh-keys (from sudo user)
elif [[ "$COPY_SSH_KEYS" == "true" ]]; then
    SUDO_USER_HOME=""
    if [[ -n "${SUDO_USER:-}" ]] && [[ "$SUDO_USER" != "root" ]]; then
        SUDO_USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    fi

    for SOURCE_HOME in "$SUDO_USER_HOME" /root; do
        if [[ -n "$SOURCE_HOME" ]] && [[ -f "$SOURCE_HOME/.ssh/authorized_keys" ]]; then
            cp "$SOURCE_HOME/.ssh/authorized_keys" "$USER_HOME/.ssh/"
            print_info "SSH authorized_keys copied from $SOURCE_HOME"
            SSH_KEY_COPIED=true
            break
        fi
    done

    if [[ "$SSH_KEY_COPIED" == "false" ]]; then
        print_warn "No SSH authorized_keys found to copy from sudo user"
    fi
fi

# Set permissions if keys were copied
if [[ "$SSH_KEY_COPIED" == "true" ]]; then
    chown "$USERNAME:$USERNAME" "$USER_HOME/.ssh/authorized_keys"
    chmod 600 "$USER_HOME/.ssh/authorized_keys"
else
    print_info "SSH directory created (add your own keys to ~/.ssh/authorized_keys)"
fi

# ============================================================================
# FIX SNAP FIREFOX PERMISSIONS (Ubuntu)
# ============================================================================

if [[ "$DISTRO" == "ubuntu" ]] && command -v snap &>/dev/null; then
    # Pre-create snap firefox config to avoid broken symlinks
    SNAP_FIREFOX_CONFIG="$USER_HOME/snap/firefox/common/.mozilla"
    if [[ ! -d "$SNAP_FIREFOX_CONFIG" ]]; then
        mkdir -p "$SNAP_FIREFOX_CONFIG"
        chown -R "$USERNAME:$USERNAME" "$USER_HOME/snap"
        print_info "Snap Firefox directories prepared"
    fi
fi

# ============================================================================
# SUMMARY
# ============================================================================

echo ""
print_info "============================================"
print_info "User '$USERNAME' created successfully!"
print_info "============================================"
echo ""
echo "  Username: $USERNAME"
echo "  Password: $PASSWORD"
echo "  Home:     $USER_HOME"
echo "  Sudo:     Passwordless (NOPASSWD)"
echo "  Groups:   $(id -nG "$USERNAME")"
echo ""
echo "  Developer tools configured:"
echo "    - npm global: ~/.npm-global (no sudo needed)"
echo "    - Git config: ~/.gitconfig (set name/email!)"
echo "    - AWS CLI:    ~/.aws"
echo "    - Azure CLI:  ~/.azure"
echo "    - kubectl:    ~/.kube"
echo "    - Docker:     ~/.docker"
echo ""

if command -v grdctl &>/dev/null; then
    # Get IP address
    IP_ADDR=$(hostname -I 2>/dev/null | awk '{print $1}')
    echo "  RDP Access:"
    echo "    Host: ${IP_ADDR:-$(hostname)}:3389"
    echo "    User: $USERNAME"
    echo "    Pass: $PASSWORD"
    echo ""
fi

print_warn "IMPORTANT: User must configure Git identity:"
echo "  git config --global user.name \"Full Name\""
echo "  git config --global user.email \"email@example.com\""
echo ""

if [[ "$PASSWORD" == "$USERNAME" ]]; then
    print_warn "Password is same as username - consider changing it!"
    echo "  Change password: passwd $USERNAME"
    echo "  Change RDP pass: sudo grdctl --system rdp set-credentials $USERNAME <newpass>"
    echo ""
fi

print_info "User can now log in via console, SSH, or RDP"
