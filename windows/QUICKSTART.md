# HyperSec Windows SOE - Quick Start

Your Windows 11 machine configured with proper security in about 20 minutes.

## Prerequisites

⚠️ **Heads up:** This script makes significant system changes. It's been tested extensively on clean Windows 11 installs, and should work fine on existing systems, but having a backup never hurt anyone.

What you'll need:
- ✅ **Windows 11 Pro** (Home edition might work but some security features need Pro)
- ✅ **All Windows Updates** applied
- ✅ **Latest hardware drivers** (particularly graphics, network, storage)
- ✅ **Administrator access**
- ✅ **Internet connection**
- ✅ **Recent backup** (script creates automatic restore points, but better safe than sorry)
- ✅ **TPM 2.0 and UEFI firmware** (for VBS and Credential Guard)

### System Compatibility
- **✅ Clean installations** - Tested thoroughly, works well
- **⚠️ Existing installations** - Should work, but changes a fair bit:
  - Registry tweaks (privacy, power, file associations)
  - Service modifications (turns off telemetry and background noise)
  - Windows features (enables Hyper-V, VBS, Credential Guard, HVCI)
  - Built-in bloatware removal and telemetry disabling
  - Default app associations (Firefox, VLC, PDFGear)
  - Startup program cleanup

## Setup

### Step 1: Download
```powershell
git clone https://github.com/hyperi-io/hyperi-developer.git
cd hyperi-developer/windows
```

### Step 2: Run the Script
Right-click PowerShell, **Run as administrator**, then:

```powershell
# Standard installation with Hyper-V
.\hypersec-windows.ps1

# Skip VSCode if you're running from VSCode
.\hypersec-windows.ps1 -SkipVSCode

# Include Microsoft 365 installation
.\hypersec-windows.ps1 -IncludeM365
```

### Step 3: Restart
Restart when prompted. Hyper-V and security features need a reboot to activate.

## What You Get

### Software Installed
- **Office 365 Business** (Outlook, Word, Excel, PowerPoint, Teams) - optional with -IncludeM365
- **Development Tools** (Git, PowerShell 7, Visual Studio Code, GitHub Desktop, WinMerge)
- **Browsers** (Firefox, Chrome - you'll need to set default manually)
- **Network Tools** (PuTTY, WinSCP, OpenVPN GUI, TigerVNC)
- **Media & Utilities** (VLC, 7-Zip, OBS Studio, Paint.NET)
- **Communication** (Slack)
- **Cloud Storage** (Microsoft OneDrive)

### System Configuration
- **Privacy tweaks** - Telemetry off, bloatware removed (built-in to script)
- **Australian English** - Proper date/currency formats, timezone
- **Clean desktop** - No unnecessary shortcuts
- **Power settings** - Adjusted for laptop or desktop use
- **Hyper-V enabled** - VBS, Credential Guard, HVCI, Core Isolation all active

### Security Features
- **Virtualization-Based Security (VBS)** - Hardware-backed protection
- **Credential Guard** - Credentials protected by hypervisor
- **HVCI** - Kernel code integrity enforced by hypervisor
- **Core Isolation** - Memory integrity protection
- **No compromises** - All security features stay enabled

## Using Hyper-V VMs

### Creating a New VM
1. **Open Hyper-V Manager** (search for it in Start menu)
2. **New → Virtual Machine** from the Actions panel
3. **Choose Generation 2** for Windows/modern Linux, Generation 1 for older OSes
4. **Set memory** - 4GB is a good start for most VMs
5. **Use Default Switch** for networking (script sets this up automatically)
6. **Create virtual hard disk** - stored in `C:\VM\Virtual Hard Disks` by default
7. **Install from ISO** or network

### Default Configuration
The script sets up:
- **VM storage:** `C:\VM\Hyper-V`
- **VHD storage:** `C:\VM\Virtual Hard Disks`
- **Default Switch:** Automatically assigned to new VMs via scheduled task
- **Security:** All Hyper-V VMs benefit from VBS, Credential Guard, HVCI

## Troubleshooting

### Common Issues

**"Not run as Administrator"**
- Right-click PowerShell → Run as administrator, then run the script

**Software installation fails**
- Check your internet connection
- Run the script again - it's designed to handle reruns safely

**Hyper-V not working after restart**
- Check your BIOS/UEFI - virtualization must be enabled
- Windows 11 Home edition has limited Hyper-V support
- TPM 2.0 required for VBS/Credential Guard

**VMs won't connect to network**
- Check Hyper-V Manager → Virtual Switch Manager
- Default Switch should exist (created automatically by Windows)
- Script creates a scheduled task to assign Default Switch to new VMs

### Log Files
Check logs in your home directory if something goes wrong:
- `%USERPROFILE%\hypersec-windows.log` - Installation and configuration details
- `%USERPROFILE%\hypersec-windows-vmware.log` - VMware script log (if used)

## Advanced Options

### Custom Wallpaper
Drop a `default-background.svg` file in the script directory and it'll be converted and applied automatically.

### Windows Defender ATP Onboarding
Put your `GatewayWindowsDefenderATPOnboardingPackage.zip` in the script directory for automatic Defender ATP setup.

### Revert Changes
The script creates system restore points automatically. Use Windows System Restore if you need to roll back changes.

## Post-Installation Setup

A few things you'll need to do manually after the script runs:

### Required Steps

1. **Set Default Browser**
   - Open **Settings > Apps > Default apps**
   - Search for **Firefox** (or Chrome if you prefer)
   - Click **Set default**
   - Why manual? Windows 11 24H2 blocks automated browser defaults for security reasons

2. **Sign into Microsoft 365** with your work account (if you used -IncludeM365)

3. **Configure Slack** with your workspace

4. **Set up Git** with your details:
   ```powershell
   git config --global user.name "Your Name"
   git config --global user.email "your.email@example.com"
   ```

5. **Configure development tools** as needed for your workflow

## What to Expect

### After Running the Script
- **Clean desktop** - no junk shortcuts
- **Essential software** installed and ready to use
- **Privacy tweaks** applied - telemetry off, bloatware gone
- **Development tools** configured - Git, PowerShell 7, VSCode, etc.
- **Hyper-V enabled** - full security stack active (VBS, Credential Guard, HVCI)

### System Impact
- **~10-15GB disk space** used for software
- **Australian English** configured - proper date/currency formats
- **No consumer nonsense** - promotional apps and suggestions removed
- **Security enabled** - all Windows 11 security features active, nothing disabled

### About VMware
The old VMware-focused approach is deprecated. While VMware provides better Linux VM performance, it requires disabling VBS, Credential Guard, HVCI, and other core security features. In 2025, that's not an acceptable trade-off for most environments. If you absolutely need VMware, the `hypersec-windows-vmware.ps1` script is still there, but it won't be maintained.

---

**Need more info?** Check the [README.md](README.md) for details.

*Configured for Australian development teams who care about security.*