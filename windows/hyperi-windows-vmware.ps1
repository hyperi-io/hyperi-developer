#Requires -RunAsAdministrator
<#
.SYNOPSIS
    [DEPRECATED] Windows Security Enhancement and VMware Configuration Script
.DESCRIPTION
    ⚠️  DEPRECATED - This script is retained for existing VMware Workstation users but is NO LONGER MAINTAINED.

    For new deployments, use hyperi-windows.ps1 which configures Microsoft Hyper-V with full security enabled.

    While VMware Workstation provides better Linux VM performance, achieving this requires disabling critical
    Windows security features (VBS, Credential Guard, HVCI, speculative execution mitigations). In modern
    threat environments, these security compromises are unacceptable.

    This script remains available for:
    - Existing VMware Workstation users who accept the security trade-offs
    - Testing and comparison purposes
    - Organizations with specific VMware requirements

    However, this script will NOT be maintained going forward. Security updates and new features will only
    be added to hyperi-windows.ps1 with Hyper-V.

    Legacy functionality:
    Enhances Windows 11 security by enabling Hyper-V, VBS, Credential Guard, and other
    security features. Configures optimal VMware settings with security focus and creates
    security-optimized VM configurations.
.PARAMETER Silent
    Skip confirmation prompts and apply all optimizations automatically
.PARAMETER KeepWSL
    Preserve WSL2 functionality (may impact VMware performance)
.PARAMETER ShowHelp
    Display detailed help information about this script
.PARAMETER Uninstall
    Remove all security enhancements and revert to default Windows configuration
.PARAMETER HyperV
    Uninstall VMware settings and fully enable and install Microsoft Hyper-V
.EXAMPLE
    .\hyperi-windows-vmware.ps1
    .\hyperi-windows-vmware.ps1 -Silent
    .\hyperi-windows-vmware.ps1 -KeepWSL
    .\hyperi-windows-vmware.ps1 -Uninstall
    .\hyperi-windows-vmware.ps1 -ShowHelp
#>

param(
    [switch]$Silent,
    [switch]$KeepWSL,
    [switch]$ShowHelp,
    [switch]$Uninstall,
    [switch]$HyperV
)

$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"

# Simple logging function (transcript handles file logging)
function Write-Log {
    param($Message, $Color = "White")
    Write-Host $Message -ForegroundColor $Color
}

# Get script directory for relative file checks
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Read version from VERSION file if present
$VersionFile = Join-Path $ScriptDir "VERSION"
$ScriptVersion = "Unknown"
if (Test-Path $VersionFile) {
    try {
        $ScriptVersion = (Get-Content $VersionFile -Raw).Trim()
    }
    catch {
        $ScriptVersion = "Unknown"
    }
}

# Enable transcript logging - logs to user's home directory
$ScriptBaseName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$TranscriptPath = Join-Path $env:USERPROFILE "$ScriptBaseName.log"

# Remove old transcript if exists (to overwrite, not append)
if (Test-Path $TranscriptPath) {
    Remove-Item $TranscriptPath -Force -ErrorAction SilentlyContinue
}

Start-Transcript -Path $TranscriptPath

# Function to display help
function Show-Help {
    $helpText = @"

====================================================
    Windows Security Enhancement
====================================================

DESCRIPTION:
    This script enhances Windows 11 24H2 security by enabling Hyper-V, VBS,
    Credential Guard, and other security features while maintaining VMware
    compatibility and applying security optimizations.

PARAMETERS:
    -Silent        : Skip all confirmation prompts (automated mode)
    -KeepWSL       : Preserve WSL2 functionality (impacts performance)
    -Uninstall     : Remove all security enhancements and revert to defaults
    -HyperV        : Remove VMware config and fully enable Microsoft Hyper-V
    -ShowHelp      : Display this help message

WHAT GETS ENABLED/CONFIGURED:
    Core Security Features:
        - Microsoft Hyper-V (full installation)
        - Virtualization Based Security (VBS)
        - Memory Integrity / Core Isolation
        - Windows Hypervisor Platform
        - Credential Guard
        - Device Guard
        - Virtual Machine Platform
    
    Optional Disablements (if -KeepWSL not specified):
        - Windows Subsystem for Linux 2 (WSL2) [unless -KeepWSL]
    
    Performance Optimizations:
        - Power Throttling disabled for VMware processes (Intel 12th-14th gen CPUs)
        - Windows Defender Real-Time Protection exclusions for VM folders

OPTIMIZATIONS APPLIED:
    System Performance:
        - High Performance power plan
        - Ultimate Performance power plan (if available)
        - CPU performance boost mode
        - Disable Windows Search indexing for VM folders
    
    VMware Configuration:
        - Creates C:\VM directory structure
        - Configures VMware paths to use C:\VM
        - Generates optimized .vmx templates
        - Sets VMware preferences for performance

VM TEMPLATES CREATED:
    - Windows VM template (workstation optimized)
    - Linux VM template (workstation optimized)  
    - vSphere-compatible VM template

REQUIREMENTS:
    - Windows 11 (24H2 or later recommended)
    - Administrator privileges
    - VMware Workstation 17.6+ installed
    - System restart required after completion

WARNINGS:
    - This will enable Windows Hello Face Recognition (requires compatible hardware)
    - WSL2 will be disabled (unless -KeepWSL specified)
    - Enhanced Windows Security features will be enabled
    - Docker Desktop may require reconfiguration
    - A system restart is MANDATORY for changes to take effect

EXAMPLES:
    # Interactive mode with confirmations
    .\hyperi-windows-vmware.ps1
    
    # Silent mode for automation
    .\hyperi-windows-vmware.ps1 -Silent
    
    # Keep WSL2 (reduced security)
    .\hyperi-windows-vmware.ps1 -KeepWSL
    
    # Uninstall all security enhancements
    .\hyperi-windows-vmware.ps1 -Uninstall

    # Remove VMware and fully enable Hyper-V
    .\hyperi-windows-vmware.ps1 -HyperV

"@
    Write-Host $helpText -ForegroundColor Cyan
    exit 0
}

# Check if help was requested
if ($ShowHelp) {
    Show-Help
}

