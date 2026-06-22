#!/bin/bash
# ============================================================================
# install-hyperi-developer - Hyperi Developer Environment Setup Script
# ============================================================================
# Default installer for developers building applications FOR the Hyperi platform
# This is the main script for most developers using Hyperi
#
# USAGE:
#   ./install-hyperi-developer.sh [--sudoers]
#
# INSTALLS:
#   - Docker CE, Docker Desktop (GUI), Docker Compose Plugin
#   - VS Code (GUI), Google Chrome (GUI), Firefox extensions (GUI)
#   - Python tools: pyenv, pipx, UV (replaces pip/poetry)
#   - Cloud tools: AWS CLI, kubectl, Helm, Terraform, Vault
#   - Data tools: Confluent CLI, ClickHouse, Vector
#   - Dev utilities: Git, Git LFS, jq, yq, bat, ripgrep, fd-find, httpie
#   - System tools: tmux, ansible, postgresql, ShellCheck
#
# NOTE: GUI tools are only installed if GNOME desktop is running
#       For Hyperi core contributors, use install-hyperi-developer-core.sh
#
# LICENSE:
#   Licensed under the Apache License, Version 2.0
#   See ../LICENSE file for full license text
# ============================================================================

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions library
if [[ -f "$SCRIPT_DIR/lib.sh" ]]; then
    source "$SCRIPT_DIR/lib.sh"
else
    echo "[ERROR] Cannot find lib.sh library" >&2
    exit 1
fi

# Parse command line options
ENABLE_SUDOERS=false
INSTALL_GHOSTTY=true
while [[ $# -gt 0 ]]; do
    case $1 in
        --sudoers)
            ENABLE_SUDOERS=true
            shift
            ;;
        --no-ghostty)
            INSTALL_GHOSTTY=false
            shift
            ;;
        --help)
            echo "Usage: $0 [--sudoers] [--no-ghostty] [--help]"
            echo ""
            echo "Options:"
            echo "  --sudoers      Configure passwordless sudo for the current user (optional)"
            echo "  --no-ghostty   Skip Ghostty terminal installation (optional)"
            echo "  --help         Show this help message"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Initialize script with common setup
init_script "Hyperi Developer Environment Setup"

# Detect if GNOME desktop is running
if is_gnome; then
    HAS_GNOME="true"
    print_info "GNOME desktop detected - GUI tools will be installed"
else
    HAS_GNOME="false"
    print_info "GNOME not detected - skipping GUI tools"
fi

# Configure passwordless sudo if requested
if [[ "$ENABLE_SUDOERS" = true ]]; then
    print_info "Configuring passwordless sudo as requested..."
    developer_sudoers "$USER"
fi

# Configure SELinux to permissive mode
print_info "Configuring SELinux to permissive mode..."
sudo setenforce 0 || true
sudo sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config || true

# Enable RPM Fusion repositories
print_info "Enabling RPM Fusion repositories..."
sudo dnf install -y "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" || true
sudo dnf install -y "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm" || true

# Configure DNF for optimal performance
print_info "Configuring DNF for optimal performance..."
# Check if we've already configured DNF
if ! grep -q "# Performance optimizations" /etc/dnf/dnf.conf 2>/dev/null; then
    sudo bash -c 'cat >> /etc/dnf/dnf.conf << EOF || true

# Performance optimizations
max_parallel_downloads=20
fastestmirror=False
deltarpm=True
timeout=30
retries=10
skip_if_unavailable=True
metadata_expire=7200
EOF'
else
    print_info "DNF already optimized, skipping..."
fi

# Configure AARNET mirrors
print_info "Configuring AARNET mirrors for faster downloads..."
sudo sed -i 's/^metalink=/#metalink=/' /etc/yum.repos.d/fedora.repo || true
sudo sed -i '/\[fedora\]/a baseurl=https://mirror.aarnet.edu.au/pub/fedora/linux/releases/$releasever/Everything/$basearch/os/' /etc/yum.repos.d/fedora.repo || true
sudo sed -i 's/^metalink=/#metalink=/' /etc/yum.repos.d/fedora-updates.repo || true
sudo sed -i '/\[updates\]/a baseurl=https://mirror.aarnet.edu.au/pub/fedora/linux/updates/$releasever/Everything/$basearch/' /etc/yum.repos.d/fedora-updates.repo || true

