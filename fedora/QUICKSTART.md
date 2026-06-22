# HyperSec Fedora Hyperi - Quick Start

Your Fedora Linux development environment configured in about 30 minutes.

## Prerequisites

What you'll need:
- Fedora 42 or later (clean install recommended)
- 4GB RAM minimum (8GB+ recommended)
- 20GB available disk space
- Internet connection
- sudo/root access

## Setup

### Step 1: Clone Repository

```bash
git clone https://github.com/hyperi-io/hyperi-developer.git
cd hyperi-developer/fedora
```

### Step 2: Run Main Installer

```bash
# Standard developer installation
./install-hyperi-developer.sh

# With passwordless sudo (optional)
./install-hyperi-developer.sh --sudoers
```

### Step 3: Optional Components

```bash
# Core Hyperi contributor tools (JFrog, Azure CLI, Node.js, Claude Code CLI)
./install-hyperi-developer-core.sh

# VM/RDP optimizations (if running in VM)
./install-vm-optimizer.sh
./install-rdp-optimizer.sh

# Ghostty terminal (optional)
./install-ghostty.sh
```

## What You Get

### Standard Developer Tools
- **Docker CE** - Container platform with compose plugin
- **Python Development** - UV package manager, pyenv version management
- **Cloud Tools** - AWS CLI, kubectl, Helm + Dashboard, Terraform, Vault
- **Kubernetes** - K9s, Freelens IDE, Minikube, ArgoCD CLI
- **Development Utilities** - jq, yq, bat, fzf, ripgrep, fd-find, httpie
- **Git Tools** - Git LFS, GitHub CLI (gh)
- **VS Code** - Configured for development

### Hyperi Core Developer Tools (Optional)
- **JFrog CLI** - Artifact repository management
- **Azure CLI** - Azure cloud platform tools
- **Node.js** - JavaScript runtime with semantic-release
- **Claude Code CLI** - AI-powered coding assistant
- **Advanced Python** - Nox testing framework
- **Slack** - Team communication (Flatpak)

### VM Optimizations (Optional)
- Reduced GNOME resource usage
- Optimized graphics settings
- RDP enhancements for remote access
- Improved performance for virtualized environments

## Post-Installation

### Configure Git

```bash
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"
```

### Configure Docker

```bash
# Add your user to docker group (logout/login required)
sudo usermod -aG docker $USER
```

### Configure Claude Code CLI (if installed)

```bash
# Login to Claude Code
claude login

# Start coding with AI assistance
claude
```

## Testing Your Installation

```bash
# Run comprehensive tests
cd tests
bash 01-shellcheck.sh      # Static analysis
bats *.bats                # Unit and integration tests
```

## Troubleshooting

### Docker Issues
If Docker commands fail with permission errors after installation:
```bash
# Logout and login again for group membership to take effect
# Or restart your session
```

### Python/UV Issues
```bash
# Ensure shell is reloaded
exec $SHELL
```

### VS Code Issues
If VS Code doesn't launch:
```bash
# Check if installed
code --version

# Reinstall if needed
sudo dnf install code -y
```

## What's Installed Where

- **Docker** - System-wide service
- **Python tools** - `~/.local/bin` (UV, pyenv)
- **Cloud CLIs** - `/usr/local/bin`
- **Flatpak apps** - User-level installation
- **VS Code** - System package manager

## Next Steps

1. **Restart your terminal** to load all environment changes
2. **Verify installations** - Run `docker --version`, `kubectl version --client`, `aws --version`
3. **Configure cloud credentials** - AWS, Azure, Kubernetes as needed
4. **Start developing** - All tools are ready to use

## Additional Documentation

- **[README.md](README.md)** - Complete installation guide and tool details
- **[../CONTRIBUTING.md](../CONTRIBUTING.md)** - Contribution guidelines
- **[../CHANGELOG.md](../CHANGELOG.md)** - Version history and changes

---

**Need help?** Check the main [README.md](README.md) or open an issue on GitHub.