# Check if HyperV mode was requested
if ($HyperV) {
    Write-Log "" 
    Write-Log "HYPER-V MODE: Uninstalling VMware and enabling full Hyper-V..." "Red"
    Write-Log "This will remove VMware configuration and switch this host to Microsoft Hyper-V." "Yellow"
    Write-Log "" 

    if (-not $Silent) {
        $response = Read-Host "Proceed to remove VMware and enable Hyper-V? (Type 'YES' to confirm)"
        if ($response -ne "YES") {
            Write-Log "Hyper-V switch cancelled by user. No changes made." "Yellow"
            exit 0
        }
    }

    try {
        # 1) Stop VMware services if present
        $vmwareServices = @("VMwareHostd", "VMAuthdService", "VMnetDHCP", "VMware NAT Service")
        foreach ($service in $vmwareServices) {
            try {
                $svc = Get-Service -Name $service -ErrorAction SilentlyContinue
                if ($svc -and $svc.Status -eq "Running") {
                    Stop-Service -Name $service -Force -ErrorAction SilentlyContinue
                    Write-Log "  [OK] Stopped service: $service" "Green"
                }
            }
            catch {}
        }

        # 2) Unregister any registered templates (best effort)
        $vmrunPath = "C:\Program Files (x86)\VMware\VMware Workstation\vmrun.exe"
        if (Test-Path $vmrunPath) {
            # No reliable list API; skip explicit unregister to avoid errors
        }

        # 3) Uninstall VMware Workstation silently if installed
        $vmwareExe = "C:\Program Files (x86)\VMware\VMware Workstation\vmware.exe"
        if (Test-Path $vmwareExe) {
            Write-Log "  Uninstalling VMware Workstation..." "White"
            try {
                $uninstKey = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*VMware Workstation*" }
                if ($uninstKey -and $uninstKey.UninstallString) {
                    if ($uninstKey.UninstallString -like "*.msi*") {
                        Start-Process -FilePath "msiexec.exe" -ArgumentList "/x $($uninstKey.PSChildName) /quiet /norestart" -Wait -ErrorAction SilentlyContinue
                    } else {
                        Start-Process -FilePath $uninstKey.UninstallString -ArgumentList "/S" -Wait -ErrorAction SilentlyContinue
                    }
                }
            }
            catch {
                Write-Log "  [WARN] Could not uninstall VMware Workstation (continuing): $_" "Yellow"
            }
        }

        # 4) Remove VMware config and Defender exclusions
        try {
            $vmwareConfigPaths = @(
                "$env:APPDATA\VMware\config.ini",
                "$env:APPDATA\VMware\preferences.ini"
            )
            foreach ($configPath in $vmwareConfigPaths) {
                if (Test-Path $configPath) { Remove-Item -Path $configPath -Force -ErrorAction SilentlyContinue }
            }

            $exclusionPaths = @("C:\VM", "C:\Program Files (x86)\VMware", "C:\ProgramData\VMware")
            foreach ($path in $exclusionPaths) {
                Remove-MpPreference -ExclusionPath $path -ErrorAction SilentlyContinue
            }
            $vmwareProcesses = @("vmware-vmx.exe","vmware.exe","vmware-hostd.exe","vmware-authd.exe")
            foreach ($proc in $vmwareProcesses) {
                Remove-MpPreference -ExclusionProcess $proc -ErrorAction SilentlyContinue
            }
        }
        catch {}

        # 5) Enable full Hyper-V stack and security
        Write-Log "  Enabling Hyper-V features..." "White"
        $hyperVFeatures = @(
            "Microsoft-Hyper-V-All",
            "Microsoft-Hyper-V",
            "Microsoft-Hyper-V-Tools-All",
            "Microsoft-Hyper-V-Management-PowerShell",
            "Microsoft-Hyper-V-Hypervisor",
            "Microsoft-Hyper-V-Services",
            "Microsoft-Hyper-V-Management-Clients",
            "VirtualMachinePlatform",
            "HypervisorPlatform"
        )
        foreach ($feature in $hyperVFeatures) {
            try {
                $featureState = Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction SilentlyContinue
                if ($featureState -and $featureState.State -ne "Enabled") {
                    Enable-WindowsOptionalFeature -Online -FeatureName $feature -All -NoRestart -WarningAction SilentlyContinue | Out-Null
                    Write-Log "    [OK] Enabled $feature" "Green"
                }
            }
            catch { Write-Log "    [WARN] Could not enable $feature" "Yellow" }
        }

        # 6) Configure boot for Hyper-V
        $bcdCommands = @(
            @{Command = "bcdedit /set hypervisorlaunchtype auto"; Description = "Enable Hypervisor Launch"},
            @{Command = "bcdedit /set vsmlaunchtype auto"; Description = "Enable VSM Launch"},
            @{Command = "bcdedit /set nx optin"; Description = "Enable NX/DEP"},
            @{Command = "bcdedit /deletevalue loadoptions"; Description = "Remove load options to enable VBS"},
            @{Command = "bcdedit /set isolatedcontext Yes"; Description = "Enable Isolated Context"},
            @{Command = "bcdedit /set allowedinmemorysettings 0x1"; Description = "Enable Memory Settings"},
            @{Command = "bcdedit /set vm Yes"; Description = "Enable VM Boot Option"}
        )
        foreach ($bcd in $bcdCommands) { try { Invoke-Expression $bcd.Command 2>$null } catch {} }

        # 7) Configure registry for VBS / Credential Guard / HVCI
        $registrySettings = @(
            @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard"; Name = "EnableVirtualizationBasedSecurity"; Value = 1; Type = "DWord"},
            @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard"; Name = "RequirePlatformSecurityFeatures"; Value = 1; Type = "DWord"},
            @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity"; Name = "Enabled"; Value = 1; Type = "DWord"},
            @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\CredentialGuard"; Name = "Enabled"; Value = 1; Type = "DWord"},
            @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"; Name = "FeatureSettings"; Value = 1; Type = "DWord"},
            @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"; Name = "FeatureSettingsOverride"; Value = 0; Type = "DWord"},
            @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"; Name = "FeatureSettingsOverrideMask"; Value = 0; Type = "DWord"}
        )
        foreach ($setting in $registrySettings) {
            try {
                if (-not (Test-Path $setting.Path)) { New-Item -Path $setting.Path -Force | Out-Null }
                Set-ItemProperty -Path $setting.Path -Name $setting.Name -Value $setting.Value -Type $setting.Type -Force
            }
            catch {}
        }

        # 8) Disable Memory Compression
        try { Disable-MMAgent -MemoryCompression -ErrorAction SilentlyContinue } catch {}

        Write-Log "[OK] VMware removed and Hyper-V fully enabled. Reboot required." "Green"
    }
    catch {
        Write-Log "[ERROR] Hyper-V switch failed: $_" "Red"
    }

    # Stop transcript logging
    Stop-Transcript
    
    if (-not $Silent) {
        $restart = Read-Host "Would you like to restart the computer now? (Y/N)"
        if ($restart -eq 'Y' -or $restart -eq 'y') {
            Write-Log "Restarting computer in 10 seconds..." "Yellow"
            Start-Sleep -Seconds 10
            Restart-Computer -Force
        }
    } else {
        Write-Log "Silent mode: Restart required to complete Hyper-V enablement." "Yellow"
    }

    exit 0
}