# Clear DNF cache and update metadata once
sudo dnf clean all
sudo dnf makecache

# Remove Podman if installed (conflicts with Docker)
print_info "Removing Podman (conflicts with Docker)..."
sudo dnf remove -y podman podman-docker buildah skopeo toolbox || true

# Configure Docker repository
print_info "Adding Docker CE repository..."
sudo dnf config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo --overwrite || true

# Install core system packages
print_info "Installing core system packages..."

# Split packages into GUI and non-GUI
GUI_PACKAGES=""
if [ "$HAS_GNOME" = "true" ]; then
    # Note: GNOME extensions are now installed via gext, not DNF packages (for GNOME 48+ compatibility)
    GUI_PACKAGES="firefox gnome-extensions-app gnome-shell-extension-appindicator"
fi

sudo dnf install -y --skip-unavailable \
    git \
    $GUI_PACKAGES \
    gh \
    git-lfs \
    git-subtree \
    curl \
    wget \
    bind-utils \
    net-tools \
    traceroute \
    nmap \
    telnet \
    nc \
    whois \
    htop \
    lsof \
    psmisc \
    procps-ng \
    tree \
    unzip \
    zip \
    tar \
    openssl \
    certbot \
    mkcert \
    socat \
    tcpdump \
    iperf3 \
    mtr \
    siege \
    bats \
    jq \
    yq \
    bat \
    fzf \
    ripgrep \
    fd-find \
    httpie \
    tmux \
    postgresql \
    ansible \
    docker-ce \
    docker-compose-plugin \
    ShellCheck \
    dnf-utils \
    dnf-automatic

# Configure git-lfs
print_info "Configuring Git LFS..."
git lfs install --system || git lfs install || true

# Configure git for better submodule handling
print_info "Configuring Git for submodules..."
git config --global submodule.recurse true
git config --global diff.submodule log
git config --global status.submoduleSummary true
git config --global pull.rebase true

# Install pyenv system-wide (Python version manager)
print_info "Installing pyenv (system-wide)..."
sudo dnf install -y gcc make patch zlib-devel bzip2 bzip2-devel readline-devel sqlite sqlite-devel openssl-devel tk-devel libffi-devel xz-devel
if [ ! -d "/opt/pyenv" ]; then
    sudo git clone https://github.com/pyenv/pyenv.git /opt/pyenv
    # Create pyenv group for shared access
    sudo groupadd -f pyenv
    # Set proper ownership and permissions
    sudo chown -R root:pyenv /opt/pyenv
    sudo chmod -R 755 /opt/pyenv
    # Make shims and versions directories group-writable (775 = rwxrwxr-x)
    sudo mkdir -p /opt/pyenv/shims /opt/pyenv/versions
    sudo chmod 775 /opt/pyenv/shims /opt/pyenv/versions
    # Add current user to pyenv group
    sudo usermod -aG pyenv "${USER}"
else
    # Fix permissions on existing installation
    sudo groupadd -f pyenv
    sudo chown -R root:pyenv /opt/pyenv
    sudo mkdir -p /opt/pyenv/shims /opt/pyenv/versions
    sudo chmod 775 /opt/pyenv/shims /opt/pyenv/versions
    sudo usermod -aG pyenv "${USER}"
fi

# Add to system profile (if not already present)
if [ ! -f /etc/profile.d/pyenv.sh ]; then
    sudo tee /etc/profile.d/pyenv.sh > /dev/null << 'EOF'
export PYENV_ROOT="/opt/pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"
EOF
else
    print_info "pyenv already installed system-wide"
fi

# Configure Docker
print_info "Configuring Docker..."
sudo usermod -aG docker "$USER" || true
sudo systemctl enable docker
sudo systemctl start docker

# Install Python development tools
print_info "Installing Python development tools..."
sudo dnf install -y python3-pip python3-devel

# Install pipx (Python application manager)
print_info "Installing pipx..."
python3 -m pip install --user pipx
python3 -m pipx ensurepath || true

# Install UV (fast Python package installer - replaces pip and poetry)
print_info "Installing UV..."
pipx install uv || python3 -m pip install --user uv

