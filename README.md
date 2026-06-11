# DFE Developer Environment

[![Latest Release](https://img.shields.io/github/v/release/hyperi-io/dfe-developer)](https://github.com/hyperi-io/dfe-developer/releases/latest)
[![Release Date](https://img.shields.io/github/release-date/hyperi-io/dfe-developer)](https://github.com/hyperi-io/dfe-developer/releases/latest)
[![License](https://img.shields.io/github/license/hyperi-io/dfe-developer)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Ubuntu%20%7C%20Fedora%20%7C%20macOS-blue)](#platform-support)
[![Last Commit](https://img.shields.io/github/last-commit/hyperi-io/dfe-developer)](https://github.com/hyperi-io/dfe-developer/commits/main)
[![Stars](https://img.shields.io/github/stars/hyperi-io/dfe-developer?style=social)](https://github.com/hyperi-io/dfe-developer/stargazers)

Standardised developer environment for HyperSec DFE teams. One command gets you Docker, Kubernetes tools, cloud CLIs, and a properly configured desktop.

## Platform Support

| Platform | Status | Notes |
|----------|--------|-------|
| **Ubuntu 24.04** | Fully tested | Primary platform |
| **Fedora 42** | Fully tested | GNOME 48 compatible |
| **macOS Sequoia** | Fully tested | Homebrew-based |
| **Windows 11** | Productivity host | Hyper-V for Linux VMs |

## Installation

The DFE developer environment installs as a set of composable profiles.

### Profiles

- **`developer`** — OSS-safe base for external contributors on DFE/ESH. No Hyperi internals.
- **`core`** — Hyperi internal tier (implies `developer`). Adds Slack, Linear, JFrog, rclone, WireGuard, branding.
- **`rust`** — Rust toolchain + cargo tooling.
- **`iac`** — Terraform, Vault, Helm, Kubernetes CLI set.
- **`gui_extras`** — Freelens, Bruno, Podman Desktop, DBeaver Community, lazygit.
- **`openvpn`** — Transitional legacy VPN (requires `core`). Scheduled for removal once WireGuard migration completes.

### Common invocations

    ./install.sh --profile developer          # External contributor (minimal)
    ./install.sh --profile core               # Hyperi dev (minimal)
    ./install.sh --profile core,all           # Hyperi + rust + iac + gui_extras
    ./install.sh --profile core,openvpn       # Hyperi + legacy VPN (transition)

### Opt-out individual tools

    ./install.sh --profile core --extra-vars "install_slack=false"

See [docs/TOOLS.md](docs/TOOLS.md) for the full tool list and rationale.

### Deprecations

- `--core` and `--all` are aliased (with a warning) for one release, then removed.
  Replace with `--profile core,rust,iac` and `--profile core,all` respectively.
- `--tags developer_core` is **not** aliased — scripts/CI using this tag must be
  updated to `--profile core,rust,iac`.

## Requirements

- **Ubuntu 24.04+**, **Fedora 42+**, or **macOS Sequoia**
- 8GB RAM recommended
- 20GB disk space
- Internet connection

## Project Structure

- `ansible/` - Ansible-based multi-platform installer (Fedora, Ubuntu, macOS)
- `fedora/` - Legacy Fedora Linux installation scripts (bug fixes only)
- `windows/` - Windows 11 SOE setup scripts and documentation
- `tools/` - Developer utilities and helper scripts
  - `tools/git/` - Git-related utilities
- `docs/` - Documentation and guides
- `VERSION` - Version tracking
- `CHANGELOG.md` - Release history
- `TODO.md` - Task tracking

## Developer Utilities

### Git Data Spill Cleanup

The [git-spill-cleanup.sh](tools/git/git-spill-cleanup.sh) utility safely removes sensitive data accidentally committed to git history.

**Use cases:** Remove `.env` files, API keys, passwords, private keys, or any sensitive data from git history.

```bash
# List potentially sensitive files in history
./tools/git/git-spill-cleanup.sh --list

# Remove a specific file from all history
./tools/git/git-spill-cleanup.sh --file .env

# Remove entire directory and all contents
./tools/git/git-spill-cleanup.sh --directory .claude

# Remove all AI assistant artifacts
./tools/git/git-spill-cleanup.sh --ai

# Remove all files matching a pattern
./tools/git/git-spill-cleanup.sh --pattern "*.pem"

# Remove a specific string from all files
./tools/git/git-spill-cleanup.sh --string "sk-abc123secretkey"

# Dry run to preview changes
./tools/git/git-spill-cleanup.sh --file secrets.yml --dry-run
```

**Features:**
- Uses git-filter-repo (modern, GitHub-recommended tool)
- Automatic backups before cleanup (stored in `~/.git-spill-backups/`)
- Remove files, directories, or patterns (wildcards)
- Remove AI assistant artifacts with `--ai` option (Claude, Cursor, Aider, Continue, Copilot, Windsurf, Codeium, Tabnine, etc.)
- String/text removal from all files in history
- Dry-run mode for safe testing
- Friendly install guidance if git-filter-repo is missing
- Comprehensive safety checks and warnings

**Documentation:** See [tools/git/README.md](tools/git/README.md) for detailed usage guide, scenarios, and troubleshooting.

### Git Claude Contributor Fix

The [git-claude-contrib-fix.sh](tools/git/git-claude-contrib-fix.sh) script removes Claude Code from GitHub contributors when it autonomously adds itself without permission.

**Problem:** Claude Code sometimes adds "Co-Authored-By: Claude" attribution to commits without explicit user consent, causing Claude to appear as a repository contributor on GitHub.

**Usage:**

```bash
# Use current repository with default branch
cd dfe-developer
./tools/git/git-claude-contrib-fix.sh

# Specify repository URL
./tools/git/git-claude-contrib-fix.sh https://github.com/owner/repo.git

# Specify repository and branch
./tools/git/git-claude-contrib-fix.sh https://github.com/owner/repo.git develop
```

**Features:**
- Removes "Co-Authored-By: Claude" and "Generated with Claude Code" from commit messages
- Auto-detects repository default branch (main, master, etc.)
- Optional branch parameter to clean specific branches
- For default branch: forces GitHub contributor reindex
- For non-default branches: only cleans commits (no gh CLI required)
- Comprehensive error handling and automatic cleanup

**Requirements:**
- git (required)
- gh (GitHub CLI) - only required when working on default branch
- Push access to the repository

**Documentation:** See [tools/git/README.md](tools/git/README.md) for detailed usage guide, scenarios, and troubleshooting.

**Help:**
```bash
./tools/git/git-claude-contrib-fix.sh --help
```

## Windows 11 SOE

Automated Windows 11 Standard Operating Environment setup for HyperSec DFE developers.

### Overview

Automated Windows 11 configuration for development teams. Installs essential software, enables Hyper-V with full security stack (VBS, Credential Guard, HVCI), removes bloatware, disables telemetry, and configures Australian English locale. Security-first approach using Windows 11's native hypervisor - actual development work happens in Linux VMs while Windows serves as the productivity and VM host platform.

### Quick Start

```powershell
# Run as Administrator in PowerShell
cd windows
.\hypersec-windows.ps1                    # Complete SOE with Hyper-V
.\hypersec-windows.ps1 -SkipVSCode       # Skip VSCode (if running from VSCode)
.\hypersec-windows.ps1 -IncludeM365      # Include Microsoft 365 installation
.\hypersec-windows.ps1 -ShowHelp         # Display detailed help
```

### Software Installation

- **Development Tools** - Git, PowerShell 7, Visual Studio Code, GitHub Desktop, WinMerge
- **Browsers** - Firefox, Chrome (manual default setting required)
- **Office Suite** - Microsoft 365 Business (optional with -IncludeM365)
- **Network Tools** - PuTTY, WinSCP, OpenVPN GUI, TigerVNC
- **Media & Utilities** - VLC, 7-Zip, OBS Studio, Paint.NET, PDFGear
- **Communication** - Slack, Microsoft Teams (with M365)

### System Configuration

- **Privacy** - Telemetry disabled, bloatware removed
- **Regional Settings** - Australian English locale, timezone, date/currency formats
- **Power Management** - Laptop/desktop detection with appropriate settings
- **Desktop** - Clean appearance, no unnecessary shortcuts
- **Custom Wallpaper** - Optional SVG wallpaper support

### Hyper-V Virtualization

- **Native hypervisor** - Uses Windows 11's built-in Hyper-V
- **C:\VM structure** - Automatic directory creation and configuration
- **Default Switch** - Automatic network switch assignment for new VMs
- **Security intact** - All Windows security features remain enabled
- **Linux VM Setup** - See `windows/HYPERV-LINUX.md` for detailed guide

### Security Configuration

- **Virtualization-Based Security (VBS)** - Hardware-backed protection enabled
- **Credential Guard** - Credential isolation via hypervisor
- **HVCI** - Hypervisor-enforced kernel code integrity
- **Core Isolation** - Memory integrity protection
- **Defender ATP** - Optional automated onboarding (drop package in directory)

### Windows Requirements

- **Windows 11 Pro** (24H2 or later recommended, Build 26100+)
- **Administrator privileges**
- **Internet connection**
- **TPM 2.0** (for VBS/Credential Guard)
- **UEFI firmware** (for modern security features)

### Additional Documentation

- **windows/QUICKSTART.md** - Fast setup guide with Hyper-V configuration
- **windows/HYPERV-LINUX.md** - Step-by-step guide for creating Linux VMs in Hyper-V
- **windows/CHANGELOG.md** - Windows SOE version history and release notes

### Why Hyper-V Instead of VMware?

VMware Workstation delivers better Linux VM performance, but requires disabling Windows security features (VBS, Credential Guard, HVCI, Core Isolation). We prioritize security over marginal performance gains. For legacy VMware users, `hypersec-windows-vmware.ps1` exists but is deprecated and unmaintained.

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for:
- How to submit pull requests
- Code standards and style guidelines
- Testing requirements
- Development workflow

## License

Apache License 2.0 - See [LICENSE](LICENSE) file for details.