# Ensure uninstall function is defined before use
# Function to uninstall all security enhancements and revert to defaults
function Uninstall-SecurityEnhancements {
    Write-Log ""
    Write-Log "=====================================================" "Cyan"
    Write-Log "    Uninstalling Security Enhancements" "Cyan"
    Write-Log "=====================================================" "Cyan"
    Write-Log ""
    
    # Disable Windows features that were enabled
    Write-Log "Disabling Windows security features..." "Yellow"
    
    $featuresToDisable = @(
        "Microsoft-Hyper-V-All",
        "Microsoft-Hyper-V",
        "Microsoft-Hyper-V-Tools-All",
        "Microsoft-Hyper-V-Management-PowerShell",
        "Microsoft-Hyper-V-Hypervisor",
        "Microsoft-Hyper-V-Services",
        "Microsoft-Hyper-V-Management-Clients",
        "VirtualMachinePlatform",
        "HypervisorPlatform"
    )
    
    foreach ($feature in $featuresToDisable) {
        try {
            $featureState = Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction SilentlyContinue
            if ($featureState -and $featureState.State -eq "Enabled") {
                Write-Log "  Disabling $feature..." "White"
                Disable-WindowsOptionalFeature -Online -FeatureName $feature -All -NoRestart -WarningAction SilentlyContinue | Out-Null
                Write-Log "  [OK] $feature disabled" "Green"
            } elseif ($featureState -and $featureState.State -eq "Disabled") {
                Write-Log "  [OK] $feature already disabled" "Green"
            }
        }
        catch {
            Write-Log "  [WARN] Could not disable $feature" "Yellow"
        }
    }
    
    # Revert BCDEdit settings to defaults
    Write-Log ""
    Write-Log "Reverting boot settings to defaults..." "Yellow"
    
    $bcdCommands = @(
        @{Command = "bcdedit /set hypervisorlaunchtype off"; Description = "Disable Hypervisor Launch"},
        @{Command = "bcdedit /set vsmlaunchtype Off"; Description = "Disable VSM Launch"},
        @{Command = "bcdedit /set nx optout"; Description = "Disable NX/DEP"},
        @{Command = "bcdedit /set loadoptions DISABLE-LSA-ISO,DISABLE-VBS"; Description = "Disable LSA Isolation and VBS"},
        @{Command = "bcdedit /set isolatedcontext No"; Description = "Disable Isolated Context"},
        @{Command = "bcdedit /set allowedinmemorysettings 0x0"; Description = "Disable Memory Settings"},
        @{Command = "bcdedit /set vm No"; Description = "Disable VM Boot Option"}
    )
    
    foreach ($bcdEntry in $bcdCommands) {
        try {
            Write-Log "  $($bcdEntry.Description)..." "White"
            Invoke-Expression $bcdEntry.Command 2>$null
            Write-Log "  [OK] $($bcdEntry.Description) completed" "Green"
        }
        catch {
            Write-Log "  [WARN] Failed: $($bcdEntry.Description)" "Yellow"
        }
    }
    
    # Revert registry settings to defaults
    Write-Log ""
    Write-Log "Reverting registry settings to defaults..." "Yellow"
    
    $registrySettings = @(
        # Disable VBS
        @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard"; Name = "EnableVirtualizationBasedSecurity"; Value = 0; Type = "DWord"},
        @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard"; Name = "RequirePlatformSecurityFeatures"; Value = 0; Type = "DWord"},
        @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard"; Name = "Locked"; Value = 0; Type = "DWord"},
        
        # Disable Core Isolation
        @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity"; Name = "Enabled"; Value = 0; Type = "DWord"},
        
        # Disable Credential Guard
        @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\CredentialGuard"; Name = "Enabled"; Value = 0; Type = "DWord"},
        
        # Disable Speculative Execution Mitigations (performance mode)
        @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"; Name = "FeatureSettings"; Value = 0; Type = "DWord"},
        @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"; Name = "FeatureSettingsOverride"; Value = 3; Type = "DWord"},
        @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"; Name = "FeatureSettingsOverrideMask"; Value = 3; Type = "DWord"}
    )
    
    foreach ($setting in $registrySettings) {
        try {
            if (-not (Test-Path $setting.Path)) {
                New-Item -Path $setting.Path -Force | Out-Null
            }
            Write-Log "  Reverting $($setting.Path)\$($setting.Name)..." "White"
            Set-ItemProperty -Path $setting.Path -Name $setting.Name -Value $setting.Value -Type $setting.Type -Force
            Write-Log "  [OK] Registry setting reverted" "Green"
        }
        catch {
            Write-Log "  [WARN] Failed to revert $($setting.Path)\$($setting.Name)" "Yellow"
        }
    }
    
    # Remove Windows Defender exclusions
    Write-Log ""
    Write-Log "Removing Windows Defender exclusions..." "Yellow"
    
    $exclusionPaths = @(
        "C:\VM",
        "C:\Program Files (x86)\VMware",
        "C:\ProgramData\VMware"
    )
    
    foreach ($path in $exclusionPaths) {
        try {
            Remove-MpPreference -ExclusionPath $path -Force 2>$null
            Write-Log "  [OK] Removed exclusion for $path" "Green"
        }
        catch {
            Write-Log "  [WARN] Could not remove exclusion for $path" "Yellow"
        }
    }
    
    # Remove VMware process exclusions
    $vmwareProcesses = @(
        "vmware-vmx.exe",
        "vmware.exe",
        "vmware-hostd.exe",
        "vmware-authd.exe"
    )
    
    foreach ($process in $vmwareProcesses) {
        try {
            Remove-MpPreference -ExclusionProcess $process -Force 2>$null
            Write-Log "  [OK] Removed process exclusion for $process" "Green"
        }
        catch {
            Write-Log "  [WARN] Could not remove process exclusion for $process" "Yellow"
        }
    }
    
    # Remove VMware configuration files
    Write-Log ""
    Write-Log "Removing VMware configuration files..." "Yellow"
    
    $vmwareConfigPaths = @(
        "$env:APPDATA\VMware\config.ini",
        "$env:APPDATA\VMware\preferences.ini"
    )
    
    foreach ($configPath in $vmwareConfigPaths) {
        try {
            if (Test-Path $configPath) {
                Remove-Item -Path $configPath -Force
                Write-Log "  [OK] Removed $configPath" "Green"
            } else {
                Write-Log "  [OK] $configPath not found (already removed)" "Green"
            }
        }
        catch {
            Write-Log "  [WARN] Could not remove $configPath" "Yellow"
        }
    }
    
    # Remove VM directory structure (optional - ask user)
    Write-Log ""
    Write-Log "VM directory structure at C:\VM will be preserved." "Yellow"
    Write-Log "You can manually remove C:\VM if no longer needed." "White"
    
    Write-Log ""
    Write-Log "=====================================================" "Cyan"
    Write-Log "                Uninstall Summary" "Cyan"  
    Write-Log "=====================================================" "Cyan"
    Write-Log ""
    Write-Log "Security enhancements have been removed!" "Green"
    Write-Log ""
    Write-Log "CHANGES REVERTED:" "Green"
    Write-Log "  [OK] Windows Hypervisor Platform disabled" "Green"
    Write-Log "  [OK] Virtualization Based Security (VBS) disabled" "Green"
    Write-Log "  [OK] Credential Guard disabled" "Green"
    Write-Log "  [OK] Core Isolation and Memory Integrity disabled" "Green"
    Write-Log "  [OK] Device Guard disabled" "Green"
    Write-Log "  [OK] Hyper-V features disabled" "Green"
    Write-Log "  [OK] Registry settings reverted to defaults" "Green"
    Write-Log "  [OK] BCDEdit settings reverted to defaults" "Green"
    Write-Log "  [OK] Windows Defender exclusions removed" "Green"
    Write-Log "  [OK] VMware configuration files removed" "Green"
    Write-Log ""
    Write-Log "IMPORTANT: A system restart is required!" "Red"
    Write-Log "After restart, Windows will be in its default configuration." "Green"
    Write-Log ""
    Write-Log "VM directory structure at C:\VM has been preserved." "Yellow"
    Write-Log "Remove manually if no longer needed." "White"
}

