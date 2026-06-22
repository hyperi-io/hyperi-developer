#!/bin/bash
# ============================================================================
# install-hyperi-developer-core - Core Development Tools Installation Script
# ============================================================================
# Advanced tools for developers contributing TO the Hyperi platform itself
# This script is for Hyperi core contributors and maintainers
#
# USAGE:
#   sudo ./install-hyperi-developer-core.sh
#
# INSTALLS:
#   - C Development Tools group and libraries
#   - Node.js LTS via N|Solid repository
#   - semantic-release and npm packages
#   - JFrog CLI, GitHub CLI, Azure CLI
#   - OpenVPN 3 client
#   - Claude Code CLI (native binary)
#   - UV and Nox Python tools
#   - Slack (Flatpak)
#
# NOTE: Core developers should run BOTH scripts:
#       1. First run install-hyperi-developer.sh (base tools)
#       2. Then run install-hyperi-developer-core.sh (advanced tools)
#       OR use install-all.sh to run everything in the correct order
#
# LICENSE:
#   Licensed under the Apache License, Version 2.0
#   See ../LICENSE file for full license text
# ============================================================================

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Source common functions library
if [[ -f "$SCRIPT_DIR/lib.sh" ]]; then
    source "$SCRIPT_DIR/lib.sh"
else
    echo "[ERROR] Cannot find lib.sh library" >&2
    exit 1
fi

# Initialize script with common setup
init_script "Core Development Tools Installation"

# Detect if GNOME desktop is running
if is_gnome; then
    HAS_GNOME="true"
else
    HAS_GNOME="false"
fi

# Install C development tools
print_info "Installing C development tools..."
sudo dnf group install -y "c-development"

# Install Node.js LTS
print_info "Installing Node.js LTS..."
curl -fsSL https://rpm.nodesource.com/setup_lts.x | sudo bash -
sudo dnf install -y nodejs

# Configure npm for user-specific global packages
print_info "Configuring npm for user-specific packages..."
mkdir -p "$HOME/.npm-global"
npm config set prefix "$HOME/.npm-global"

# Add to PATH in .bashrc if not already there
if ! grep -qF ".npm-global/bin" "$HOME/.bashrc"; then
    echo "" >> "$HOME/.bashrc"
    echo "# npm global packages (user-specific)" >> "$HOME/.bashrc"
    echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> "$HOME/.bashrc"
fi

# Install semantic-release and plugins
print_info "Installing semantic-release..."
npm install -g npm@latest
npm install -g semantic-release
npm install -g \
    @semantic-release/changelog \
    @semantic-release/git \
    @semantic-release/github \
    @semantic-release/commit-analyzer \
    @semantic-release/release-notes-generator \
    @semantic-release/exec \
    conventional-changelog-conventionalcommits 

# OpenVPN 3 COPR repository
print_info "Setting up OpenVPN 3 repository..."
sudo dnf copr enable -y dsommers/openvpn3
sudo dnf install -y openvpn3-client

# JFrog CLI repository
print_info "Installing JFrog CLI..."
cat << 'EOF' | sudo tee /etc/yum.repos.d/jfrog-cli.repo
[jfrog-cli]
name=JFrog CLI
baseurl=https://releases.jfrog.io/artifactory/jfrog-rpms
enabled=1
gpgcheck=1
gpgkey=https://releases.jfrog.io/artifactory/api/v2/repositories/jfrog-rpms/keyPairs/primary/public
       https://releases.jfrog.io/artifactory/api/v2/repositories/jfrog-rpms/keyPairs/secondary/public
EOF
sudo dnf install -y jfrog-cli-v2-jf

# GitHub CLI repository
print_info "Installing GitHub CLI..."
sudo dnf config-manager addrepo --from-repofile=https://cli.github.com/packages/rpm/gh-cli.repo --overwrite || true
sudo dnf install -y gh --repo gh-cli

# Azure CLI repository
print_info "Installing Azure CLI..."
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
cat << 'EOF' | sudo tee /etc/yum.repos.d/azure-cli.repo
[azure-cli]
name=Azure CLI
baseurl=https://packages.microsoft.com/yumrepos/azure-cli
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
sudo dnf install -y azure-cli

# Claude Code CLI (native binary - user-specific installation)
print_info "Installing Claude Code CLI (native binary)..."
CLAUDE_GCS_BUCKET="https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases"

# Remove deprecated npm installation if present
if [ -x "$HOME/.npm-global/bin/claude" ]; then
    print_info "Removing deprecated npm Claude Code installation..."
    npm uninstall -g @anthropic-ai/claude-code || true