# Install gext (gnome-extensions-cli) for extension management
if [ "$HAS_GNOME" = "true" ]; then
    print_info "Installing gnome-extensions-cli (gext)..."
    pipx install gnome-extensions-cli || true
fi

# Install Docker Desktop (GUI application)
if [ "$HAS_GNOME" = "true" ]; then
    print_info "Installing Docker Desktop..."
    # Docker Desktop for Fedora uses rpm directly
    DOCKER_DESKTOP_URL="https://desktop.docker.com/linux/main/amd64/docker-desktop-x86_64.rpm?utm_source=docker&utm_medium=webreferral&utm_campaign=docs-driven-download-linux-amd64"
    curl -fsSL -o /tmp/docker-desktop.rpm "$DOCKER_DESKTOP_URL" || true
    if [ -f /tmp/docker-desktop.rpm ]; then
        sudo dnf install -y /tmp/docker-desktop.rpm || true
        rm -f /tmp/docker-desktop.rpm
    fi
else
    print_info "Skipping Docker Desktop (requires GNOME)"
fi

# VS Code repository and installation (GUI application)
if [ "$HAS_GNOME" = "true" ]; then
    print_info "Installing VS Code..."
    sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
    echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" | sudo tee /etc/yum.repos.d/vscode.repo
    sudo dnf install -y code

    # Configure VS Code settings
    print_info "Configuring VS Code settings..."
    # User settings directory
    VS_CODE_USER_DIR="$HOME/.config/Code/User"
    mkdir -p "$VS_CODE_USER_DIR"

    # Create or update settings.json with proper window close behavior
    VS_CODE_SETTINGS="$VS_CODE_USER_DIR/settings.json"
    if [ -f "$VS_CODE_SETTINGS" ]; then
        # Backup existing settings
        cp "$VS_CODE_SETTINGS" "$VS_CODE_SETTINGS.backup.$(date +%Y%m%d_%H%M%S)"
        # Update existing settings using jq to preserve JSON structure
        jq '. + {"window.confirmBeforeClose": "never", "window.closeWhenEmpty": false, "window.restoreWindows": "folders"}' "$VS_CODE_SETTINGS" > "$VS_CODE_SETTINGS.tmp" && mv "$VS_CODE_SETTINGS.tmp" "$VS_CODE_SETTINGS"
    else
        # Create new settings file
        cat > "$VS_CODE_SETTINGS" << 'EOF'
{
    "window.confirmBeforeClose": "never",
    "window.closeWhenEmpty": false,
    "window.restoreWindows": "folders"
}
EOF
    fi
else
    print_info "Skipping VS Code (requires GNOME)"
fi

# Google Chrome repository and installation (GUI application)
if [ "$HAS_GNOME" = "true" ]; then
    print_info "Installing Google Chrome..."
    # Remove old/expired Google GPG keys to avoid conflicts
    print_info "Cleaning up old Google Chrome GPG keys..."
    for key in $(rpm -qa gpg-pubkey* | xargs rpm -qi | grep -B 5 "Google" | grep "Name.*gpg-pubkey" | awk '{print $3}'); do
        sudo rpm -e "$key" 2>/dev/null || true
    done
    # Set up repository with fresh GPG key
    echo -e "[google-chrome]\nname=Google Chrome\nbaseurl=http://dl.google.com/linux/chrome/rpm/stable/x86_64\nenabled=1\ngpgcheck=1\ngpgkey=https://dl.google.com/linux/linux_signing_key.pub" | sudo tee /etc/yum.repos.d/google-chrome.repo
    sudo rpm --import https://dl.google.com/linux/linux_signing_key.pub || true
    sudo dnf install -y google-chrome-stable
else
    print_info "Skipping Google Chrome (requires GNOME)"
fi

# Vector.dev repository
print_info "Setting up Vector.dev repository..."
cat << 'EOF' | sudo tee /etc/yum.repos.d/vector.repo
[vector]
name = Vector
baseurl = https://yum.vector.dev/stable/vector-0/$basearch/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://keys.datadoghq.com/DATADOG_RPM_KEY_CURRENT.public https://keys.datadoghq.com/DATADOG_RPM_KEY_B01082D3.public https://keys.datadoghq.com/DATADOG_RPM_KEY_FD4BF915.public
EOF