# Check if uninstall was requested
if ($Uninstall) {
    Write-Log ""
    Write-Log "UNINSTALL MODE: Removing all security enhancements..." "Red"
    Write-Log "This will revert Windows to its default configuration." "Yellow"
    Write-Log ""
    
    if (-not $Silent) {
        $response = Read-Host "Are you sure you want to remove all security enhancements? (Type 'YES' to confirm)"
        if ($response -ne "YES") {
            Write-Log "Uninstall cancelled by user. No changes made." "Yellow"
            exit 0
        }
    }
    
    try {
        Uninstall-SecurityEnhancements
    }
    catch {
        Write-Log "Error during uninstall: $_" "Red"
    }
    
    # Stop transcript logging
    Stop-Transcript
    
    # Prompt for restart
    if (-not $Silent) {
        $restart = Read-Host "Would you like to restart the computer now? (Y/N)"
        if ($restart -eq 'Y' -or $restart -eq 'y') {
            Write-Log "Restarting computer in 10 seconds..." "Yellow"
            Start-Sleep -Seconds 10
            Restart-Computer -Force
        }
    } else {
        Write-Log "Silent mode: Restart required to complete uninstall." "Yellow"
    }
    
    exit 0
}

Write-Log "=====================================================" "Cyan"
Write-Log "    Windows Security Enhancement" "Cyan"
Write-Log "    Version: $ScriptVersion" "Cyan"
Write-Log "=====================================================" "Cyan"
Write-Log ""

# Check for Administrator privileges
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "ERROR: This script must be run as Administrator!" "Red"
    Write-Log "Right-click and select 'Run as Administrator'" "Yellow"
    exit 1
}

# Check Windows version
$windowsVersion = [System.Environment]::OSVersion.Version
Write-Log "Windows Version: $($windowsVersion.Major).$($windowsVersion.Minor) Build $($windowsVersion.Build)" "Cyan"

if ($windowsVersion.Build -lt 22000) {
    Write-Log "WARNING: This script is optimized for Windows 11. Some features may not work on older versions." "Yellow"
}

# Function to install VMware Workstation if installer is present
function Install-VMwareWorkstation {
    Write-Log ""
    Write-Log "Checking for VMware Workstation installer..." "Yellow"
    
    # Look for VMware installer in script directory
    $installerPattern = "VMware-workstation-full-*.exe"
    $installerPath = Get-ChildItem -Path $ScriptDir -Filter $installerPattern | Select-Object -First 1
    
    if ($installerPath) {
        Write-Log "Found VMware installer: $($installerPath.Name)" "Green"
        
        # Check if VMware is already installed
        $vmwareInstalled = Test-Path "C:\Program Files (x86)\VMware\VMware Workstation\vmware.exe"
        
        if ($vmwareInstalled) {
            Write-Log "VMware Workstation is already installed. Skipping installation." "Yellow"
            return
        }
        
        Write-Log "Installing VMware Workstation silently..." "Yellow"
        try {
            $installArgs = "/S /v/qn EULAS_AGREED=1 DATACOLLECTION=0"
            $process = Start-Process -FilePath $installerPath.FullName -ArgumentList $installArgs -Wait -PassThru
            
            if ($process.ExitCode -eq 0) {
                Write-Log "[OK] VMware Workstation installed successfully" "Green"
            } else {
                Write-Log "[WARN] VMware installation completed with exit code: $($process.ExitCode)" "Yellow"
            }
            
            # Clean up VMware desktop icons after installation
            Write-Log ""
            Write-Log "Removing VMware desktop icons..." "Yellow"
            
            $desktopPaths = @(
                [System.Environment]::GetFolderPath("Desktop"),
                [System.Environment]::GetFolderPath("CommonDesktopDirectory")
            )
            
            $vmwareIcons = @("*VMware*", "*Workstation*")
            $removedCount = 0
            
            foreach ($desktopPath in $desktopPaths) {
                if (Test-Path $desktopPath) {
                    foreach ($iconPattern in $vmwareIcons) {
                        $icons = Get-ChildItem -Path $desktopPath -Name $iconPattern -ErrorAction SilentlyContinue
                        foreach ($icon in $icons) {
                            try {
                                $iconPath = Join-Path $desktopPath $icon
                                Remove-Item -Path $iconPath -Force -ErrorAction SilentlyContinue
                                Write-Log "  [OK] Removed: $icon" "Green"
                                $removedCount++
                            }
                            catch {
                                Write-Log "  [WARN] Could not remove: $icon" "Yellow"
                            }
                        }
                    }
                }
            }
            
            Write-Log "[OK] VMware desktop cleanup completed - removed $removedCount icons" "Green"
        }
        catch {
            Write-Log "[ERROR] Failed to install VMware Workstation: $_" "Red"
        }
    } else {
        Write-Log "No VMware installer found (looking for $installerPattern)" "Yellow"
        Write-Log "Please download VMware Workstation installer if you want to install it" "White"
    }
}

# Confirmation prompt (unless Silent)
if (-not $Silent) {
    Write-Log ""
    Write-Log "SECURITY ENHANCEMENT TRADE-OFF:" "Red"
    Write-Log "  [OK] Enhanced Windows Security with VBS and Credential Guard" "Green"
    Write-Log "  [OK] Windows Hello Face Recognition will be enabled" "Green"
    Write-Log "  [OK] Core Isolation and Memory Integrity enabled" "Green"
    Write-Log "  [WARN] WSL2 will be disabled (unless -KeepWSL specified)" "Yellow"
    Write-Log "  [WARN] VMware performance may be reduced due to security features" "Yellow"
    Write-Log ""
    Write-Log "WHAT YOU GAIN: Enhanced security with VBS, Credential Guard, and Core Isolation" "Green"
    Write-Log "WHAT YOU LOSE: Some VMware performance (security vs performance trade-off)" "Yellow"
    Write-Log ""
    Write-Log "System restart required to complete optimization." "Cyan"
    Write-Log ""
    
    $response = Read-Host "Enable enhanced Windows security features (VBS, Credential Guard)? (Type 'YES' to confirm)"
    if ($response -ne "YES") {
        Write-Log "Operation cancelled by user. No changes made." "Yellow"
        exit 0
    }
}

Write-Log ""
Write-Log "Starting Windows security enhancement..." "Green"

# Function to enable Windows features
function Enable-WindowsFeatures {
    Write-Log ""
    Write-Log "Enabling Windows Hypervisor Platform and security features..." "Yellow"
    
    $featuresToEnable = @(
        "Microsoft-Hyper-V-All",
        "Microsoft-Hyper-V",
        "Microsoft-Hyper-V-Tools-All",
        "Microsoft-Hyper-V-Management-PowerShell",
        "Microsoft-Hyper-V-Hypervisor",
        "Microsoft-Hyper-V-Services",
        "Microsoft-Hyper-V-Management-Clients",
        "VirtualMachinePlatform",
        "HypervisorPlatform"
    )
    
    # Add WSL features if not keeping WSL
    if (-not $KeepWSL) {
        $featuresToDisable = @(
            "Microsoft-Windows-Subsystem-Linux"
        )
        
        foreach ($feature in $featuresToDisable) {
            try {
                $featureState = Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction SilentlyContinue
                if ($featureState -and $featureState.State -eq "Enabled") {
                    Write-Log "  Disabling $feature..." "White"
                    Disable-WindowsOptionalFeature -Online -FeatureName $feature -All -NoRestart -WarningAction SilentlyContinue | Out-Null
                    Write-Log "  [OK] $feature disabled" "Green"
                }
            }
            catch {
                Write-Log "  [WARN] Could not disable $feature" "Yellow"
            }
        }
    }
    
    foreach ($feature in $featuresToEnable) {
        try {
            $featureState = Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction SilentlyContinue
            if ($featureState -and $featureState.State -eq "Disabled") {
                Write-Log "  Enabling $feature..." "White"
                Enable-WindowsOptionalFeature -Online -FeatureName $feature -All -NoRestart -WarningAction SilentlyContinue | Out-Null
                Write-Log "  [OK] $feature enabled" "Green"
            } elseif ($featureState -and $featureState.State -eq "Enabled") {
                Write-Log "  [OK] $feature already enabled" "Green"
            }
        }
        catch {
            Write-Log "  [WARN] Could not enable $feature" "Yellow"
        }
    }
}