fi

# Determine platform
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  CLAUDE_PLATFORM="linux-x64" ;;
    aarch64) CLAUDE_PLATFORM="linux-arm64" ;;
    *)       print_error "Unsupported architecture: $ARCH"; exit 1 ;;
esac

# Fetch latest version
CLAUDE_VERSION=$(curl -fsSL "${CLAUDE_GCS_BUCKET}/latest")
print_info "Claude Code version: $CLAUDE_VERSION"

# Fetch manifest and extract checksum
CLAUDE_CHECKSUM=$(curl -fsSL "${CLAUDE_GCS_BUCKET}/${CLAUDE_VERSION}/manifest.json" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['platforms']['${CLAUDE_PLATFORM}']['checksum'])")

# Download binary to temp directory
mkdir -p /tmp/claude-install
curl -fsSL -o /tmp/claude-install/claude "${CLAUDE_GCS_BUCKET}/${CLAUDE_VERSION}/${CLAUDE_PLATFORM}/claude"
chmod +x /tmp/claude-install/claude

# Verify SHA256 checksum
ACTUAL_CHECKSUM=$(sha256sum /tmp/claude-install/claude | cut -d' ' -f1)
if [ "$ACTUAL_CHECKSUM" != "$CLAUDE_CHECKSUM" ]; then
    print_error "Claude Code checksum verification failed!"
    print_error "  Expected: $CLAUDE_CHECKSUM"
    print_error "  Actual:   $ACTUAL_CHECKSUM"
    rm -rf /tmp/claude-install
    exit 1
fi

# Install (sets up ~/.local/bin/claude and shell integration)
mkdir -p "$HOME/.local/bin"
/tmp/claude-install/claude install

# Cleanup
rm -rf /tmp/claude-install

# Linear.app CLI tool (system-wide installation)
sudo npm install -g @digitalstories/linear-cli

# claude-monitor via UV (if UV is installed)
if command -v uv &>/dev/null; then
    print_info "Installing claude-monitor..."
    uv tool install claude-monitor
fi

# Nox via pipx (if pipx is installed)
if command -v pipx &>/dev/null; then
    print_info "Installing Nox..."
    pipx install nox
fi

# Slack via Flatpak (GUI only)
if [ "$HAS_GNOME" = "true" ] && command -v flatpak &>/dev/null; then
    print_info "Installing Slack..."
    # Ensure flathub remote is configured for user
    if ! flatpak remote-list --user | grep -q flathub; then
        print_info "Adding flathub remote for user..."
        flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || true
    fi
    # Install Slack (non-fatal if it fails)
    FLATPAK_TTY_PROGRESS=0 flatpak install --user -y flathub com.slack.Slack 2>&1 | grep -v "%" || print_info "Slack installation skipped (may already be installed system-wide)"
fi

print_info "Core Development Tools Installation Complete"

# Simple verification - check if key tools actually work
print_info "Verifying installation..."
echo ""
echo "Development Tools:"
node --version &>/dev/null && echo "  [OK] Node.js" || echo "  [FAIL] Node.js"
npm --version &>/dev/null && echo "  [OK] npm" || echo "  [FAIL] npm"

echo ""
echo "Cloud/Enterprise Tools:"
jf --version &>/dev/null && echo "  [OK] JFrog CLI" || echo "  [FAIL] JFrog CLI"
gh --version &>/dev/null && echo "  [OK] GitHub CLI" || echo "  [FAIL] GitHub CLI"
az version &>/dev/null && echo "  [OK] Azure CLI" || echo "  [FAIL] Azure CLI"
openvpn3 version &>/dev/null && echo "  [OK] OpenVPN 3" || echo "  [FAIL] OpenVPN 3"

echo ""
echo "User-installed Tools:"
[ -x "$HOME/.npm-global/bin/semantic-release" ] && echo "  [OK] semantic-release" || echo "  [FAIL] semantic-release"
[ -x "$HOME/.local/bin/claude" ] && echo "  [OK] Claude Code CLI" || echo "  [FAIL] Claude Code CLI"

echo ""
echo "Python Tools:"
command -v uv &>/dev/null && echo "  [OK] UV" || echo "  [FAIL] UV"
command -v nox &>/dev/null && echo "  [OK] Nox" || echo "  [FAIL] Nox"

echo ""
echo "Communication Tools:"
flatpak list --app 2>/dev/null | grep -q com.slack.Slack && echo "  [OK] Slack" || echo "  [FAIL] Slack"

echo ""
print_success "Core development tools installed"
print_info "NOTE: A reboot is recommended after install-all.sh completes"