print_info "Installing Vector..."
sudo dnf install -y vector

# ClickHouse repository
print_info "Setting up ClickHouse repository..."
cat << 'EOF' | sudo tee /etc/yum.repos.d/clickhouse.repo
[clickhouse-stable]
name=ClickHouse - Stable Repository
baseurl=https://packages.clickhouse.com/rpm/stable/
gpgcheck=0
enabled=1
EOF

print_info "Installing ClickHouse client..."
sudo dnf install -y clickhouse-client

# Confluent repository (Kafka CLI)
print_info "Setting up Confluent repository..."
# Detect latest Confluent version
CONFLUENT_VERSION=$(curl -sL https://packages.confluent.io/rpm/ 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | sort -V | tail -1)
if [ -z "$CONFLUENT_VERSION" ]; then
    print_warning "Could not detect latest Confluent version, using 8.1 as fallback"
    CONFLUENT_VERSION="8.1"
fi
print_info "Using Confluent version: $CONFLUENT_VERSION"
sudo rpm --import "https://packages.confluent.io/rpm/$CONFLUENT_VERSION/archive.key" || true
cat << EOF | sudo tee /etc/yum.repos.d/confluent.repo
[Confluent]
name=Confluent repository
baseurl=https://packages.confluent.io/rpm/$CONFLUENT_VERSION
gpgcheck=1
gpgkey=https://packages.confluent.io/rpm/$CONFLUENT_VERSION/archive.key
enabled=1
EOF

print_info "Installing Confluent CLI (Kafka client)..."
sudo dnf install -y confluent-cli

# HashiCorp repository
print_info "Setting up HashiCorp repository..."
sudo curl -fsSL https://rpm.releases.hashicorp.com/fedora/hashicorp.repo -o /etc/yum.repos.d/hashicorp.repo

print_info "Installing HashiCorp tools (Terraform, Vault)..."
sudo dnf install -y terraform vault

# Install AWS CLI v2
print_info "Installing AWS CLI v2..."
pushd /tmp >/dev/null || exit 1
curl -sL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
sudo ./aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update || \
    sudo ./aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli
rm -rf awscliv2.zip aws/
popd >/dev/null || exit 1

# Install kubectl
print_info "Installing kubectl..."
# Detect latest stable Kubernetes version
K8S_FULL_VERSION=$(curl -sL https://dl.k8s.io/release/stable.txt 2>/dev/null || echo "v1.34.1")
K8S_VERSION=$(echo "$K8S_FULL_VERSION" | grep -oE '[0-9]+\.[0-9]+' | head -1)
if [ -z "$K8S_VERSION" ]; then
    print_warning "Could not detect latest Kubernetes version, using 1.34 as fallback"
    K8S_VERSION="1.34"
fi
print_info "Using Kubernetes version: $K8S_VERSION"
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/rpm/
enabled=1
gpgcheck=0
exclude=kubelet kubeadm cri-tools kubernetes-cni
EOF
sudo dnf install -y kubectl --repo kubernetes

# Install Helm
print_info "Installing Helm..."
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
rm get_helm.sh

# Install Helm Dashboard plugin
print_info "Installing Helm Dashboard plugin..."
helm plugin install https://github.com/komodorio/helm-dashboard.git || true

# Install K9s
print_info "Installing K9s..."
K9S_VERSION=$(curl -s https://api.github.com/repos/derailed/k9s/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
curl -sL https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_amd64.tar.gz | sudo tar xz -C /usr/local/bin k9s
sudo chmod +x /usr/local/bin/k9s

# Install Freelens (Kubernetes IDE - GUI only)
if [ "$HAS_GNOME" = "true" ] && command -v flatpak &>/dev/null; then
    print_info "Installing Freelens (Kubernetes IDE)..."
    # Ensure flathub remote is configured for user
    if ! flatpak remote-list --user | grep -q flathub; then
        flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || true
    fi
    FLATPAK_TTY_PROGRESS=0 flatpak install --user -y flathub app.freelens.Freelens 2>&1 | grep -v "%" || print_info "Freelens installation skipped (may already be installed)"
fi

# Install Minikube
if ! command -v minikube &>/dev/null; then
    print_info "Installing Minikube..."
    pushd /tmp >/dev/null || exit 1
    curl -LO https://github.com/kubernetes/minikube/releases/latest/download/minikube-linux-amd64
    sudo install minikube-linux-amd64 /usr/local/bin/minikube
    rm -f minikube-linux-amd64
    popd >/dev/null || exit 1
else
    print_info "Minikube already installed, skipping..."
fi

# Install kubectx and kubens
print_info "Installing kubectx and kubens..."
KUBECTX_VERSION=$(curl -s https://api.github.com/repos/ahmetb/kubectx/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
sudo curl -L https://github.com/ahmetb/kubectx/releases/download/${KUBECTX_VERSION}/kubectx -o /usr/local/bin/kubectx
sudo curl -L https://github.com/ahmetb/kubectx/releases/download/${KUBECTX_VERSION}/kubens -o /usr/local/bin/kubens
sudo chmod +x /usr/local/bin/kubectx /usr/local/bin/kubens

# Install ArgoCD CLI
print_info "Installing ArgoCD CLI..."
ARGOCD_VERSION=$(curl -s https://api.github.com/repos/argoproj/argo-cd/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
sudo curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-amd64
sudo chmod +x /usr/local/bin/argocd

# Install Dive (Docker image analyzer)
print_info "Installing Dive..."
DIVE_VERSION=$(curl -s https://api.github.com/repos/wagoodman/dive/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
curl -sL https://github.com/wagoodman/dive/releases/download/${DIVE_VERSION}/dive_${DIVE_VERSION#v}_linux_amd64.tar.gz | sudo tar xz -C /usr/local/bin dive
sudo chmod +x /usr/local/bin/dive

# Configure DNF automatic for security updates
print_info "Configuring automatic security updates..."
cat << 'EOF' | sudo tee /etc/dnf/automatic.conf
[commands]
upgrade_type = security
random_sleep = 3600
keep_cache = false

[emitters]
emit_via = motd

[email]
email_from = root@localhost
email_to = root
email_host = localhost

[base]
debuglevel = 1
EOF

sudo systemctl enable dnf-automatic.timer
sudo systemctl start dnf-automatic.timer

# Enable GNOME extensions (only if GNOME is running)
if [ "$HAS_GNOME" = "true" ]; then
    print_info "Installing GNOME extensions via gext..."
    GEXT_CMD="$HOME/.local/bin/gext"
    if [ -x "$GEXT_CMD" ]; then
        # Install extensions via gext (GNOME 48+ compatible)
        "$GEXT_CMD" -F install monitor@astraext.github.io || true
        "$GEXT_CMD" -F install dash-to-panel@jderose9.github.com || true

        # Compile schemas for Astra Monitor
        ASTRA_SCHEMA_DIR="$HOME/.local/share/gnome-shell/extensions/monitor@astraext.github.io/schemas"
        if [ -d "$ASTRA_SCHEMA_DIR" ]; then
            glib-compile-schemas "$ASTRA_SCHEMA_DIR" || true
        fi

        # Compile schemas for Dash to Panel
        DTP_SCHEMA_DIR="$HOME/.local/share/gnome-shell/extensions/dash-to-panel@jderose9.github.com/schemas"
        if [ -d "$DTP_SCHEMA_DIR" ]; then
            glib-compile-schemas "$DTP_SCHEMA_DIR" || true
        fi
    else
        print_warn "gext not found, skipping extension installation"
    fi

    print_info "Configuring GNOME extensions..."
    gsettings set org.gnome.shell enabled-extensions "['monitor@astraext.github.io', 'appindicatorsupport@rgcjonas.gmail.com', 'dash-to-panel@jderose9.github.com']" || true

    # Configure Astra Monitor extension
    print_info "Configuring Astra Monitor extension..."
    ASTRA_SCHEMA_DIR="$HOME/.local/share/gnome-shell/extensions/monitor@astraext.github.io/schemas"
    if [ -d "$ASTRA_SCHEMA_DIR" ]; then
        export GSETTINGS_SCHEMA_DIR="$ASTRA_SCHEMA_DIR"
        gsettings set org.gnome.shell.extensions.astra-monitor processor-header-show true || true
        gsettings set org.gnome.shell.extensions.astra-monitor memory-header-show true || true
        gsettings set org.gnome.shell.extensions.astra-monitor storage-header-show false || true
        gsettings set org.gnome.shell.extensions.astra-monitor network-header-show false || true
        gsettings set org.gnome.shell.extensions.astra-monitor gpu-header-show false || true
        gsettings set org.gnome.shell.extensions.astra-monitor sensors-header-show false || true
        unset GSETTINGS_SCHEMA_DIR
    fi

    # Enable minimize and maximize buttons on windows
    print_info "Configuring window title bar buttons..."
    gsettings set org.gnome.desktop.wm.preferences button-layout ':minimize,maximize,close' || true

    # Configure dash-to-panel monitor settings
    print_info "Configuring dash-to-panel monitor settings..."
    DTP_SCHEMA_DIR="$HOME/.local/share/gnome-shell/extensions/dash-to-panel@jderose9.github.com/schemas"
    if [ -d "$DTP_SCHEMA_DIR" ]; then
        export GSETTINGS_SCHEMA_DIR="$DTP_SCHEMA_DIR"
        gsettings set org.gnome.shell.extensions.dash-to-panel primary-monitor 'MetaVendor-0x000001' || true
        gsettings set org.gnome.shell.extensions.dash-to-panel trans-use-custom-opacity true || true
        gsettings set org.gnome.shell.extensions.dash-to-panel trans-panel-opacity 0.4 || true
        unset GSETTINGS_SCHEMA_DIR
    fi
fi

# Set wallpaper if it exists (only if GNOME is running)
if [ "$HAS_GNOME" = "true" ]; then
    WALLPAPER_FILE=""
    for ext in jpg png svg; do
        if [ -f "$SCRIPT_DIR/default-background.$ext" ]; then
            WALLPAPER_FILE="$SCRIPT_DIR/default-background.$ext"
            break
        fi
    done

    if [ -n "$WALLPAPER_FILE" ]; then
        print_info "Setting desktop wallpaper..."
        WALLPAPER_NAME=$(basename "$WALLPAPER_FILE")
        sudo cp "$WALLPAPER_FILE" "/usr/share/backgrounds/$WALLPAPER_NAME"
        sudo chmod 644 "/usr/share/backgrounds/$WALLPAPER_NAME"
        gsettings set org.gnome.desktop.background picture-uri "file:///usr/share/backgrounds/$WALLPAPER_NAME" || true
        gsettings set org.gnome.desktop.background picture-uri-dark "file:///usr/share/backgrounds/$WALLPAPER_NAME" || true
        gsettings set org.gnome.desktop.background picture-options "scaled" || true
    fi
fi

# Install Ghostty terminal emulator
if [ "$INSTALL_GHOSTTY" = true ]; then
    print_info "Installing Ghostty terminal emulator..."
    sudo dnf install -y jetbrains-mono-fonts || true
    sudo dnf copr enable -y scottames/ghostty || true
    sudo dnf install -y ghostty || print_info "Ghostty installation skipped"

    # Create Ghostty configuration
    CONFIG_DIR="$HOME/.config/ghostty"
    mkdir -p "$CONFIG_DIR"
    if [ ! -f "$CONFIG_DIR/config" ]; then
        cat > "$CONFIG_DIR/config" << 'EOF'
    # Ghostty Configuration - Fedora Optimized
    # Font Configuration
    font-family = JetBrains Mono
    font-size = 11
    font-feature = calt
    font-feature = liga

    # Theme - Solarized Dark
    theme = iTerm2 Solarized Dark

    # Window Configuration
    window-height = 35
    window-width = 140
    window-padding-x = 8
    window-padding-y = 8
    window-save-state = always

    # Transparency - disabled for RDP optimization
    background-opacity = 1.0
    unfocused-split-opacity = 1.0

    # Performance - VSync disabled for RDP
    window-vsync = false
    gtk-single-instance = false

    # Scrollback
    scrollback-limit = 10000

    # Cursor
    cursor-style = block
    cursor-style-blink = true

    # Shell Integration
    shell-integration = detect
    shell-integration-features = cursor,sudo,title

    # Mouse Behavior
    mouse-hide-while-typing = true

    # Keybindings
    keybind = ctrl+shift+c=copy_to_clipboard
    keybind = ctrl+shift+v=paste_from_clipboard
    keybind = ctrl+shift+t=new_tab
    keybind = ctrl+shift+n=new_window
    keybind = ctrl+plus=increase_font_size:1
    keybind = ctrl+minus=decrease_font_size:1
    keybind = ctrl+zero=reset_font_size
EOF
    fi
else
    print_info "Ghostty installation skipped (--no-ghostty flag)"
fi

print_info "Installation Complete"

# Simple verification - check if key tools actually work
print_info "Verifying installation..."
echo ""
echo "Core Tools:"
docker --version &>/dev/null && echo "  [OK] Docker Engine" || echo "  [FAIL] Docker Engine"
git --version &>/dev/null && echo "  [OK] Git" || echo "  [FAIL] Git"
git lfs version &>/dev/null && echo "  [OK] Git LFS" || echo "  [FAIL] Git LFS"

# GUI tools - only check if GNOME is available
if [ "$HAS_GNOME" = "true" ]; then
    [ -f /usr/share/applications/docker-desktop.desktop ] && echo "  [OK] Docker Desktop" || echo "  [FAIL] Docker Desktop"
    code --version &>/dev/null && echo "  [OK] VS Code" || echo "  [FAIL] VS Code"
    google-chrome --version &>/dev/null && echo "  [OK] Chrome" || echo "  [FAIL] Chrome"
fi

if [ "$INSTALL_GHOSTTY" = true ]; then
    echo ""
    echo "Terminal:"
    ghostty --version &>/dev/null && echo "  [OK] Ghostty" || echo "  [FAIL] Ghostty"
    fc-list | grep -q "JetBrains Mono" && echo "  [OK] JetBrains Mono font" || echo "  [FAIL] JetBrains Mono font"
fi

echo ""
echo "Cloud/DevOps Tools:"
aws --version &>/dev/null && echo "  [OK] AWS CLI" || echo "  [FAIL] AWS CLI"
kubectl version --client=true -o yaml &>/dev/null && echo "  [OK] Kubectl" || echo "  [FAIL] Kubectl"
helm version &>/dev/null && echo "  [OK] Helm" || echo "  [FAIL] Helm"
helm plugin list 2>/dev/null | grep -q dashboard && echo "  [OK] Helm Dashboard" || echo "  [FAIL] Helm Dashboard"
k9s version &>/dev/null && echo "  [OK] K9s" || echo "  [FAIL] K9s"
if [ "$HAS_GNOME" = "true" ]; then
    flatpak list --user 2>/dev/null | grep -q app.freelens.Freelens && echo "  [OK] Freelens" || echo "  [FAIL] Freelens"
fi
terraform --version &>/dev/null && echo "  [OK] Terraform" || echo "  [FAIL] Terraform"
vault --version &>/dev/null && echo "  [OK] Vault" || echo "  [FAIL] Vault"
argocd version --client &>/dev/null && echo "  [OK] ArgoCD" || echo "  [FAIL] ArgoCD"

echo ""
echo "Data/Analytics Tools:"
confluent version &>/dev/null && echo "  [OK] Confluent CLI" || echo "  [FAIL] Confluent CLI"
clickhouse-client --version &>/dev/null && echo "  [OK] ClickHouse Client" || echo "  [FAIL] ClickHouse Client"
vector --version &>/dev/null && echo "  [OK] Vector" || echo "  [FAIL] Vector"

echo ""
echo "Development Tools:"
jq --version &>/dev/null && echo "  [OK] jq" || echo "  [FAIL] jq"
yq --version &>/dev/null && echo "  [OK] yq" || echo "  [FAIL] yq"
bat --version &>/dev/null && echo "  [OK] bat" || echo "  [FAIL] bat"
rg --version &>/dev/null && echo "  [OK] ripgrep" || echo "  [FAIL] ripgrep"

# Update all system packages to latest versions
echo ""
print_info "Updating all system packages to latest versions..."
print_info "This may take a few minutes..."
sudo dnf update -y || print_warning "Some packages failed to update, but continuing"

echo ""
print_info "IMPORTANT: A system reboot is recommended to ensure all changes take effect"
print_info "This includes kernel updates, systemd services, and Docker group membership"
print_success "Hyperi Developer Environment setup complete"
print_info "Please reboot your system: sudo reboot"