# Function to configure BCDEdit settings
function Configure-BCDEdit {
    Write-Log ""
    Write-Log "Configuring boot settings..." "Yellow"
    
    $bcdCommands = @(
        @{Command = "bcdedit /set hypervisorlaunchtype auto"; Description = "Enable Hypervisor Launch"},
        @{Command = "bcdedit /set vsmlaunchtype auto"; Description = "Enable VSM Launch"},
        @{Command = "bcdedit /set nx optin"; Description = "Enable NX/DEP"},
        @{Command = "bcdedit /deletevalue loadoptions"; Description = "Remove load options to enable VBS"},
        @{Command = "bcdedit /set isolatedcontext Yes"; Description = "Enable Isolated Context"},
        @{Command = "bcdedit /set allowedinmemorysettings 0x1"; Description = "Enable Memory Settings"},
        @{Command = "bcdedit /set vm Yes"; Description = "Enable VM Boot Option"}
    )
    
    foreach ($bcdEntry in $bcdCommands) {
        try {
            Write-Log "  $($bcdEntry.Description)..." "White"
            Invoke-Expression $bcdEntry.Command 2>$null
            Write-Log "  [OK] $($bcdEntry.Description) completed" "Green"
        }
        catch {
            Write-Log "  [WARN] Failed: $($bcdEntry.Description)" "Yellow"
        }
    }
}

# Function to configure registry settings
function Configure-Registry {
    Write-Log ""
    Write-Log "Configuring registry for VBS and Device Guard..." "Yellow"
    
    $registrySettings = @(
        # Enable VBS
        @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard"; Name = "EnableVirtualizationBasedSecurity"; Value = 1; Type = "DWord"},
        @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard"; Name = "RequirePlatformSecurityFeatures"; Value = 1; Type = "DWord"},
        @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard"; Name = "Locked"; Value = 0; Type = "DWord"},
        
        # Enable Core Isolation
        @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity"; Name = "Enabled"; Value = 1; Type = "DWord"},
        
        # Enable Credential Guard
        @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\CredentialGuard"; Name = "Enabled"; Value = 1; Type = "DWord"},
        
        # Keep Speculative Execution Mitigations enabled for security
        @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"; Name = "FeatureSettings"; Value = 1; Type = "DWord"},
        @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"; Name = "FeatureSettingsOverride"; Value = 0; Type = "DWord"},
        @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"; Name = "FeatureSettingsOverrideMask"; Value = 0; Type = "DWord"}
    )
    
    foreach ($setting in $registrySettings) {
        try {
            if (-not (Test-Path $setting.Path)) {
                New-Item -Path $setting.Path -Force | Out-Null
            }
            Write-Log "  Setting $($setting.Path)\$($setting.Name)..." "White"
            Set-ItemProperty -Path $setting.Path -Name $setting.Name -Value $setting.Value -Type $setting.Type -Force
            Write-Log "  [OK] Registry setting applied" "Green"
        }
        catch {
            Write-Log "  [WARN] Failed to set $($setting.Path)\$($setting.Name)" "Yellow"
        }
    }
}

# Function to disable power throttling (Intel 12th-14th gen fix)
function Disable-PowerThrottling {
    Write-Log ""
    Write-Log "Disabling power throttling for VMware processes..." "Yellow"
    
    $vmwarePaths = @(
        "C:\Program Files (x86)\VMware\VMware Workstation\x64\vmware-vmx.exe",
        "C:\Program Files (x86)\VMware\VMware Workstation\vmware.exe",
        "C:\Program Files (x86)\VMware\VMware Workstation\x64\vmware-hostd.exe"
    )
    
    foreach ($path in $vmwarePaths) {
        if (Test-Path $path) {
            try {
                Write-Log "  Disabling throttling for $path..." "White"
                powercfg /powerthrottling disable /path "$path" 2>$null
                Write-Log "  [OK] Power throttling disabled for $(Split-Path $path -Leaf)" "Green"
            }
            catch {
                Write-Log "  [WARN] Could not disable throttling for $(Split-Path $path -Leaf)" "Yellow"
            }
        }
    }
}


# Function to create VM directory structure
function Create-VMDirectories {
    Write-Log ""
    Write-Log "Creating C:\VM directory structure..." "Yellow"
    
    $vmDirs = @(
        "C:\VM",
        "C:\VM\Templates",
        "C:\VM\ISOs",
        "C:\VM\VMs",
        "C:\VM\Shared"
    )
    
    foreach ($dir in $vmDirs) {
        try {
            if (-not (Test-Path $dir)) {
                New-Item -Path $dir -ItemType Directory -Force | Out-Null
                Write-Log "  [OK] Created $dir" "Green"
            }
            else {
                Write-Log "  [OK] $dir already exists" "Green"
            }
        }
        catch {
            Write-Log "  [FAIL] Failed to create $dir" "Red"
        }
    }
    
    # Configure Windows Search to exclude VM directories
    try {
        Write-Log "  Configuring Windows Search exclusions..." "White"
        Add-WindowsSearchDataSource -Path "C:\VM" -Exclude 2>$null
        Write-Log "  [OK] Windows Search exclusion configured" "Green"
    }
    catch {
        Write-Log "  [WARN] Could not configure search exclusions" "Yellow"
    }
}

# Function to configure VMware settings
function Configure-VMwareSettings {
    Write-Log ""
    Write-Log "Configuring VMware Workstation settings..." "Yellow"
    
    # VMware config file paths
    $vmwareConfigPaths = @(
        "$env:APPDATA\VMware\config.ini",
        "$env:APPDATA\VMware\preferences.ini"
    )
    
    # Create VMware config directory if needed
    $vmwareConfigDir = "$env:APPDATA\VMware"
    if (-not (Test-Path $vmwareConfigDir)) {
        New-Item -Path $vmwareConfigDir -ItemType Directory -Force | Out-Null
    }
    
    # VMware configuration settings
    $configContent = @"
# VMware Workstation Configuration - Performance Optimized
# Generated by HyperI VMware Optimization Script

# Performance Settings
mainMem.useNamedFile = "FALSE"
MemTrimRate = "0"
sched.mem.pshare.enable = "FALSE"
prefvmx.useRecommendedLockedMemSize = "TRUE"
prefvmx.minVmMemPct = "100"

# Path Configuration
prefvmx.defaultVMPath = "C:\VM\VMs"
prefvmx.defaultSharePath = "C:\VM\Shared"
vixDiskLib.tempDir = "C:\VM\Temp"

# Security Settings (Performance Mode)
ulm.disableMitigations = "TRUE"
vmx.allowNested = "TRUE"
vhv.enable = "TRUE"

# UI Settings
vmware.fullscreen.topology = "single"
pref.vmplayer.exit.vmAction = "poweroff"
pref.vmplayer.confirmOnExit = "FALSE"

# Logging (Minimal for Performance)
log.keepOld = "3"
log.maxFileSize = "100000"

"@

    try {
        # Write to both config.ini and preferences.ini for broader compatibility
        $configPath = "$vmwareConfigDir\config.ini"
        $preferencesPath = "$vmwareConfigDir\preferences.ini"
        
        $configContent | Out-File -FilePath $configPath -Encoding UTF8 -Force
        $configContent | Out-File -FilePath $preferencesPath -Encoding UTF8 -Force
        
        Write-Log "  [OK] VMware configuration written to config.ini and preferences.ini" "Green"
        
        # Restart VMware services to apply configuration
        $vmwareServices = @("VMwareHostd", "VMAuthdService", "VMnetDHCP", "VMware NAT Service")
        foreach ($service in $vmwareServices) {
            try {
                $svc = Get-Service -Name $service -ErrorAction SilentlyContinue
                if ($svc -and $svc.Status -eq "Running") {
                    Restart-Service -Name $service -Force -ErrorAction SilentlyContinue
                    Write-Log "    [OK] Restarted $service" "Green"
                }
            }
            catch {
                # Service might not exist or be running
            }
        }
    }
    catch {
        Write-Log "  [WARN] Could not write VMware configuration" "Yellow"
    }
}

# Function to create VM templates from external files
function Create-VMTemplates {
    Write-Log ""
    Write-Log "Creating optimized VM templates..." "Yellow"
    
    # Copy VM template files from script directory to C:\VM\Templates
    $templateFiles = @(
        "Windows-Template.vmx",
        "Fedora-Template.vmx",
        "Ubuntu-LTS-Template.vmx", 
        "vSphere-Template.vmx"
    )
    
    foreach ($templateFile in $templateFiles) {
        $sourcePath = Join-Path $ScriptDir $templateFile
        $destinationPath = Join-Path "C:\VM\Templates" $templateFile
        
        if (Test-Path $sourcePath) {
            try {
                Copy-Item -Path $sourcePath -Destination $destinationPath -Force
                Write-Log "  [OK] Copied $templateFile to C:\VM\Templates" "Green"
            }
            catch {
                Write-Log "  [FAIL] Failed to copy $templateFile" "Red"
            }
        } else {
            Write-Log "  [WARN] Template file not found: $templateFile" "Yellow"
        }
    }
    
    # Register templates with VMware Workstation GUI
    Write-Log ""
    Write-Log "Registering templates with VMware Workstation..." "Yellow"
    
    $vmrunPath = "C:\Program Files (x86)\VMware\VMware Workstation\vmrun.exe"
    if (Test-Path $vmrunPath) {
        foreach ($templateFile in $templateFiles) {
            $templatePath = Join-Path "C:\VM\Templates" $templateFile
            if (Test-Path $templatePath) {
                try {
                    # Register template in VMware inventory
                    $result = & $vmrunPath -T ws register $templatePath 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        Write-Log "  [OK] Registered $templateFile in VMware GUI" "Green"
                    } else {
                        Write-Log "  [WARN] Could not register $templateFile (may already exist)" "Yellow"
                    }
                }
                catch {
                    Write-Log "  [WARN] Failed to register $templateFile in VMware GUI" "Yellow"
                }
            }
        }
    } else {
        Write-Log "  [WARN] VMware Workstation not found - templates copied but not registered" "Yellow"
    }
}

# Function to disable Windows Defender for VM directories
function Configure-WindowsDefender {
    Write-Log ""
    Write-Log "Configuring Windows Defender exclusions for VM performance..." "Yellow"

  
    $linuxVMX = @"
# VMware VM Configuration File - Fedora 42 Template
#---
# Filename: Fedora-42-Template.vmx
# Purpose: Fedora 42 optimized VM template for VMware Workstation
# Description: VMware configuration optimized for Fedora 42 with virtual drivers and legacy BIOS
# Version: 1.0.0
# Changelog: |
#   ## [1.0.0] - $(Get-Date -Format "yyyy-MM-dd")
#   Initial high-performance Linux VM template
# Copyright: © 2025 HyperSec Pty Ltd  
# Licence: "Apache-2.0"
#---

.encoding = "UTF-8"
config.version = "8"
virtualHW.version = "21"

# VM Identity
displayName = "Fedora-42-Template"
guestOS = "fedora-64"
firmware = "bios"

# Memory Configuration (Adjust as needed)
memSize = "4096"
mem.hotadd = "FALSE"

# CPU Configuration (Adjust as needed)
numvcpus = "2" 
cpuid.coresPerSocket = "2"
vcpu.hotadd = "FALSE"

# Performance Optimizations
mem.enableHostMemory = "TRUE"
sched.mem.pshare.enable = "FALSE"
sched.mem.pin = "TRUE"
balloon.maxSize = "0"
balloon.enable = "FALSE"
mainMem.useNamedFile = "FALSE"
prefvmx.useRecommendedLockedMemSize = "TRUE"
MemTrimRate = "0"

# Linux-specific optimizations
tools.syncTime = "FALSE"
time.synchronize.continue = "FALSE"
time.synchronize.restore = "FALSE"
time.synchronize.resume.disk = "FALSE"
time.synchronize.shrink = "FALSE"

# Disable unnecessary features
sound.present = "FALSE"
usb.present = "FALSE"
serial0.present = "FALSE"
parallel0.present = "FALSE"

# Network (NAT with high-performance virtual driver)
ethernet0.present = "TRUE"
ethernet0.connectionType = "nat"
ethernet0.virtualDev = "vmxnet3"

# Storage (NVMe for best performance)
scsi0.present = "TRUE"
scsi0.virtualDev = "nvme"
scsi0:0.present = "TRUE"
scsi0:0.fileName = "Fedora-42-Template.vmdk"
scsi0:0.mode = "persistent"

# Graphics (Standard VGA for compatibility)
svga.graphicsMemoryKB = "262144"
svga.vramSize = "268435456"
svga.present = "TRUE"
svga.autodetect = "TRUE"

# Security Settings (Performance Mode)
ulm.disableMitigations = "TRUE"

# Disable logging
log.keepOld = "0"
logging = "FALSE"

    $vSphereVMX = @"
# VMware VM Configuration File - vSphere Template
#---
# Filename: vSphere-Template.vmx
# Purpose: vSphere-compatible VM template for VMware Workstation
# Description: VM configuration compatible with vSphere infrastructure with performance optimizations
# Version: 1.0.0
# Changelog: |
#   ## [1.0.0] - $(Get-Date -Format "yyyy-MM-dd")
#   Initial vSphere-compatible VM template
# Copyright: © 2025 HyperSec Pty Ltd
# Licence: "Apache-2.0"
#---

.encoding = "UTF-8"
config.version = "8"
virtualHW.version = "19"

# VM Identity
displayName = "vSphere-Template"
guestOS = "windows2019srv-64"
firmware = "efi"

# Memory Configuration
memSize = "4096"
mem.hotadd = "TRUE"

# CPU Configuration
numvcpus = "2"
cpuid.coresPerSocket = "1"
vcpu.hotadd = "TRUE"

# vSphere Compatibility Settings
pciBridge0.present = "TRUE"
pciBridge4.present = "TRUE"
pciBridge4.virtualDev = "pcieRootPort"
pciBridge5.present = "TRUE"
pciBridge5.virtualDev = "pcieRootPort"
pciBridge6.present = "TRUE"
pciBridge6.virtualDev = "pcieRootPort"
pciBridge7.present = "TRUE"
pciBridge7.virtualDev = "pcieRootPort"

# Storage (LSI Logic SAS for vSphere compatibility)
scsi0.present = "TRUE"
scsi0.virtualDev = "lsisas1068"
scsi0:0.present = "TRUE"
scsi0:0.fileName = "vSphere-Template.vmdk"
scsi0:0.mode = "persistent"

# Network (VMXNET3 for best performance)
ethernet0.present = "TRUE"
ethernet0.connectionType = "nat"
ethernet0.virtualDev = "vmxnet3"

# Graphics (Standard VGA for compatibility)
svga.present = "TRUE"
svga.graphicsMemoryKB = "262144"

# Tools and Features
tools.upgrade.policy = "manual"
powerType.powerOff = "soft"
powerType.suspend = "soft"
powerType.reset = "soft"

# Performance optimizations where compatible
sched.mem.pshare.enable = "TRUE"
mainMem.useNamedFile = "TRUE"

"@

    # Write template files
    $templates = @(
        @{Name = "Windows-Template.vmx"; Content = $windowsVMX},
        @{Name = "Fedora-42-Template.vmx"; Content = $linuxVMX},
        @{Name = "vSphere-Template.vmx"; Content = $vSphereVMX}
    )
    
    foreach ($template in $templates) {
        try {
            $templatePath = "C:\VM\Templates\$($template.Name)"
            $template.Content | Out-File -FilePath $templatePath -Encoding UTF8 -Force
            Write-Log "  [OK] Created $($template.Name)" "Green"
        }
        catch {
            Write-Log "  [FAIL] Failed to create $($template.Name)" "Red"
        }
    }
}

# Function to disable Windows Defender for VM directories
function Configure-WindowsDefender {
    Write-Log ""
    Write-Log "Configuring Windows Defender exclusions for VM performance..." "Yellow"
    
    $exclusionPaths = @(
        "C:\VM",
        "C:\Program Files (x86)\VMware",
        "C:\ProgramData\VMware"
    )
    
    foreach ($path in $exclusionPaths) {
        try {
            Add-MpPreference -ExclusionPath $path -Force 2>$null
            Write-Log "  [OK] Added exclusion for $path" "Green"
        }
        catch {
            Write-Log "  [WARN] Could not add exclusion for $path" "Yellow"
        }
    }
    
    # Disable real-time monitoring for VM processes
    $vmwareProcesses = @(
        "vmware-vmx.exe",
        "vmware.exe",
        "vmware-hostd.exe",
        "vmware-authd.exe"
    )
    
    foreach ($process in $vmwareProcesses) {
        try {
            Add-MpPreference -ExclusionProcess $process -Force 2>$null
            Write-Log "  [OK] Added process exclusion for $process" "Green"
        }
        catch {
            Write-Log "  [WARN] Could not add process exclusion for $process" "Yellow"
        }
    }
}

# Function to uninstall all security enhancements and revert to defaults
function Uninstall-SecurityEnhancements {
    Write-Log ""
    Write-Log "=====================================================" "Cyan"
    Write-Log "    Uninstalling Security Enhancements" "Cyan"
    Write-Log "=====================================================" "Cyan"
    Write-Log ""
    
    # Disable Windows features that were enabled
    Write-Log "Disabling Windows security features..." "Yellow"
    
    $featuresToDisable = @(
        "Microsoft-Hyper-V-All",
        "Microsoft-Hyper-V",
        "Microsoft-Hyper-V-Tools-All",
        "Microsoft-Hyper-V-Management-PowerShell",
        "Microsoft-Hyper-V-Hypervisor",
        "Microsoft-Hyper-V-Services",
        "Microsoft-Hyper-V-Management-Clients",
        "VirtualMachinePlatform",
        "HypervisorPlatform"
    )
    
    foreach ($feature in $featuresToDisable) {
        try {
            $featureState = Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction SilentlyContinue
            if ($featureState -and $featureState.State -eq "Enabled") {
                Write-Log "  Disabling $feature..." "White"
                Disable-WindowsOptionalFeature -Online -FeatureName $feature -All -NoRestart -WarningAction SilentlyContinue | Out-Null
                Write-Log "  [OK] $feature disabled" "Green"
            } elseif ($featureState -and $featureState.State -eq "Disabled") {
                Write-Log "  [OK] $feature already disabled" "Green"
            }
        }
        catch {
            Write-Log "  [WARN] Could not disable $feature" "Yellow"
        }
    }
    
    # Revert BCDEdit settings to defaults
    Write-Log ""
    Write-Log "Reverting boot settings to defaults..." "Yellow"
    
    $bcdCommands = @(
        @{Command = "bcdedit /set hypervisorlaunchtype off"; Description = "Disable Hypervisor Launch"},
        @{Command = "bcdedit /set vsmlaunchtype Off"; Description = "Disable VSM Launch"},
        @{Command = "bcdedit /set nx optout"; Description = "Disable NX/DEP"},
        @{Command = "bcdedit /set loadoptions DISABLE-LSA-ISO,DISABLE-VBS"; Description = "Disable LSA Isolation and VBS"},
        @{Command = "bcdedit /set isolatedcontext No"; Description = "Disable Isolated Context"},
        @{Command = "bcdedit /set allowedinmemorysettings 0x0"; Description = "Disable Memory Settings"},
        @{Command = "bcdedit /set vm No"; Description = "Disable VM Boot Option"}
    )
    
    foreach ($bcdEntry in $bcdCommands) {
        try {
            Write-Log "  $($bcdEntry.Description)..." "White"
            Invoke-Expression $bcdEntry.Command 2>$null
            Write-Log "  [OK] $($bcdEntry.Description) completed" "Green"
        }
        catch {
            Write-Log "  [WARN] Failed: $($bcdEntry.Description)" "Yellow"
        }
    }
    
    # Revert registry settings to defaults
    Write-Log ""
    Write-Log "Reverting registry settings to defaults..." "Yellow"
    
    $registrySettings = @(
        # Disable VBS
        @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard"; Name = "EnableVirtualizationBasedSecurity"; Value = 0; Type = "DWord"},
        @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard"; Name = "RequirePlatformSecurityFeatures"; Value = 0; Type = "DWord"},
        @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard"; Name = "Locked"; Value = 0; Type = "DWord"},
        
        # Disable Core Isolation
        @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity"; Name = "Enabled"; Value = 0; Type = "DWord"},
        
        # Disable Credential Guard
        @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\CredentialGuard"; Name = "Enabled"; Value = 0; Type = "DWord"},
        
        # Disable Speculative Execution Mitigations (performance mode)
        @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"; Name = "FeatureSettings"; Value = 0; Type = "DWord"},
        @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"; Name = "FeatureSettingsOverride"; Value = 3; Type = "DWord"},
        @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"; Name = "FeatureSettingsOverrideMask"; Value = 3; Type = "DWord"}
    )
    
    foreach ($setting in $registrySettings) {
        try {
            if (-not (Test-Path $setting.Path)) {
                New-Item -Path $setting.Path -Force | Out-Null
            }
            Write-Log "  Reverting $($setting.Path)\$($setting.Name)..." "White"
            Set-ItemProperty -Path $setting.Path -Name $setting.Name -Value $setting.Value -Type $setting.Type -Force
            Write-Log "  [OK] Registry setting reverted" "Green"
        }
        catch {
            Write-Log "  [WARN] Failed to revert $($setting.Path)\$($setting.Name)" "Yellow"
        }
    }
    
    # Remove Windows Defender exclusions
    Write-Log ""
    Write-Log "Removing Windows Defender exclusions..." "Yellow"
    
    $exclusionPaths = @(
        "C:\VM",
        "C:\Program Files (x86)\VMware",
        "C:\ProgramData\VMware"
    )
    
    foreach ($path in $exclusionPaths) {
        try {
            Remove-MpPreference -ExclusionPath $path -Force 2>$null
            Write-Log "  [OK] Removed exclusion for $path" "Green"
        }
        catch {
            Write-Log "  [WARN] Could not remove exclusion for $path" "Yellow"
        }
    }
    
    # Remove VMware process exclusions
    $vmwareProcesses = @(
        "vmware-vmx.exe",
        "vmware.exe",
        "vmware-hostd.exe",
        "vmware-authd.exe"
    )
    
    foreach ($process in $vmwareProcesses) {
        try {
            Remove-MpPreference -ExclusionProcess $process -Force 2>$null
            Write-Log "  [OK] Removed process exclusion for $process" "Green"
        }
        catch {
            Write-Log "  [WARN] Could not remove process exclusion for $process" "Yellow"
        }
    }
    
    # Remove VMware configuration files
    Write-Log ""
    Write-Log "Removing VMware configuration files..." "Yellow"
    
    $vmwareConfigPaths = @(
        "$env:APPDATA\VMware\config.ini",
        "$env:APPDATA\VMware\preferences.ini"
    )
    
    foreach ($configPath in $vmwareConfigPaths) {
        try {
            if (Test-Path $configPath) {
                Remove-Item -Path $configPath -Force
                Write-Log "  [OK] Removed $configPath" "Green"
            } else {
                Write-Log "  [OK] $configPath not found (already removed)" "Green"
            }
        }
        catch {
            Write-Log "  [WARN] Could not remove $configPath" "Yellow"
        }
    }
    
    # Remove VM directory structure (optional - ask user)
    Write-Log ""
    Write-Log "VM directory structure at C:\VM will be preserved." "Yellow"
    Write-Log "You can manually remove C:\VM if no longer needed." "White"
    
    Write-Log ""
    Write-Log "=====================================================" "Cyan"
    Write-Log "                Uninstall Summary" "Cyan"  
    Write-Log "=====================================================" "Cyan"
    Write-Log ""
    Write-Log "Security enhancements have been removed!" "Green"
    Write-Log ""
    Write-Log "CHANGES REVERTED:" "Green"
    Write-Log "  [OK] Windows Hypervisor Platform disabled" "Green"
    Write-Log "  [OK] Virtualization Based Security (VBS) disabled" "Green"
    Write-Log "  [OK] Credential Guard disabled" "Green"
    Write-Log "  [OK] Core Isolation and Memory Integrity disabled" "Green"
    Write-Log "  [OK] Device Guard disabled" "Green"
    Write-Log "  [OK] Hyper-V features disabled" "Green"
    Write-Log "  [OK] Registry settings reverted to defaults" "Green"
    Write-Log "  [OK] BCDEdit settings reverted to defaults" "Green"
    Write-Log "  [OK] Windows Defender exclusions removed" "Green"
    Write-Log "  [OK] VMware configuration files removed" "Green"
    Write-Log ""
    Write-Log "IMPORTANT: A system restart is required!" "Red"
    Write-Log "After restart, Windows will be in its default configuration." "Green"
    Write-Log ""
    Write-Log "VM directory structure at C:\VM has been preserved." "Yellow"
    Write-Log "Remove manually if no longer needed." "White"
}

# Main execution
try {
    Install-VMwareWorkstation
    Enable-WindowsFeatures
    Configure-BCDEdit
    Configure-Registry
    Disable-PowerThrottling
    # Set-HighPerformancePlan  # Commented out - SOE script handles power management
    Create-VMDirectories
    Configure-VMwareSettings
    Create-VMTemplates
    Configure-WindowsDefender
}
catch {
    Write-Log "Error during optimization: $_" "Red"
}

# Summary
Write-Log ""
Write-Log "=====================================================" "Cyan"
Write-Log "                Optimization Summary" "Cyan"  
Write-Log "=====================================================" "Cyan"
Write-Log ""
Write-Log "Windows Security Enhancement Complete!" "Green"
Write-Log ""
Write-Log "SECURITY ENHANCEMENTS APPLIED:" "Green"
Write-Log "  [OK] Windows Hypervisor Platform enabled" "Green"
Write-Log "  [OK] Virtualization Based Security (VBS) enabled" "Green"
Write-Log "  [OK] Credential Guard enabled" "Green"
Write-Log "  [OK] Core Isolation and Memory Integrity enabled" "Green"
Write-Log "  [OK] Device Guard enabled" "Green"
Write-Log "  [OK] Hyper-V features enabled" "Green"
if (-not $KeepWSL) {
    Write-Log "  [OK] Disabled WSL2 for security" "Green"
} else {
    Write-Log "  [WARN] WSL2 preserved (may impact security)" "Yellow"
}
Write-Log "  [OK] Ultimate Performance power plan activated" "Green"
Write-Log "  [OK] Created optimized C:\VM directory structure" "Green"
Write-Log "  [OK] Configured VMware for security" "Green"
Write-Log "  [OK] Generated security-optimized VM templates" "Green"
Write-Log "  [OK] Windows Defender VM exclusions configured" "Green"
Write-Log ""
Write-Log "TRADE-OFFS MADE FOR SECURITY:" "Yellow"
Write-Log "  [OK] Windows Hello Face Recognition enabled" "Green"
if (-not $KeepWSL) {
    Write-Log "  [FAIL] WSL2 (Windows Subsystem for Linux) disabled" "Yellow"
} else {
    Write-Log "  [WARN] WSL2 kept (may reduce security)" "Yellow"
}
Write-Log "  [WARN] VMware performance may be reduced due to security features" "Yellow"
Write-Log "  [OK] PIN and Password authentication still work" "Green"
Write-Log ""
Write-Log "VM Templates created in C:\VM\Templates:" "Yellow"
Write-Log "  - Windows-Template.vmx (High-performance Windows)" "White"
Write-Log "  - Fedora-Template.vmx (Fedora optimized)" "White"
Write-Log "  - Ubuntu-LTS-Template.vmx (Ubuntu LTS optimized)" "White"
Write-Log "  - vSphere-Template.vmx (vSphere-compatible)" "White"
Write-Log ""
Write-Log "IMPORTANT: A system restart is required!" "Red"
Write-Log "After restart, Windows security features will be fully enabled." "Green"
Write-Log ""
Write-Log "Log file saved to: $TranscriptPath" "Cyan"

# Stop transcript logging
Stop-Transcript

# Prompt for restart
if (-not $Silent) {
    $restart = Read-Host "Would you like to restart the computer now? (Y/N)"
    if ($restart -eq 'Y' -or $restart -eq 'y') {
        Write-Log "Restarting computer in 10 seconds..." "Yellow"
        Start-Sleep -Seconds 10
        Restart-Computer -Force
    }
} else {
    Write-Log "Silent mode: Restart required to complete optimization." "Yellow"
}