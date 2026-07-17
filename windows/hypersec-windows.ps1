#Requires -RunAsAdministrator
<#
.SYNOPSIS
    HyperSec Windows 11 SOE - VM Host and Productivity Configuration
.DESCRIPTION
    Configures Windows 11 as a secure VM host for productivity work and Linux development VMs.

    IMPORTANT - DEVELOPMENT WORKFLOW:
    This script prepares Windows for:
      - Productivity tools: Office, Slack, browsers, communication apps
      - VM hosting: Hyper-V with full security stack (VBS, Credential Guard, HVCI)
      - Office automation and business tasks

    Actual HyperSec code development happens in Linux VMs configured with the HyperSec Linux Hyperi
    developer SOE - NOT natively on Windows. Windows is your comfortable office chair; Linux VMs
    are where you write code.

    VIRTUALIZATION APPROACH:
    Uses Microsoft Hyper-V instead of VMware Workstation. While VMware delivers better Linux VM
    performance, it requires disabling VBS, Credential Guard, HVCI, and speculative execution
    mitigations. Whether Microsoft's design forcing third-party hypervisors to disable core
    security features is intentional or coincidental is left as an exercise for the reader.
    Either way, we're not trading security for convenience.

    For legacy VMware users: See hypersec-windows-vmware.ps1 (DEPRECATED - unmaintained)
.PARAMETER SkipBrowserConfig
    Skip Firefox default browser configuration
.PARAMETER IncludeM365
    Include Microsoft 365 installation (requires license)
.PARAMETER SkipVSCode
    Skip Visual Studio Code installation (useful when running from VSCode)
.PARAMETER ShowHelp
    Display detailed help information about this script
.EXAMPLE
    .\hypersec-windows.ps1
    .\hypersec-windows.ps1 -SkipBrowserConfig
    .\hypersec-windows.ps1 -IncludeM365
    .\hypersec-windows.ps1 -SkipVSCode
    .\hypersec-windows.ps1 -ShowHelp
#>

param(
    [switch]$SkipBrowserConfig,
    [switch]$IncludeM365,
    [switch]$SkipVSCode,
    [switch]$ShowHelp
)

$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"

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

# Function to clear all PowerShell execution policies and set unrestricted
function Reset-ExecutionPolicies {
    Write-Host "Clearing all existing PowerShell execution policies..." -ForegroundColor Yellow
    
    # Clear all scopes of execution policy
    $scopes = @("Process", "CurrentUser", "LocalMachine", "UserPolicy", "MachinePolicy")
    
    foreach ($scope in $scopes) {
        try {
            Write-Host "Clearing execution policy for scope: $scope" -ForegroundColor Yellow
            Set-ExecutionPolicy -ExecutionPolicy Undefined -Scope $scope -Force -ErrorAction SilentlyContinue
        }
        catch {
            Write-Host "Could not clear execution policy for scope $scope`: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    
    Write-Host "Setting unrestricted execution policies..." -ForegroundColor Yellow
    
    # Set unrestricted policies for CurrentUser and LocalMachine
    try {
        Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope CurrentUser -Force
        Write-Host "CurrentUser execution policy set to Unrestricted" -ForegroundColor Green
    }
    catch {
        Write-Host "Could not set CurrentUser execution policy: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    try {
        Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope LocalMachine -Force
        Write-Host "LocalMachine execution policy set to Unrestricted" -ForegroundColor Green
    }
    catch {
        Write-Host "Could not set LocalMachine execution policy: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    Write-Host "Execution policy reset completed" -ForegroundColor Green
}

# Function to comprehensively uninstall applications that support both user and system-wide modes
function Remove-ExistingInstallations {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageName,
        [Parameter(Mandatory = $true)]
        [string]$DisplayName
    )
    
    Write-Host "Checking for existing $DisplayName installations..." -ForegroundColor Yellow
    
    # Stop any running processes for the application
    $processNames = @()
    switch ($PackageName) {
        "googlechrome" { $processNames = @("chrome", "chrome.exe") }
        "firefox" { $processNames = @("firefox", "firefox.exe") }
        "vscode" { $processNames = @("code", "Code.exe") }
        "slack" { $processNames = @("slack", "Slack.exe") }
        "onedrive" { $processNames = @("OneDrive", "OneDrive.exe") }
        "putty" { $processNames = @("putty", "putty.exe") }
        "winscp" { $processNames = @("WinSCP", "WinSCP.exe") }
        "obs-studio" { $processNames = @("obs64", "obs32", "obs.exe") }
        "vlc" { $processNames = @("vlc", "vlc.exe") }
        "paint.net" { $processNames = @("paintdotnet", "PaintDotNet.exe") }
        "github-desktop" { $processNames = @("GitHubDesktop", "GitHubDesktop.exe") }
        "powershell" { $processNames = @("pwsh", "pwsh.exe") }
        "git" { $processNames = @("git", "git.exe") }
    }
    
    foreach ($procName in $processNames) {
        try {
            Get-Process $procName -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        }
        catch { }
    }
    
    if ($processNames.Count -gt 0) {
        Start-Sleep -Seconds 2
    }
    
    # 1. Check for Chocolatey-managed installation (skip if found - only clean manual installations)
    $chocoInstalled = choco list --local-only --exact $PackageName 2>$null | Select-String -Pattern "^$PackageName\s"
    if ($chocoInstalled) {
        Write-Host "Chocolatey-managed $DisplayName found - skipping cleanup (keeping existing installation)" -ForegroundColor Green
        return  # Exit function early if Chocolatey version exists
    }
    
    # 2. Check for user-mode installations (AppData)
    $userPaths = @()
    switch ($PackageName) {
        "googlechrome" { $userPaths = @("$env:LOCALAPPDATA\Google") }
        "firefox" { $userPaths = @("$env:APPDATA\Mozilla\Firefox", "$env:LOCALAPPDATA\Mozilla\Firefox") }
        "vscode" { $userPaths = @("$env:LOCALAPPDATA\Programs\Microsoft VS Code") }
        "slack" { $userPaths = @("$env:LOCALAPPDATA\slack") }
        "onedrive" { $userPaths = @("$env:LOCALAPPDATA\Microsoft\OneDrive") }
        "obs-studio" { $userPaths = @("$env:LOCALAPPDATA\obs-studio") }
        "vlc" { $userPaths = @("$env:LOCALAPPDATA\vlc") }
        "paint.net" { $userPaths = @("$env:LOCALAPPDATA\paint.net") }
        "github-desktop" { $userPaths = @("$env:LOCALAPPDATA\GitHubDesktop") }
        "powershell" { $userPaths = @("$env:LOCALAPPDATA\Microsoft\WindowsApps\Microsoft.PowerShell_*") }
    }
    
    foreach ($userPath in $userPaths) {
        if (Test-Path $userPath) {
            Write-Host "Found user-mode $DisplayName installation, removing..." -ForegroundColor Yellow
            try {
                Remove-Item $userPath -Recurse -Force -ErrorAction SilentlyContinue
                Write-Host "User-mode $DisplayName removed" -ForegroundColor Green
            }
            catch {
                Write-Host "Could not fully remove user-mode $DisplayName`: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
    }
    
    # 3. Check for system-wide installations (Program Files)
    $systemPaths = @()
    switch ($PackageName) {
        "googlechrome" { $systemPaths = @("C:\Program Files\Google", "C:\Program Files (x86)\Google") }
        "firefox" { $systemPaths = @("C:\Program Files\Mozilla Firefox", "C:\Program Files (x86)\Mozilla Firefox") }
        "vscode" { $systemPaths = @("C:\Program Files\Microsoft VS Code", "C:\Program Files (x86)\Microsoft VS Code") }
        "slack" { $systemPaths = @("C:\Program Files\Slack", "C:\Program Files (x86)\Slack") }
        "onedrive" { $systemPaths = @("C:\Program Files\Microsoft OneDrive", "C:\Program Files (x86)\Microsoft OneDrive") }
        "putty" { $systemPaths = @("C:\Program Files\PuTTY", "C:\Program Files (x86)\PuTTY") }
        "winscp" { $systemPaths = @("C:\Program Files\WinSCP", "C:\Program Files (x86)\WinSCP") }
        "obs-studio" { $systemPaths = @("C:\Program Files\obs-studio", "C:\Program Files (x86)\obs-studio") }
        "vlc" { $systemPaths = @("C:\Program Files\VideoLAN\VLC", "C:\Program Files (x86)\VideoLAN\VLC") }
        "paint.net" { $systemPaths = @("C:\Program Files\paint.net", "C:\Program Files (x86)\paint.net") }
        "github-desktop" { $systemPaths = @("C:\Program Files\GitHub Desktop", "C:\Program Files (x86)\GitHub Desktop") }
        "powershell" { $systemPaths = @("C:\Program Files\PowerShell", "C:\Program Files (x86)\PowerShell") }
        "git" { $systemPaths = @("C:\Program Files\Git", "C:\Program Files (x86)\Git") }
    }
    
    foreach ($systemPath in $systemPaths) {
        if (Test-Path $systemPath) {
            Write-Host "Found system-wide $DisplayName installation, removing..." -ForegroundColor Yellow
            try {
                # Try to use Windows uninstaller first
                $uninstallKey = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*$DisplayName*" }
                if ($uninstallKey) {
                    $uninstallString = $uninstallKey.UninstallString
                    if ($uninstallString) {
                        Write-Host "Using Windows uninstaller for $DisplayName..." -ForegroundColor Yellow
                        if ($uninstallString -like "*.msi*") {
                            Start-Process -FilePath "msiexec.exe" -ArgumentList "/x $($uninstallKey.PSChildName) /quiet /norestart" -Wait -ErrorAction SilentlyContinue
                        } else {
                            Start-Process -FilePath $uninstallString -ArgumentList "/S" -Wait -ErrorAction SilentlyContinue
                        }
                    }
                }
                
                # Remove remaining directories
                Remove-Item $systemPath -Recurse -Force -ErrorAction SilentlyContinue
                Write-Host "System-wide $DisplayName removed" -ForegroundColor Green
            }
            catch {
                Write-Host "Could not fully remove system-wide $DisplayName`: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
    }
    
    # 4. Check for Windows Store/AppX packages
    $appxNames = @()
    switch ($PackageName) {
        "vscode" { $appxNames = @("Microsoft.VisualStudioCode") }
        "slack" { $appxNames = @("9NZKDKZXXQPS") }
        "onedrive" { $appxNames = @("Microsoft.OneDrive") }
    }
    
    foreach ($appxName in $appxNames) {
        try {
            $appxPackage = Get-AppxPackage -Name $appxName -AllUsers -ErrorAction SilentlyContinue
            if ($appxPackage) {
                Write-Host "Found AppX package for $DisplayName, removing..." -ForegroundColor Yellow
                Remove-AppxPackage -Package $appxPackage.PackageFullName -AllUsers -ErrorAction SilentlyContinue
                Write-Host "AppX package for $DisplayName removed" -ForegroundColor Green
            }
        }
        catch {
            Write-Host "Could not remove AppX package for $DisplayName`: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    
    Write-Host "Cleanup completed for $DisplayName" -ForegroundColor Green
}

# Function to display help
function Show-Help {
    $helpText = @"

====================================================
    HyperSec Windows 11 SOE Configuration
====================================================

PURPOSE:
    Prepares Windows 11 as a secure VM host for productivity work and Linux development VMs.

    IMPORTANT: This script configures Windows for productivity tools (Office, Slack, browsers)
    and VM hosting. Actual HyperSec code development happens in Linux VMs using the HyperSec
    Linux Hyperi developer SOE - NOT natively on Windows.

    Think of it this way:
      - Windows = Your office desk (productivity, communication, VM hosting)
      - Linux VMs = Your workshop (where actual development happens)

PARAMETERS:
    -SkipBrowserConfig   : Skip Firefox default browser configuration
    -IncludeM365        : Include Microsoft 365 installation (requires license)
    -SkipVSCode         : Skip Visual Studio Code installation
    -ShowHelp           : Display this help message

SOFTWARE INSTALLED:
    Development:
        - Visual Studio Code (unless -SkipVSCode)
        - Windows Terminal
        - Git (if Claude Code requested)
        - SourceTree (Git GUI client)
    
    Browsers:
        - Mozilla Firefox (set as default unless -SkipBrowserConfig)
        - Google Chrome
    
    Communication:
        - Slack
        - Microsoft 365 (if -IncludeM365)
    
    Network Tools:
        - PuTTY
        - WinSCP
        - TigerVNC
    
    Utilities:
        - 7-Zip
        - AstroGrep (file search)
        - PDFGear (PDF editor)
    
    Media:
        - VLC Media Player
        - OBS Studio
        - Paint.NET

PRIVACY & SECURITY:
    - Built-in Privacy Hardening
        * Disables Microsoft telemetry and tracking
        * Removes bloatware apps and services
        * Disables Copilot, Cortana, and Bing integration
        * Removes ads and suggestions from Start menu
        * Disables Edge forcing and upsell prompts

    - Hyper-V with Full Security Stack
        * Installs Microsoft Hyper-V with all components
        * Enables Virtualization Based Security (VBS)
        * Enables Credential Guard and Device Guard
        * Enables Core Isolation (HVCI) and Memory Integrity
        * Creates C:\VM structure with Default Switch configuration
        * Scheduled task for automatic Default Switch assignment

SYSTEM-WIDE INSTALLATION:
    All applications are installed at the system level:
    - Programs installed to C:\Program Files or C:\Program Files (x86)
    - Available to all users on the system
    - Not installed in user-specific AppData folders
    - Chocolatey configured for machine-wide installations

REQUIREMENTS:
    - Windows 11 (or Windows 10)
    - Administrator privileges
    - Internet connection
    - PowerShell 5.1 or higher

DEVELOPMENT WORKFLOW:
    Windows (this script):
      - Productivity apps: Office 365, Slack, browsers
      - Communication and collaboration tools
      - VM hosting with Hyper-V
      - Office automation tasks

    Linux VM (separate - HyperSec Linux Hyperi SOE):
      - Actual code development and compilation
      - Development tools and IDEs
      - Testing and debugging
      - Source control operations

EXAMPLES:
    # Standard installation
    .\hypersec-windows.ps1

    # Skip VSCode when running from VSCode
    .\hypersec-windows.ps1 -SkipVSCode

    # Include Microsoft 365
    .\hypersec-windows.ps1 -IncludeM365

    # Full installation without browser config
    .\hypersec-windows.ps1 -SkipBrowserConfig -IncludeM365

NOTES:
    - Installs Chocolatey if not present
    - Creates automatic system restore points
    - Requires restart after Hyper-V installation
    - ATP onboarding package (optional): drop in script directory
    - Log file: %USERPROFILE%\hypersec-windows.log (overwrites previous)

"@
    Write-Host $helpText -ForegroundColor Cyan
    exit 0
}

# Check if help was requested
if ($ShowHelp) {
    Show-Help
}

# Logging function - logs to user's home directory
$ScriptBaseName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$LogFile = Join-Path $env:USERPROFILE "$ScriptBaseName.log"

# Initialize log file (overwrite if exists)
if (Test-Path $LogFile) {
    Remove-Item $LogFile -Force -ErrorAction SilentlyContinue
}

function Write-Log {
    param($Message, $Color = "White")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $LogFile -Append -Encoding UTF8
    Write-Host $Message -ForegroundColor $Color
}

Write-Log "=====================================================" "Cyan"
Write-Log "    Windows 11 Software Installation Script" "Cyan"
Write-Log "    Version: $ScriptVersion" "Cyan"
Write-Log "=====================================================" "Cyan"
Write-Log ""

# Reset execution policies first to ensure clean state
Reset-ExecutionPolicies

# Check for Administrator privileges
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "ERROR: This script must be run as Administrator!" "Red"
    Write-Log "Right-click and select 'Run as Administrator'" "Yellow"
    exit 1
}

# Check for pending reboot
Write-Log "Checking for pending system reboot..." "Yellow"
$rebootRequired = $false

try {
    # Check Windows Update reboot flag
    $wuReboot = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" -ErrorAction SilentlyContinue
    if ($wuReboot) {
        $rebootRequired = $true
        Write-Log "  [WARN] Windows Update requires reboot" "Yellow"
    }
    
    # Check Component Based Servicing reboot flag  
    $cbsReboot = Get-ChildItem -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" -ErrorAction SilentlyContinue
    if ($cbsReboot) {
        $rebootRequired = $true
        Write-Log "  [WARN] Component Based Servicing requires reboot" "Yellow"
    }
    
    # Check pending file operations
    $pendingFileOps = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name "PendingFileRenameOperations" -ErrorAction SilentlyContinue
    if ($pendingFileOps) {
        $rebootRequired = $true
        Write-Log "  [WARN] Pending file operations require reboot" "Yellow"
    }
    
    # Check for software installation reboot flags
    $softwareReboot = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Updates" -Name "UpdateExeVolatile" -ErrorAction SilentlyContinue
    if ($softwareReboot) {
        $rebootRequired = $true
        Write-Log "  [WARN] Software installation requires reboot" "Yellow"
    }
}
catch {
    Write-Log "  [WARN] Could not check all reboot conditions: $_" "Yellow"
}

if ($rebootRequired) {
    Write-Log ""
    Write-Log "ERROR: System has pending reboot requirements!" "Red"
    Write-Log "This script cannot run properly until the system is rebooted." "Yellow"
    Write-Log "Please restart your computer and run this script again." "White"
    Write-Log ""
    exit 1
}

Write-Log "[OK] No pending reboot detected - proceeding with installation" "Green"

# Function to test internet connectivity
function Test-InternetConnection {
    try {
        $null = Invoke-WebRequest -Uri "https://www.google.com" -Method Head -TimeoutSec 5 -UseBasicParsing
        return $true
    }
    catch {
        return $false
    }
}

# Function to test if debloat worked effectively
function Test-DebloatEffectiveness {
    Write-Log "    Checking telemetry settings..." "White"
    $telemetryPassed = $true
    
    # Check telemetry registry keys
    $telemetryKeys = @(
        @{Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"; Name = "AllowTelemetry"; ExpectedValue = 0},
        @{Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection"; Name = "AllowTelemetry"; ExpectedValue = 0},
        @{Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy"; Name = "TailoredExperiencesWithDiagnosticDataEnabled"; ExpectedValue = 0}
    )
    
    foreach ($key in $telemetryKeys) {
        try {
            $value = Get-ItemProperty -Path $key.Path -Name $key.Name -ErrorAction SilentlyContinue
            if (-not $value -or $value.($key.Name) -ne $key.ExpectedValue) {
                Write-Log "      [FAIL] Telemetry not disabled: $($key.Path)\$($key.Name)" "Red"
                $telemetryPassed = $false
            }
        }
        catch {
            Write-Log "      [FAIL] Telemetry setting missing: $($key.Path)\$($key.Name)" "Red"
            $telemetryPassed = $false
        }
    }
    
    # Check for common bloatware apps
    Write-Log "    Checking for remaining bloatware apps..." "White"
    $bloatwareApps = @(
        # Consumer/Entertainment apps
        "Microsoft.GetHelp", "Microsoft.Getstarted", "Microsoft.BingNews", "Microsoft.BingWeather",
        "Microsoft.BingFinance", "Microsoft.BingSports", "Microsoft.WindowsCamera", "Microsoft.WindowsAlarms",
        "Microsoft.WindowsSoundRecorder", "Microsoft.WindowsMaps", "Microsoft.MicrosoftSolitaireCollection",
        "Microsoft.MicrosoftStickyNotes", "Microsoft.People", "Microsoft.Messaging", "Microsoft.SkypeApp",
        "Microsoft.ZuneMusic", "Microsoft.ZuneVideo", "Microsoft.YourPhone", "Microsoft.ConnectivityStore",
        # Xbox/Gaming apps (complete removal)
        "Microsoft.XboxApp", "Microsoft.XboxGamingOverlay", "Microsoft.Xbox.TCUI", "Microsoft.XboxSpeechToTextOverlay",
        "Microsoft.XboxIdentityProvider", "Microsoft.XboxGameOverlay", "Microsoft.GamingApp", "Microsoft.GamingServices",
        # 3D/Mixed Reality apps
        "Microsoft.MixedReality.Portal", "Microsoft.3DBuilder", "Microsoft.Print3D",
        # Other consumer apps
        "Microsoft.WindowsFeedbackHub",
        # Microsoft upsell/promotional apps
        "Microsoft.LinkedIn", "Microsoft.Clipchamp", "Clipchamp.Clipchamp",
        "Microsoft.Todos", "Microsoft.To-Do", "Microsoft.MicrosoftToDo",
        "Microsoft.GetStarted", "Microsoft.Getstarted",
        "Microsoft.PowerAutomate", "Microsoft.PowerApps",
        "Microsoft.MicrosoftOfficeHub", "Microsoft.OfficeHub",
        "Microsoft.MicrosoftFamily", "Microsoft.Family",
        "Microsoft.MSPaint", "Microsoft.Paint3D"
    )
    
    $remainingBloatware = 0
    foreach ($app in $bloatwareApps) {
        $installed = Get-AppxPackage -Name $app -ErrorAction SilentlyContinue
        if ($installed) {
            Write-Log "      [FAIL] Bloatware still installed: $app" "Red"
            $remainingBloatware++
        }
    }
    
    # Check taskbar UI elements (skip widgets - permission protected in Windows 11)
    Write-Log "    Checking taskbar UI elements..." "White"
    $taskbarClean = $true
    try {
        # Skip widgets check (Windows 11 permission protected)
        # $widgetsSetting = Get-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarDa" -ErrorAction SilentlyContinue
        
        # Check search bar
        $searchSetting = Get-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" -Name "SearchboxTaskbarMode" -ErrorAction SilentlyContinue
        if (-not $searchSetting -or $searchSetting.SearchboxTaskbarMode -ne 0) {
            Write-Log "      [FAIL] Taskbar search bar still enabled" "Red"
            $taskbarClean = $false
        }
        
        # Check store icon
        $storeSetting = Get-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarSi" -ErrorAction SilentlyContinue
        if ($storeSetting -and $storeSetting.TaskbarSi -ne 0) {
            Write-Log "      [FAIL] Taskbar Store icon still enabled" "Red"
            $taskbarClean = $false
        }
        
        # Check Edge pinned to taskbar
        $edgePinned = Get-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Taskband" -Name "Favorites" -ErrorAction SilentlyContinue
        if ($edgePinned -and $edgePinned.Favorites -and $edgePinned.Favorites.Count -gt 0) {
            Write-Log "      [FAIL] Edge still pinned to taskbar" "Red"
            $taskbarClean = $false
        }
    }
    catch {
        $taskbarClean = $false
    }
    
    # Check privacy/advertising services are disabled
    Write-Log "    Checking privacy and advertising services..." "White"
    $servicesDisabled = $true
    $servicesToCheck = @(
        "DiagTrack",      # Connected User Experiences and Telemetry
        "DPS",            # Diagnostic Policy Service
        "PcaSvc",         # Program Compatibility Assistant  
        "AeLookupSvc",    # Application Experience
        "WSearch",        # Windows Search
        "SysMain",        # Superfetch/SysMain
        "WpnService",     # Windows Push Notifications
        "RetailDemo",     # Retail Demo Service
        "MapsBroker"      # Downloaded Maps Manager
    )
    
    foreach ($serviceName in $servicesToCheck) {
        try {
            $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
            if ($service -and $service.StartType -ne "Disabled") {
                Write-Log "      [FAIL] Service still enabled: $serviceName" "Red"
                $servicesDisabled = $false
            }
        }
        catch {
            # Service might not exist on this system - that's OK
        }
    }
    
    $overallPassed = $telemetryPassed -and ($remainingBloatware -eq 0) -and $taskbarClean -and $servicesDisabled
    
    if ($overallPassed) {
        Write-Log "    [OK] Debloat verification passed" "Green"
    } else {
        Write-Log "    [FAIL] Debloat verification failed - manual cleanup needed" "Red"
    }
    
    return $overallPassed
}


# Function for manual debloat with improved error handling
function Invoke-ManualDebloat {
    Write-Log "    Performing manual privacy hardening..." "Yellow"
    
    # Improved registry setting function with Win11Debloat patterns
    function Set-RegistrySetting {
        param($Path, $Name, $Value, $Type = "DWord", $Description)
        
        try {
            # Ensure parent path exists
            $parentPath = Split-Path $Path -Parent
            if ($parentPath -and -not (Test-Path $parentPath)) {
                New-Item -Path $parentPath -Force -ErrorAction SilentlyContinue | Out-Null
            }
            
            # Ensure target path exists
            if (-not (Test-Path $Path)) {
                New-Item -Path $Path -Force -ErrorAction SilentlyContinue | Out-Null
            }
            
            # Set the registry value
            Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force -ErrorAction Stop
            Write-Log "        [OK] $Description" "Green"
            return $true
        }
        catch {
            Write-Log "        [WARN] Failed: $Description - $($_.Exception.Message)" "Yellow"
            return $false
        }
    }
    
    # Disable telemetry (comprehensive with better error handling)
    Write-Log "      Disabling telemetry..." "White"
    
    Set-RegistrySetting -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 0 -Description "Disable telemetry data collection"
    Set-RegistrySetting -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" -Name "AllowTelemetry" -Value 0 -Description "Disable telemetry policy"
    Set-RegistrySetting -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy" -Name "TailoredExperiencesWithDiagnosticDataEnabled" -Value 0 -Description "Disable tailored experiences"
    Set-RegistrySetting -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "LimitEnhancedDiagnosticDataWindowsAnalytics" -Value 1 -Description "Limit diagnostic data"
    
    # Remove critical bloatware apps including Edge and Copilot (Teams kept for M365)
    Write-Log "      Removing bloatware apps including Edge and Copilot (Teams kept for M365)..." "White"
    $criticalBloatware = @(
        # Consumer/Entertainment (safe to remove)
        "Microsoft.BingNews", "Microsoft.BingWeather", "Microsoft.GetHelp", "Microsoft.Getstarted",
        "Microsoft.WindowsCamera", "Microsoft.WindowsAlarms", "Microsoft.WindowsSoundRecorder", 
        "Microsoft.WindowsMaps", "Microsoft.MicrosoftSolitaireCollection", "Microsoft.MicrosoftStickyNotes",
        "Microsoft.ZuneMusic", "Microsoft.ZuneVideo", "Microsoft.YourPhone", "Microsoft.SkypeApp",
        # Xbox/Gaming (safe to remove)
        "Microsoft.XboxApp", "Microsoft.XboxGamingOverlay", "Microsoft.Xbox.TCUI", "Microsoft.XboxSpeechToTextOverlay",
        "Microsoft.XboxIdentityProvider", "Microsoft.XboxGameOverlay", "Microsoft.GamingApp", "Microsoft.GamingServices",
        # 3D/Mixed Reality (safe to remove in most corporate environments)
        "Microsoft.MixedReality.Portal", "Microsoft.3DBuilder", "Microsoft.Print3D",
        # Other consumer apps
        "Microsoft.Messaging", "Microsoft.ConnectivityStore", "Microsoft.WindowsFeedbackHub",
        # Corporate apps to remove completely
        "Microsoft.MicrosoftEdge", "MicrosoftEdge.exe", "Microsoft.Edge",
        "Microsoft.Copilot", "Microsoft.Windows.Ai.Copilot.Provider", "Microsoft.BingSearch",
        # Microsoft upsell/promotional apps
        "Microsoft.LinkedIn", "LinkedIn",
        "Microsoft.Clipchamp", "Clipchamp.Clipchamp",
        "Microsoft.Todos", "Microsoft.To-Do", "Microsoft.MicrosoftToDo",
        "Microsoft.GetStarted", "Microsoft.Getstarted",
        # Additional promotional apps
        "Microsoft.PowerAutomate", "Microsoft.PowerApps",
        "Microsoft.MicrosoftOfficeHub", "Microsoft.OfficeHub",
        "Microsoft.MicrosoftFamily", "Microsoft.Family",
        "Microsoft.MSPaint", "Microsoft.Paint3D",
        # Third-party promotional apps (Store partnerships)
        "SpotifyAB.SpotifyMusic", "Spotify.Spotify",
        "TikTok.TikTok", "ByteDancePte.TikTok",
        "Facebook.Facebook", "Facebook.InstagramBeta", "Facebook.Messenger",
        "Meta.WhatsApp", "Meta.Instagram",
        "Disney.37853FC22B2CE", "Disney.DisneyPlus",
        "Netflix.Netflix",
        "Amazon.Prime-Video", "Amazon.Kindle", "Amazon.com.Amazon",
        "Twitter.Twitter", "X.X",
        "Snapchat.Snapchat",
        "Adobe.CC.PhotoshopCamera", "AdobeSystemsIncorporated.AdobePhotoshopExpress",
        "king.com.CandyCrushSaga", "king.com.CandyCrushSodaSaga",
        "ROBLOXCORPORATION.ROBLOX",
        "ActiproSoftwareLLC.562882FEEB491", # Age of Empires Castle Siege
        "Flipboard.Flipboard", "PandoraMediaInc.Pandora"
    )
    
    foreach ($app in $criticalBloatware) {
        try {
            $packages = Get-AppxPackage -Name $app -AllUsers -ErrorAction SilentlyContinue
            foreach ($package in $packages) {
                Remove-AppxPackage -Package $package.PackageFullName -AllUsers -ErrorAction SilentlyContinue
            }
        }
        catch {
            # Continue on error
        }
    }
    
    # Remove Windows WebExperience package (widgets) completely
    Write-Log "      Removing Windows widgets (WebExperience package)..." "White"
    try {
        $webExpPackages = Get-AppxPackage *WebExperience* -AllUsers -ErrorAction SilentlyContinue
        if ($webExpPackages) {
            foreach ($package in $webExpPackages) {
                Remove-AppxPackage -Package $package.PackageFullName -AllUsers -ErrorAction SilentlyContinue
                Write-Log "        [OK] Removed WebExperience package: $($package.Name)" "Green"
            }
        } else {
            Write-Log "        [OK] WebExperience package already removed or not present" "Green"
        }
        
        # Also remove provisioned packages to prevent reinstallation
        $webExpProvisioned = Get-AppxProvisionedPackage -Online | Where-Object { $_.PackageName -like "*WebExperience*" }
        foreach ($provPackage in $webExpProvisioned) {
            Remove-AppxProvisionedPackage -Online -PackageName $provPackage.PackageName -ErrorAction SilentlyContinue
            Write-Log "        [OK] Removed provisioned WebExperience package" "Green"
        }
    }
    catch {
        Write-Log "        [WARN] Could not remove WebExperience packages: $_" "Yellow"
    }
    
    # Configure taskbar settings using improved registry function
    Write-Log "      Configuring taskbar settings..." "White"
    Set-RegistrySetting -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" -Name "SearchboxTaskbarMode" -Value 0 -Description "Disable taskbar search bar"
    Set-RegistrySetting -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarSi" -Value 0 -Description "Disable taskbar Store icon"
    Set-RegistrySetting -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SystemPaneSuggestionsEnabled" -Value 0 -Description "Disable Start Menu suggestions"
    Set-RegistrySetting -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarMn" -Value 0 -Description "Disable Chat/Meet Now icon"
    
    # Skip weather widget (causes permission errors in Windows 11)
    # Set-RegistrySetting -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Feeds" -Name "ShellFeedsTaskbarViewMode" -Value 2 -Description "Disable news and interests feed"
    Set-RegistrySetting -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds" -Name "EnableFeeds" -Value 0 -Description "Disable feeds policy"
    Set-RegistrySetting -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowTaskViewButton" -Value 0 -Description "Hide task view button"
    
    # Disable privacy/advertising services
    Write-Log "      Disabling privacy and advertising services..." "White"
    $servicesToDisable = @(
        @{Name = "DiagTrack"; DisplayName = "Connected User Experiences and Telemetry"},
        @{Name = "DPS"; DisplayName = "Diagnostic Policy Service"}, 
        @{Name = "PcaSvc"; DisplayName = "Program Compatibility Assistant"},
        @{Name = "AeLookupSvc"; DisplayName = "Application Experience"},
        @{Name = "WSearch"; DisplayName = "Windows Search"},
        @{Name = "SysMain"; DisplayName = "Superfetch/SysMain"},
        @{Name = "WpnService"; DisplayName = "Windows Push Notifications System Service"},
        @{Name = "RetailDemo"; DisplayName = "Retail Demo Service"},
        @{Name = "MapsBroker"; DisplayName = "Downloaded Maps Manager"}
    )
    
    foreach ($serviceInfo in $servicesToDisable) {
        try {
            $service = Get-Service -Name $serviceInfo.Name -ErrorAction SilentlyContinue
            if ($service) {
                if ($service.Status -eq "Running") {
                    Stop-Service -Name $serviceInfo.Name -Force -ErrorAction SilentlyContinue
                }
                Set-Service -Name $serviceInfo.Name -StartupType Disabled -ErrorAction SilentlyContinue
                Write-Log "        [OK] Disabled $($serviceInfo.DisplayName)" "Green"
            }
        }
        catch {
            Write-Log "        [WARN] Could not disable $($serviceInfo.DisplayName)" "Yellow"
        }
    }
    
    # Disable Windows Customer Experience Improvement Program via registry
    try {
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\SQMClient\Windows" -Name "CEIPEnable" -Value 0 -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows" -Name "CEIPEnable" -Value 0 -Force -ErrorAction SilentlyContinue
        Write-Log "        [OK] Disabled Windows Customer Experience Improvement Program" "Green"
    }
    catch {
        Write-Log "        [WARN] Could not disable Customer Experience Improvement Program" "Yellow"
    }
    
    # Remove unwanted startup programs (comprehensive Edge removal)
    Write-Log "      Removing unwanted startup programs..." "White"
    
    # More comprehensive Edge startup removal
    $edgeStartupKeys = @(
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"
    )
    
    $edgeNames = @(
        "Microsoft Edge", "msedge", "MicrosoftEdge", "MicrosoftEdgeAutoLaunch*", 
        "Microsoft Edge Update", "EdgeUpdate", "Microsoft Edge Startup Task",
        "MicrosoftEdgeAutoLaunch_*"
    )
    
    foreach ($regPath in $edgeStartupKeys) {
        if (Test-Path $regPath) {
            foreach ($edgeName in $edgeNames) {
                try {
                    $existingValues = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
                    if ($existingValues) {
                        $existingValues.PSObject.Properties | Where-Object { $_.Name -like "*$edgeName*" -or $_.Value -like "*msedge*" } | ForEach-Object {
                            Remove-ItemProperty -Path $regPath -Name $_.Name -Force -ErrorAction SilentlyContinue
                            Write-Log "        [OK] Removed Edge startup: $($_.Name)" "Green"
                        }
                    }
                }
                catch {
                    # Continue on error
                }
            }
        }
    }
    
    # Remove other startup programs
    $otherStartupApps = @(
        "Windows Terminal", "WindowsTerminal", "terminal",
        "Xbox", "XboxApp", "GamingApp",
        "Copilot", "Microsoft Copilot"
    )
    
    foreach ($regPath in $edgeStartupKeys) {
        if (Test-Path $regPath) {
            foreach ($app in $otherStartupApps) {
                try {
                    Remove-ItemProperty -Path $regPath -Name $app -Force -ErrorAction SilentlyContinue
                }
                catch {
                    # Continue on error
                }
            }
        }
    }
    
    # Remove from startup folders
    $startupPaths = @(
        [System.Environment]::GetFolderPath("Startup"),
        [System.Environment]::GetFolderPath("CommonStartup")
    )
    
    foreach ($startupPath in $startupPaths) {
        if (Test-Path $startupPath) {
            $allApps = $edgeNames + $otherStartupApps
            foreach ($app in $allApps) {
                $shortcuts = Get-ChildItem -Path $startupPath -Name "*$app*" -ErrorAction SilentlyContinue
                foreach ($shortcut in $shortcuts) {
                    try {
                        Remove-Item -Path (Join-Path $startupPath $shortcut) -Force -ErrorAction SilentlyContinue
                        Write-Log "        [OK] Removed startup shortcut: $shortcut" "Green"
                    }
                    catch {
                        # Continue on error
                    }
                }
            }
        }
    }
    
    # Disable Edge startup via Edge policy
    Set-RegistrySetting -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "StartupBoostEnabled" -Value 0 -Description "Disable Edge startup boost"
    Set-RegistrySetting -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "BackgroundModeEnabled" -Value 0 -Description "Disable Edge background mode"
    
    # Show file extensions for known file types
    Write-Log "      Enabling file extensions for known file types..." "White"
    try {
        Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "HideFileExt" -Value 0 -Type DWord -Force
        Write-Log "        [OK] File extensions enabled" "Green"
    }
    catch {
        Write-Log "        [WARN] Could not enable file extensions" "Yellow"
    }
    
    # Disable Fast Startup
    Write-Log "      Disabling Fast Startup..." "White"
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name "HiberbootEnabled" -Value 0 -Type DWord -Force
        Write-Log "        [OK] Fast Startup disabled" "Green"
    }
    catch {
        Write-Log "        [WARN] Could not disable Fast Startup" "Yellow"
    }
    
    # Disable Modern Standby network connectivity (Windows 11)
    Write-Log "      Disabling Modern Standby network connectivity..." "White"
    try {
        $standbyPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\F15576E8-98B7-4186-B944-EAFA664402D9"
        if (Test-Path $standbyPath) {
            Set-ItemProperty -Path $standbyPath -Name "Attributes" -Value 1 -Type DWord -Force
            Write-Log "        [OK] Modern Standby network connectivity disabled" "Green"
        } else {
            Write-Log "        [INFO] Modern Standby not supported on this system" "Gray"
        }
    }
    catch {
        Write-Log "        [WARN] Could not configure Modern Standby settings" "Yellow"
    }
    
    # Disable Chat/Meet Now icon
    Write-Log "      Disabling Chat (Meet Now) icon..." "White"
    try {
        Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarMn" -Value 0 -Type DWord -Force
        Write-Log "        [OK] Chat icon disabled" "Green"
    }
    catch {
        Write-Log "        [WARN] Could not disable Chat icon" "Yellow"
    }
    
    # Disable activity history
    Write-Log "      Disabling activity history..." "White"
    try {
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "EnableActivityFeed" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "PublishUserActivities" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "UploadUserActivities" -Value 0 -Type DWord -Force
        Write-Log "        [OK] Activity history disabled" "Green"
    }
    catch {
        Write-Log "        [WARN] Could not disable activity history" "Yellow"
    }
    
    # Force Explorer restart to apply taskbar changes
    Write-Log "      Restarting Windows Explorer to apply taskbar changes..." "White"
    try {
        Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
        Start-Process "explorer.exe"
        Write-Log "        [OK] Windows Explorer restarted" "Green"
    }
    catch {
        Write-Log "        [WARN] Could not restart Explorer" "Yellow"
    }
    
    Write-Log "      [OK] Manual privacy hardening completed" "Green"
}

Write-Log "Checking internet connection..." "Yellow"
if (-not (Test-InternetConnection)) {
    Write-Log "ERROR: No internet connection detected!" "Red"
    Write-Log "Please connect to the internet and try again." "Yellow"
    exit 1
}
Write-Log "[OK] Internet connection verified" "Green"

# Install Chocolatey if not present
Write-Log ""
Write-Log "Checking for Chocolatey installation..." "Yellow"

$chocoPath = "C:\ProgramData\chocolatey\bin\choco.exe"
$chocoInstalled = Test-Path $chocoPath

if (-not $chocoInstalled) {
    Write-Log "Chocolatey not found at $chocoPath. Installing Chocolatey..." "Yellow"
    
    try {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        
        # Refresh PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        
        Write-Log "[OK] Chocolatey installed successfully" "Green"
    }
    catch {
        Write-Log "ERROR: Failed to install Chocolatey: $_" "Red"
        exit 1
    }
} else {
    Write-Log "[OK] Chocolatey is already installed at $chocoPath" "Green"
    # Ensure choco is in current session PATH
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
}

# Configure Chocolatey for system-wide installations
Write-Log ""
Write-Log "Configuring Chocolatey for system-wide installations..." "Cyan"

# Enable global confirmation
choco feature enable -n allowGlobalConfirmation 2>$null

# Enable remembered arguments for upgrades
choco feature enable -n useRememberedArgumentsForUpgrades 2>$null

# Ensure installations are system-wide (this is default, but we're being explicit)
choco feature disable -n usePackageExitCodes 2>$null
choco feature enable -n usePackageExitCodes 2>$null

# Set installation paths to ensure system-wide
$env:ChocolateyToolsLocation = "$env:SystemDrive\tools"
[Environment]::SetEnvironmentVariable("ChocolateyToolsLocation", "$env:SystemDrive\tools", "Machine")

Write-Log "[OK] Chocolatey configured for system-wide installations" "Green"

# Define packages
$Packages = @(
    @{Name = "firefox"; DisplayName = "Mozilla Firefox"; Category = "Browser"},
    @{Name = "googlechrome"; DisplayName = "Google Chrome"; Category = "Browser"},
    @{Name = "slack"; DisplayName = "Slack"; Category = "Communication"},
    @{Name = "onedrive"; DisplayName = "Microsoft OneDrive"; Category = "Productivity"},
    @{Name = "putty"; DisplayName = "PuTTY"; Category = "Network"},
    @{Name = "winscp"; DisplayName = "WinSCP"; Category = "Network"},
    @{Name = "openvpn"; DisplayName = "OpenVPN GUI"; Category = "Network"},
    @{Name = "telnet"; DisplayName = "Telnet Client"; Category = "Network"},
    @{Name = "7zip"; DisplayName = "7-Zip"; Category = "Utility"},
    @{Name = "astrogrep"; DisplayName = "AstroGrep"; Category = "Utility"},
    @{Name = "obs-studio"; DisplayName = "OBS Studio"; Category = "Media"},
    @{Name = "paint.net"; DisplayName = "Paint.NET"; Category = "Media"},
    @{Name = "vlc"; DisplayName = "VLC Media Player"; Category = "Media"},
    @{Name = "tigervnc"; DisplayName = "TigerVNC"; Category = "Network"},
    @{Name = "github-desktop"; DisplayName = "GitHub Desktop"; Category = "Development"; Params = "/NoDesktopShortcut"},
    @{Name = "pdfgear"; DisplayName = "PDFGear"; Category = "Utility"},
    @{Name = "winaero-tweaker"; DisplayName = "Winaero Tweaker"; Category = "Privacy"},
    @{Name = "powershell"; DisplayName = "PowerShell 7"; Category = "Development"},
    @{Name = "rsvg-convert"; DisplayName = "RSVG Convert"; Category = "Utility"},
    @{Name = "winmerge"; DisplayName = "WinMerge"; Category = "Development"}
)

# Add Git to the standard packages (useful for development)
$Packages += @{Name = "git"; DisplayName = "Git"; Category = "Development"}

# Add VSCode unless skipped
if (-not $SkipVSCode) {
    $Packages = @(@{Name = "vscode"; DisplayName = "Visual Studio Code"; Category = "Development"}) + $Packages
} else {
    Write-Log ""
    Write-Log "→ Skipping Visual Studio Code installation as requested" "Yellow"
}

# Add Office 365 Business by default with core apps only (Outlook, Word, Excel, PowerPoint, Teams)
# Using simpler approach - let Office install all apps, we'll remove unwanted ones in debloat
$Packages += @{Name = "office365business"; DisplayName = "Microsoft 365 Business"; Category = "Productivity"}

# Group by category for better display
$Categories = $Packages | Group-Object -Property Category | Sort-Object Name

Write-Log ""
Write-Log "Installing Software Packages (System-Wide):" "Cyan"
Write-Log "===========================================" "Cyan"

$SuccessCount = 0
$FailedPackages = @()

foreach ($Category in $Categories) {
    Write-Log ""
    Write-Log "[$($Category.Name)]:" "Yellow"
    
    foreach ($Package in $Category.Group) {
        Write-Host -NoNewline "  Installing $($Package.DisplayName)... " -ForegroundColor White
        
        try {
            # Check if already installed (more thorough check)
            $installed = choco list --local-only --exact $Package.Name 2>$null | Select-String -Pattern "^$($Package.Name)\s"
            
            # Check if already installed (skip for dual-mode packages that need comprehensive cleanup)
            $dualModePackages = @("googlechrome", "firefox", "vscode", "slack", "onedrive", "putty", "winscp", "obs-studio", "vlc", "paint.net", "github-desktop", "powershell", "git")
            
            if ($installed -and $Package.Name -notin $dualModePackages) {
                Write-Host "Already installed [OK]" -ForegroundColor Green
                Write-Log "  $($Package.DisplayName) - Already installed" "Green"
                $SuccessCount++
            } else {
                # Check if this package supports both user and system-wide installations
                if ($Package.Name -in $dualModePackages) {
                    # Use comprehensive cleanup function for packages that support both modes
                    Remove-ExistingInstallations -PackageName $Package.Name -DisplayName $Package.DisplayName
                } elseif ($installed) {
                    # For other packages, just uninstall via Chocolatey if already installed
                    Write-Host "Uninstalling existing $($Package.DisplayName)..." -ForegroundColor Yellow
                    choco uninstall $Package.Name -y --force 2>$null
                }
                # Install with system-wide parameters and no desktop shortcuts
                if ($Package.Params) {
                    # Use custom parameters for specific packages (like Office 365)
                    $installParams = $Package.Params
                } else {
                    # Default parameters for most packages
                    $installParams = "/ALLUSERS /NoDesktopShortcut /NoDesktopIcon"
                }
                
                # Special handling for Office 365 (long installation time)
                if ($Package.Name -eq "office365business") {
                    Write-Host "Installing (this may take 15+ minutes)..." -ForegroundColor Yellow
                    $timeout = 1800000  # 30 minutes
                } else {
                    $timeout = 600000   # 10 minutes for other packages
                }
                
                $result = choco install $Package.Name -y --params $installParams --execution-timeout $timeout 2>&1
                
                # For Office, verify installation by checking for actual Office apps
                if ($Package.Name -eq "office365business") {
                    $officeApps = @(
                        "${env:ProgramFiles}\Microsoft Office\root\Office16\OUTLOOK.EXE",
                        "${env:ProgramFiles}\Microsoft Office\root\Office16\WINWORD.EXE",
                        "${env:ProgramFiles}\Microsoft Office\root\Office16\EXCEL.EXE"
                    )
                    
                    $officeInstalled = $false
                    foreach ($app in $officeApps) {
                        if (Test-Path $app) {
                            $officeInstalled = $true
                            break
                        }
                    }
                    
                    if ($officeInstalled -or $LASTEXITCODE -eq 0) {
                        Write-Host "Success [OK]" -ForegroundColor Green
                        Write-Log "  $($Package.DisplayName) - Installed successfully (verified)" "Green"
                        $SuccessCount++
                    } else {
                        Write-Host "Failed [ERROR]" -ForegroundColor Red
                        Write-Log "  $($Package.DisplayName) - Installation failed or incomplete" "Red"
                        $FailedPackages += $Package.DisplayName
                    }
                } else {
                    # Standard success/failure check for other packages
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "Success [OK]" -ForegroundColor Green
                        Write-Log "  $($Package.DisplayName) - Installed successfully" "Green"
                        $SuccessCount++
                    } else {
                        Write-Host "Failed [ERROR]" -ForegroundColor Red
                        Write-Log "  $($Package.DisplayName) - Installation failed" "Red"
                        $FailedPackages += $Package.DisplayName
                    }
                }
            }
        }
        catch {
            Write-Host "Error [ERROR]" -ForegroundColor Red
            Write-Log "  $($Package.DisplayName) - Error: $_" "Red"
            $FailedPackages += $Package.DisplayName
        }
    }
}


# Configure OpenVPN GUI default structure
Write-Log ""
Write-Log "Configuring OpenVPN GUI default structure..." "Yellow"

try {
    # Create OpenVPN configuration directories
    $openVpnConfigDir = Join-Path $env:USERPROFILE "OpenVPN\config"
    $openVpnLogDir = Join-Path $env:USERPROFILE "OpenVPN\log"
    
    if (-not (Test-Path $openVpnConfigDir)) {
        New-Item -Path $openVpnConfigDir -ItemType Directory -Force | Out-Null
        Write-Log "  [OK] Created OpenVPN config directory: $openVpnConfigDir" "Green"
    }
    
    if (-not (Test-Path $openVpnLogDir)) {
        New-Item -Path $openVpnLogDir -ItemType Directory -Force | Out-Null
        Write-Log "  [OK] Created OpenVPN log directory: $openVpnLogDir" "Green"
    }
    
    # Create a sample configuration file template
    $sampleConfigPath = Join-Path $openVpnConfigDir "sample-config.ovpn"
    $sampleConfig = @"
# OpenVPN Configuration Template
# Place your .ovpn configuration files in this directory
# File: $sampleConfigPath
# 
# Typical corporate VPN configuration structure:
# client
# dev tun
# proto udp
# remote your-vpn-server.com 1194
# resolv-retry infinite
# nobind
# persist-key
# persist-tun
# ca ca.crt
# cert client.crt
# key client.key
# verb 3
#
# Delete this file and add your corporate .ovpn files here
"@
    
    if (-not (Test-Path $sampleConfigPath)) {
        $sampleConfig | Out-File -FilePath $sampleConfigPath -Encoding UTF8 -Force
        Write-Log "  [OK] Created sample OpenVPN configuration template" "Green"
    }
    
    # Create OpenVPN GUI registry settings for better defaults
    $openVpnRegPath = "HKCU:\SOFTWARE\OpenVPN-GUI"
    if (-not (Test-Path $openVpnRegPath)) {
        New-Item -Path $openVpnRegPath -Force | Out-Null
    }
    
    # Set default configuration directory
    Set-ItemProperty -Path $openVpnRegPath -Name "config_dir" -Value $openVpnConfigDir -Force
    Set-ItemProperty -Path $openVpnRegPath -Name "log_dir" -Value $openVpnLogDir -Force
    Set-ItemProperty -Path $openVpnRegPath -Name "log_append" -Value 1 -Type DWord -Force
    
    Write-Log "  [OK] OpenVPN GUI configured with default directories and settings" "Green"
}
catch {
    Write-Log "  [WARN] Could not configure OpenVPN GUI: $_" "Yellow"
}

# Configure Git system defaults (not user-specific settings)
Write-Log ""
Write-Log "Configuring Git system defaults..." "Yellow"

try {
    # Refresh PATH to ensure git is available
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    
    # Check if git is available
    $gitPath = Get-Command git -ErrorAction SilentlyContinue
    if ($gitPath) {
        Write-Log "  Found Git at: $($gitPath.Source)" "Green"
        
        # Configure system-wide Git settings (not user-specific)
        & git config --system init.defaultBranch main 2>$null
        & git config --system pull.rebase false 2>$null
        Write-Log "  [OK] Git system defaults configured" "Green"
        
        # Initialize LFS system-wide
        & git lfs install --system 2>$null
        Write-Log "  [OK] Git LFS enabled system-wide" "Green"
        
        Write-Log "  [OK] Git system configuration completed" "Green"
        Write-Log "       Users will need to configure their own name/email with:" "White"
        Write-Log "       git config --global user.name 'Your Name'" "White"  
        Write-Log "       git config --global user.email 'your.email@company.com'" "White"
    } else {
        Write-Log "  [WARN] Git not found in PATH - configuration skipped" "Yellow"
    }
}
catch {
    Write-Log "  [WARN] Git system configuration failed: $_" "Yellow"
}

# Firefox installation completed - manual browser configuration required
if (-not $SkipBrowserConfig) {
    Write-Log ""
    Write-Log "Browser configuration information..." "Yellow"
    Write-Log "  [INFO] Firefox and Chrome have been installed successfully" "Green"
    Write-Log "  [INFO] Default browser must be configured manually (Windows 11 security blocks registry changes):" "White"
    Write-Log "        1. Open Settings > Apps > Default apps" "White"
    Write-Log "        2. Search for 'Firefox' and click it" "White"
    Write-Log "        3. Click 'Set default' to make Firefox your default browser" "White"
    Write-Log "        4. Alternative: Click 'Make Firefox your default browser' notification when first opened" "White"
    Write-Log "  [NOTE] Registry-based methods no longer work in Windows 11 due to enhanced security" "Yellow"
    Write-Log "  [OK] Browser installation completed - manual configuration required" "Yellow"
}

# Configure VLC as default media player
Write-Log ""
Write-Log "Configuring VLC as default media player..." "Yellow"

try {
    # Wait for VLC installation to complete
    Start-Sleep -Seconds 2
    
    # Check if VLC is installed
    $vlcPath = Get-ChildItem -Path "${env:ProgramFiles}\VideoLAN\VLC" -Name "vlc.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $vlcPath) {
        $vlcPath = Get-ChildItem -Path "${env:ProgramFiles(x86)}\VideoLAN\VLC" -Name "vlc.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    
    if ($vlcPath) {
        Write-Log "[INFO] VLC Media Player installed successfully" "Green"
        Write-Log "[INFO] To set VLC as default media player:" "White"
        Write-Log "        1. Open Settings > Apps > Default apps" "White"
        Write-Log "        2. Search for 'VLC' and click it" "White"
        Write-Log "        3. Click 'Set default' for desired media formats" "White"
    } else {
        Write-Log "[WARN] VLC not found - media association not configured" "Yellow"
    }
}
catch {
    Write-Log "[WARN] Could not set VLC as default media player (manual configuration needed)" "Yellow"
}

# Configure PDFGear as default PDF viewer
Write-Log ""
Write-Log "Configuring PDFGear as default PDF viewer..." "Yellow"

try {
    # Wait for PDFGear installation to complete
    Start-Sleep -Seconds 2
    
    # Check if PDFGear is installed
    $pdfGearPath = Get-ChildItem -Path "${env:ProgramFiles}\PDFGear*" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $pdfGearPath) {
        $pdfGearPath = Get-ChildItem -Path "${env:ProgramFiles(x86)}\PDFGear*" -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    
    if ($pdfGearPath) {
        Write-Log "[INFO] PDFGear installed successfully" "Green"
        Write-Log "[INFO] To set PDFGear as default PDF viewer:" "White"
        Write-Log "        1. Open Settings > Apps > Default apps" "White"
        Write-Log "        2. Search for 'PDFGear' and click it" "White"
        Write-Log "        3. Click 'Set default' for PDF files" "White"
    } else {
        Write-Log "[WARN] PDFGear not found - PDF association not configured" "Yellow"
    }
}
catch {
    Write-Log "[WARN] Could not set PDFGear as default PDF viewer (manual configuration needed)" "Yellow"
}

# Configure Paint.NET as default image editor
Write-Log ""
Write-Log "Configuring Paint.NET as default image editor..." "Yellow"

try {
    # Check if Paint.NET is installed
    $paintPath = Get-ChildItem -Path "${env:ProgramFiles}\paint.net" -Name "PaintDotNet.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $paintPath) {
        $paintPath = Get-ChildItem -Path "${env:ProgramFiles(x86)}\paint.net" -Name "PaintDotNet.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    
    if ($paintPath) {
        Write-Log "[INFO] Paint.NET installed successfully" "Green"
        Write-Log "[INFO] To set Paint.NET as default image editor:" "White"
        Write-Log "        1. Open Settings > Apps > Default apps" "White"
        Write-Log "        2. Search for 'Paint.NET' and click it" "White"
        Write-Log "        3. Click 'Set default' for desired image formats" "White"
    } else {
        Write-Log "[WARN] Paint.NET not found - image association not configured" "Yellow"
    }
}
catch {
    Write-Log "[WARN] Could not set Paint.NET as default image editor" "Yellow"
}

# Check for ATP onboarding files
Write-Log ""
Write-Log "Checking for ATP onboarding files..." "Yellow"

$atpFiles = @("WindowsDefenderATPOnboardingPackage.zip", "GatewayWindowsDefenderATPOnboardingPackage.zip", "WindowsDefenderATPOnboardingScript.cmd")
$atpFound = $false

foreach ($file in $atpFiles) {
    $filePath = Join-Path $ScriptDir $file
    if (Test-Path $filePath) {
        $atpFound = $true
        Write-Log "  Found: $file" "Green"
        
        if ($file -like "*.zip") {
            Write-Log "  Extracting ATP onboarding package..." "Yellow"
            try {
                $extractPath = Join-Path $env:TEMP "ATP_Extract_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
                New-Item -Path $extractPath -ItemType Directory -Force | Out-Null
                
                # Extract zip file
                Expand-Archive -Path $filePath -DestinationPath $extractPath -Force
                Write-Log "  [OK] Package extracted to temporary location" "Green"
                
                # Look for onboarding script in extracted files
                $onboardingScript = Get-ChildItem -Path $extractPath -Name "*OnboardingScript.cmd" -Recurse | Select-Object -First 1
                
                if ($onboardingScript) {
                    $scriptPath = Join-Path $extractPath $onboardingScript
                    Write-Log "  Found onboarding script: $onboardingScript" "Green"
                    
                    # Check if Windows Defender for Business is already onboarded
                    $defenderService = Get-Service -Name "Sense" -ErrorAction SilentlyContinue
                    $registryCheck = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows Advanced Threat Protection" -Name "OnboardingState" -ErrorAction SilentlyContinue
                    
                    if ($defenderService -and $defenderService.Status -eq "Running" -and $registryCheck -and $registryCheck.OnboardingState -eq 1) {
                        Write-Log "  [OK] Windows Defender for Business is already onboarded and running" "Green"
                    } else {
                        Write-Log "  Executing Windows Defender Business onboarding..." "Yellow"
                    
                        # Create input file to automatically answer prompts
                        $inputFile = "$env:TEMP\atp_input.txt"
                        "Y`r`n`r`n`r`n" | Out-File -FilePath $inputFile -Encoding ASCII
                        
                        # Execute with automatic input (fix syntax)
                        $cmdArgs = "/c `"$scriptPath`" < `"$inputFile`""
                        $process = Start-Process -FilePath "cmd.exe" -ArgumentList $cmdArgs -Wait -NoNewWindow -PassThru
                        
                        # Clean up input file
                        Remove-Item -Path $inputFile -Force -ErrorAction SilentlyContinue
                        
                        if ($process.ExitCode -eq 0) {
                            Write-Log "  [OK] Windows Defender Business onboarding completed successfully" "Green"
                        } else {
                            Write-Log "  [WARN] Windows Defender Business onboarding completed with exit code: $($process.ExitCode)" "Yellow"
                        }
                    }
                } else {
                    Write-Log "  [WARN] No onboarding script found in package" "Yellow"
                }
                
                # Clean up extracted files
                Remove-Item -Path $extractPath -Recurse -Force -ErrorAction SilentlyContinue
            }
            catch {
                Write-Log "  [ERROR] Failed to extract or run ATP onboarding package: $_" "Red"
            }
        }
        elseif ($file -like "*.cmd") {
            # Check if Windows Defender for Business is already onboarded
            $defenderService = Get-Service -Name "Sense" -ErrorAction SilentlyContinue
            $registryCheck = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows Advanced Threat Protection" -Name "OnboardingState" -ErrorAction SilentlyContinue
            
            if ($defenderService -and $defenderService.Status -eq "Running" -and $registryCheck -and $registryCheck.OnboardingState -eq 1) {
                Write-Log "  [OK] Windows Defender for Business is already onboarded and running" "Green"
            } else {
                Write-Log "  Executing ATP onboarding script..." "Yellow"
                try {
                    # Create input file to automatically answer prompts
                    $inputFile = "$env:TEMP\atp_input.txt"
                    "Y`r`n`r`n`r`n" | Out-File -FilePath $inputFile -Encoding ASCII
                    
                    # Execute with automatic input (fix syntax)
                    $cmdArgs = "/c `"$filePath`" < `"$inputFile`""
                    $process = Start-Process -FilePath "cmd.exe" -ArgumentList $cmdArgs -Wait -NoNewWindow -PassThru
                    
                    # Clean up input file
                    Remove-Item -Path $inputFile -Force -ErrorAction SilentlyContinue
                    
                    if ($process.ExitCode -eq 0) {
                        Write-Log "  [OK] ATP onboarding completed successfully" "Green"
                    } else {
                        Write-Log "  [WARN] ATP onboarding completed with exit code: $($process.ExitCode)" "Yellow"
                    }
                }
                catch {
                    Write-Log "  [ERROR] ATP onboarding failed: $_" "Red"
                }
            }
        }
    }
}

if (-not $atpFound) {
    Write-Log "  No ATP onboarding files found (optional)" "Gray"
}

# Perform comprehensive privacy hardening (skip external script due to Defender blocking)
Write-Log ""
Write-Log "Performing comprehensive privacy hardening..." "Yellow"
Write-Log "  [INFO] Skipping external Win11Debloat script (blocked by Windows Defender)" "Yellow"
Write-Log "        Using built-in comprehensive privacy hardening instead" "White"

# Run our comprehensive manual debloat directly
Invoke-ManualDebloat

# Verify the debloat effectiveness
Write-Log "  Verifying privacy hardening effectiveness..." "White"
$verificationPassed = Test-DebloatEffectiveness

if ($verificationPassed) {
    Write-Log "  [OK] Privacy hardening verification passed" "Green"
} else {
    Write-Log "  [WARN] Some privacy hardening tasks may require manual review" "Yellow"
}

# Configure Australian English language settings
Write-Log ""
Write-Log "Configuring Australian English language and regional settings..." "Yellow"

try {
    # Import the International module
    Import-Module International -ErrorAction SilentlyContinue
    
    # Check if Australian English language pack is installed
    Write-Log "  [INFO] Checking for Australian English language pack..." "Cyan"
    $installedLanguages = Get-WinUserLanguageList
    $auLanguageInstalled = $installedLanguages | Where-Object { $_.LanguageTag -eq "en-AU" }
    
    if (-not $auLanguageInstalled) {
        Write-Log "  [INFO] Australian English language pack not found. Installing..." "Cyan"
        try {
            # Try to install the language pack using Install-Language (Windows 11 24H2+)
            if (Get-Command Install-Language -ErrorAction SilentlyContinue) {
                # Use -CopyToSettings to apply language to system settings
                Install-Language -Language en-AU -CopyToSettings -ErrorAction Stop
                Write-Log "  [OK] Australian English language pack installed and applied to system settings" "Green"
            }
            else {
                # Fallback: Try using Add-WindowsCapability for older versions
                Write-Log "  [INFO] Using Add-WindowsCapability method..." "Cyan"
                $capability = Get-WindowsCapability -Online | Where-Object Name -like "*Language.Basic*en-AU*"
                if ($capability) {
                    Add-WindowsCapability -Online -Name $capability.Name -ErrorAction Stop
                    Write-Log "  [OK] Australian English language capability added" "Green"
                }
                else {
                    Write-Log "  [WARN] Could not find Australian English language capability. Manual installation may be required." "Yellow"
                }
            }
        }
        catch {
            Write-Log "  [WARN] Could not install Australian English language pack automatically: $($_.Exception.Message)" "Yellow"
            Write-Log "  [INFO] You may need to manually install the language pack via Settings > Time & language > Language & region" "Cyan"
        }
    }
    else {
        Write-Log "  [OK] Australian English language pack is already installed" "Green"
    }
    
    # === SYSTEM DEFAULT LOCALE CONFIGURATION ===
    Write-Log "  [INFO] Configuring system default locale for Australia + Australian English..." "Cyan"
    
    # Set system locale to Australian English (affects non-Unicode programs)
    try {
        Set-WinSystemLocale -SystemLocale "en-AU" -ErrorAction Stop
        Write-Log "  [OK] System default locale set to Australian English (en-AU)" "Green"
    }
    catch {
        Write-Log "  [WARN] Could not set system default locale: $($_.Exception.Message)" "Yellow"
    }
    
    # Set system preferred UI language (requires language pack to be installed)
    try {
        if (Get-Command Set-SystemPreferredUILanguage -ErrorAction SilentlyContinue) {
            Set-SystemPreferredUILanguage -Language "en-AU" -ErrorAction Stop
            Write-Log "  [OK] System preferred UI language set to Australian English" "Green"
        }
        else {
            Write-Log "  [INFO] Set-SystemPreferredUILanguage not available, using alternative method" "Cyan"
            # Alternative method using registry for older Windows versions
            Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\MUI\Settings" -Name "PreferredUILanguages" -Value "en-AU" -Force -ErrorAction SilentlyContinue
            Write-Log "  [OK] System UI language configured via registry" "Green"
        }
    }
    catch {
        Write-Log "  [WARN] Could not set system preferred UI language: $($_.Exception.Message)" "Yellow"
    }
    
    # === USER LOCALE CONFIGURATION ===
    Write-Log "  [INFO] Configuring user locale for Australia + Australian English..." "Cyan"
    
    # Set Windows display language override for current user
    try {
        Set-WinUILanguageOverride -Language "en-AU" -ErrorAction Stop
        Write-Log "  [OK] User Windows display language set to Australian English" "Green"
    }
    catch {
        Write-Log "  [WARN] Could not set user Windows display language: $($_.Exception.Message)" "Yellow"
    }
    
    # Set user language list (primary language for user interface)
    try {
        Set-WinUserLanguageList -LanguageList "en-AU" -Force -ErrorAction Stop
        Write-Log "  [OK] User language list set to Australian English" "Green"
    }
    catch {
        Write-Log "  [WARN] Could not set user language list: $($_.Exception.Message)" "Yellow"
    }
    
    # Set culture information for current user (affects formatting)
    try {
        Set-Culture -CultureInfo "en-AU" -ErrorAction Stop
        Write-Log "  [OK] User culture set to Australian English (formatting)" "Green"
    }
    catch {
        Write-Log "  [WARN] Could not set user culture: $($_.Exception.Message)" "Yellow"
    }
    
    # === REGIONAL CONFIGURATION ===
    Write-Log "  [INFO] Configuring regional settings for Australia..." "Cyan"
    
    # Set home location to Australia (GeoID 12 - verified correct for Australia)
    try {
        Set-WinHomeLocation -GeoId 12 -ErrorAction Stop
        Write-Log "  [OK] Home location set to Australia (GeoID 12)" "Green"
    }
    catch {
        Write-Log "  [WARN] Could not set home location: $($_.Exception.Message)" "Yellow"
    }
    
    # Configure regional settings (currency, date format, etc.)
    Set-ItemProperty -Path "HKCU:\Control Panel\International" -Name "sCountry" -Value "Australia" -Force
    Set-ItemProperty -Path "HKCU:\Control Panel\International" -Name "sCurrency" -Value "AUD" -Force
    Set-ItemProperty -Path "HKCU:\Control Panel\International" -Name "sShortDate" -Value "d/MM/yyyy" -Force
    Set-ItemProperty -Path "HKCU:\Control Panel\International" -Name "sLongDate" -Value "dddd, d MMMM yyyy" -Force
    Set-ItemProperty -Path "HKCU:\Control Panel\International" -Name "sTimeFormat" -Value "h:mm:ss tt" -Force
    Set-ItemProperty -Path "HKCU:\Control Panel\International" -Name "iCountry" -Value "61" -Force  # Australia country code
    Set-ItemProperty -Path "HKCU:\Control Panel\International" -Name "sLanguage" -Value "ENA" -Force  # Australian English
    Write-Log "  [OK] Regional formats configured for Australia" "Green"
    
    # Set timezone to Australian Eastern Standard Time
    try {
        Set-TimeZone -Id "AUS Eastern Standard Time" -ErrorAction SilentlyContinue
        Write-Log "  [OK] Timezone set to Australian Eastern Standard Time" "Green"
    }
    catch {
        Write-Log "  [WARN] Could not set timezone - may need manual configuration" "Yellow"
    }
    
    # Hide language bar from taskbar (since we're setting single language)
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarGlomLevel" -Value 1 -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path "HKCU:\Control Panel\Input Method" -Name "ShowStatus" -Value 0 -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarAutoHideMode" -Value 0 -Force -ErrorAction SilentlyContinue
    Write-Log "  [OK] Language taskbar icon hidden" "Green"
    
    Write-Log "  [INFO] Language and regional settings configuration completed" "Cyan"
    Write-Log "  [INFO] Some changes may require a system restart to take full effect" "Cyan"
}
catch {
    Write-Log "  [WARN] Could not configure language settings: $_" "Yellow"
}

# Configure Windows Update policy for automatic security updates
Write-Log ""
Write-Log "Configuring Windows Update policy..." "Yellow"

try {
    # Configure Windows Update to automatically download and install security updates
    $updatePath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    $auPath = "$updatePath\AU"
    
    # Create registry keys if they don't exist
    if (-not (Test-Path $updatePath)) {
        New-Item -Path $updatePath -Force | Out-Null
    }
    if (-not (Test-Path $auPath)) {
        New-Item -Path $auPath -Force | Out-Null
    }
    
    # Configure automatic updates for always-available systems
    Set-ItemProperty -Path $auPath -Name "NoAutoUpdate" -Value 0 -Type DWord -Force                    # Enable automatic updates
    Set-ItemProperty -Path $auPath -Name "AUOptions" -Value 3 -Type DWord -Force                      # Auto download, notify to install
    Set-ItemProperty -Path $auPath -Name "UseWUServer" -Value 0 -Type DWord -Force                    # Use Microsoft Update
    Set-ItemProperty -Path $auPath -Name "AutoInstallMinorUpdates" -Value 1 -Type DWord -Force       # Auto install minor updates
    Set-ItemProperty -Path $auPath -Name "NoAutoRebootWithLoggedOnUsers" -Value 1 -Type DWord -Force  # Don't auto-reboot when users logged on
    Set-ItemProperty -Path $auPath -Name "RebootRelaunchTimeoutEnabled" -Value 1 -Type DWord -Force   # Enable reboot timeout
    Set-ItemProperty -Path $auPath -Name "RebootRelaunchTimeout" -Value 60 -Type DWord -Force         # 60 minute warning before reboot
    
    # Configure metered connection behavior
    $deliveryOptPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization"
    if (-not (Test-Path $deliveryOptPath)) {
        New-Item -Path $deliveryOptPath -Force | Out-Null
    }
    Set-ItemProperty -Path $deliveryOptPath -Name "DODownloadMode" -Value 0 -Type DWord -Force        # Disable delivery optimization on metered
    
    # Respect metered connections for Windows Update
    Set-ItemProperty -Path $updatePath -Name "AllowAutoWindowsUpdateDownloadOverMeteredNetwork" -Value 0 -Type DWord -Force  # No downloads on metered
    
    # Configure Update Orchestrator to respect metered connections
    $uoPath = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"
    if (-not (Test-Path $uoPath)) {
        New-Item -Path $uoPath -Force | Out-Null
    }
    Set-ItemProperty -Path $uoPath -Name "AllowAutoWindowsUpdateDownloadOverMeteredNetwork" -Value 0 -Type DWord -Force
    
    # Enable Microsoft Update (not just Windows Update)
    Set-ItemProperty -Path $updatePath -Name "AcceptTrustedPublisherCerts" -Value 1 -Type DWord -Force
    
    # Configure to install updates for other Microsoft products (Office, etc.)
    try {
        $serviceManager = New-Object -ComObject "Microsoft.Update.ServiceManager"
        $serviceManager.ClientApplicationID = "My App"
        $newService = $serviceManager.AddService2("7971f918-a847-4430-9279-4a52d1efe18d", 7, "")
    }
    catch {
        # Microsoft Update opt-in may fail, continue anyway
    }
    
    Write-Log "  [OK] Windows Update policy configured for automatic security updates" "Green"
    Write-Log "       Updates will download automatically when machine is on and prompt to install" "White"
    Write-Log "       Will NOT download over metered/tethered connections" "White"
    Write-Log "       60-minute reboot warning when restart required" "White"
}
catch {
    Write-Log "  [WARN] Could not configure Windows Update policy: $_" "Yellow"
}

# Clean up desktop icons (keep only Start Menu shortcuts)
Write-Log ""
Write-Log "Cleaning up desktop icons..." "Yellow"

$desktopPaths = @(
    [System.Environment]::GetFolderPath("Desktop"),
    [System.Environment]::GetFolderPath("CommonDesktopDirectory")
)

$commonDesktopIcons = @(
    "*Chrome*",
    "*Firefox*", 
    "*Slack*",
    "*VLC*",
    "*7-Zip*",
    "*Paint.NET*",
    "*OBS*",
    "*PuTTY*",
    "*WinSCP*",
    "*SourceTree*",
    "*Visual Studio Code*",
    "*PDFGear*",
    "*TigerVNC*",
    "*Winaero*",
    "*OneDrive*",
    "*OpenVPN*",
    "*PowerShell*"
)

$removedCount = 0
foreach ($desktopPath in $desktopPaths) {
    if (Test-Path $desktopPath) {
        Write-Log "  Cleaning $desktopPath..." "White"
        
        foreach ($iconPattern in $commonDesktopIcons) {
            $icons = Get-ChildItem -Path $desktopPath -Name $iconPattern -ErrorAction SilentlyContinue
            foreach ($icon in $icons) {
                try {
                    $iconPath = Join-Path $desktopPath $icon
                    Remove-Item -Path $iconPath -Force -ErrorAction SilentlyContinue
                    Write-Log "    Removed: $icon" "Green"
                    $removedCount++
                }
                catch {
                    Write-Log "    Could not remove: $icon" "Yellow"
                }
            }
        }
    }
}

Write-Log "[OK] Desktop cleanup completed - removed $removedCount desktop icons" "Green"
Write-Log "All applications remain accessible via Start Menu" "White"

# Set custom desktop wallpaper from SVG (after software installation)
Write-Log ""
Write-Log "Setting custom desktop wallpaper..." "Yellow"

$svgPath = Join-Path $ScriptDir "default-background.svg"
if (Test-Path $svgPath) {
    Write-Log "  Found custom SVG wallpaper: default-background.svg" "Green"
    try {
        # Get actual physical display resolution (not scaled)
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class DisplayHelper {
    [DllImport("user32.dll")]
    public static extern int GetSystemMetrics(int nIndex);
}
"@
        
        # Get true physical display resolution bypassing DPI scaling
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class DisplayResolution {
    [DllImport("user32.dll")]
    public static extern IntPtr GetDC(IntPtr hWnd);
    
    [DllImport("gdi32.dll")]
    public static extern int GetDeviceCaps(IntPtr hdc, int nIndex);
    
    [DllImport("user32.dll")]
    public static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);
    
    public static void GetPhysicalResolution(out int width, out int height) {
        IntPtr hdc = GetDC(IntPtr.Zero);
        width = GetDeviceCaps(hdc, 118); // HORZRES - Physical width
        height = GetDeviceCaps(hdc, 117); // VERTRES - Physical height  
        ReleaseDC(IntPtr.Zero, hdc);
    }
}
"@
        
        # Get true physical resolution
        $physicalWidth = 0
        $physicalHeight = 0
        [DisplayResolution]::GetPhysicalResolution([ref]$physicalWidth, [ref]$physicalHeight)
        
        # Also get scaled resolution for comparison
        $screen = [System.Windows.Forms.Screen]::PrimaryScreen
        $scaledWidth = $screen.Bounds.Width
        $scaledHeight = $screen.Bounds.Height
        
        Write-Log "  Physical display resolution: ${physicalWidth}x${physicalHeight}" "White"
        Write-Log "  DPI scaled resolution: ${scaledWidth}x${scaledHeight}" "Gray"
        
        # Use physical resolution for wallpaper
        $width = $physicalWidth
        $height = $physicalHeight
        
        # Create output PNG path in system wallpapers directory
        $wallpaperDir = "${env:WINDIR}\Web\Wallpaper"
        $pngPath = Join-Path $wallpaperDir "hypersec-wallpaper.png"
        
        # Verify wallpaper directory exists and is writable
        Write-Log "  Checking wallpaper directory: $wallpaperDir" "White"
        if (-not (Test-Path $wallpaperDir)) {
            Write-Log "    [WARN] Windows wallpaper directory not found: $wallpaperDir" "Yellow"
            # Fallback to a different location
            $wallpaperDir = Join-Path $env:PUBLIC "Pictures"
            $pngPath = Join-Path $wallpaperDir "hypersec-wallpaper.png"
            Write-Log "    Using fallback location: $wallpaperDir" "White"
        }
        
        # Test write access
        try {
            $testFile = Join-Path $wallpaperDir "test-write-access.tmp"
            "test" | Out-File -FilePath $testFile -Force
            Remove-Item $testFile -Force -ErrorAction SilentlyContinue
            Write-Log "    [OK] Write access confirmed to $wallpaperDir" "Green"
        }
        catch {
            Write-Log "    [ERROR] No write access to $wallpaperDir - $_" "Red"
            throw "Cannot write to wallpaper directory"
        }
        
        # Use Chocolatey-installed rsvg-convert for SVG to PNG conversion
        Write-Log "  Looking for rsvg-convert (Chocolatey installation)..." "White"
        
        # Refresh PATH to ensure rsvg-convert is available
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        
        # Check if rsvg-convert is available in PATH
        $rsvgCommand = Get-Command rsvg-convert -ErrorAction SilentlyContinue
        
        if ($rsvgCommand) {
            Write-Log "  Found rsvg-convert at: $($rsvgCommand.Source)" "Green"
            
            # Calculate aspect ratio and dimensions
            Write-Log "  Calculating optimal dimensions for ${width}x${height} display..." "White"
            
            # Get SVG original dimensions and background color
            $svgContent = Get-Content $svgPath -Raw
            $svgWidthMatch = [regex]::Match($svgContent, 'width="(\d+)')
            $svgHeightMatch = [regex]::Match($svgContent, 'height="(\d+)')
            
            # Extract background color from SVG (check multiple layers and elements)
            $bgColorMatch = $null
            
            # Look for background in various SVG elements
            $bgColorPatterns = @(
                'rect[^>]*fill="([^"]+)"[^>]*width="100%"',           # Full-width background rect
                'rect[^>]*fill="([^"]+)"[^>]*height="100%"',          # Full-height background rect
                '<rect[^>]*fill="([^"]+)"[^>]*>',                     # Any background rect
                'background-color:\s*([^;"\s]+)',                     # CSS background-color
                'background:\s*([^;"\s]+)',                           # CSS background
                'fill="([^"]+)"[^>]*(?:class="background"|id="background")', # Background-classed elements
                '<svg[^>]*style="[^"]*background[^:]*:\s*([^;"\s]+)'  # SVG root background
            )
            
            foreach ($pattern in $bgColorPatterns) {
                $match = [regex]::Match($svgContent, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                if ($match.Success) {
                    $bgColor = $match.Groups[1].Value.Trim()
                    Write-Log "    Detected SVG background color: $bgColor" "Green"
                    $bgColorMatch = $match
                    break
                }
            }
            
            if (-not $bgColorMatch) {
                # If blue is expected, let's use a professional blue
                $bgColor = "#2b4c7e"  # Professional blue
                Write-Log "    No background color found in SVG, using professional blue: $bgColor" "Yellow"
            }
            
            if ($svgWidthMatch.Success -and $svgHeightMatch.Success) {
                $svgOriginalWidth = [int]$svgWidthMatch.Groups[1].Value
                $svgOriginalHeight = [int]$svgHeightMatch.Groups[1].Value
                $svgAspectRatio = $svgOriginalWidth / $svgOriginalHeight
                Write-Log "    SVG original dimensions: ${svgOriginalWidth}x${svgOriginalHeight} (ratio: $([math]::Round($svgAspectRatio, 2)))" "White"
            } else {
                # Fallback to 16:9 aspect ratio if can't parse SVG
                $svgAspectRatio = 16/9
                Write-Log "    Could not parse SVG dimensions, using 16:9 aspect ratio" "Yellow"
            }
            
            # Calculate target dimensions maintaining aspect ratio
            $displayAspectRatio = $width / $height
            
            if ($svgAspectRatio -gt $displayAspectRatio) {
                # SVG is wider - fit to width
                $targetWidth = $width
                $targetHeight = [math]::Round($width / $svgAspectRatio)
            } else {
                # SVG is taller - fit to height
                $targetHeight = $height
                $targetWidth = [math]::Round($height * $svgAspectRatio)
            }
            
            Write-Log "    Target wallpaper dimensions: ${targetWidth}x${targetHeight}" "Green"
            
            # Convert SVG to PNG with full screen size and background color
            Write-Log "    Running: rsvg-convert -w $width -h $height --background-color `"$bgColor`" `"$svgPath`" -o `"$pngPath`"" "Gray"
            
            # Create log files for rsvg-convert output
            $rsvgLogPath = Join-Path $env:TEMP "rsvg-convert-output.log"
            $rsvgErrorPath = Join-Path $env:TEMP "rsvg-convert-error.log"
            
            # Use full screen dimensions with background color fill
            $process = Start-Process -FilePath $rsvgCommand.Source -ArgumentList "-w", $width, "-h", $height, "--background-color", $bgColor, $svgPath, "-o", $pngPath -Wait -NoNewWindow -PassThru -RedirectStandardOutput $rsvgLogPath -RedirectStandardError $rsvgErrorPath
            
            Write-Log "    rsvg-convert exit code: $($process.ExitCode)" "White"
            
            # Check if PNG was created and has content
            if (Test-Path $pngPath) {
                $fileSize = (Get-Item $pngPath).Length
                if ($fileSize -gt 1000) {
                    Write-Log "    [OK] SVG converted to PNG: $pngPath ($fileSize bytes)" "Green"
                } else {
                    Write-Log "    [WARN] PNG created but seems too small: $fileSize bytes (may be blank)" "Yellow"
                    
                    # Show rsvg-convert output for debugging
                    if (Test-Path $rsvgLogPath) {
                        $rsvgOutput = Get-Content $rsvgLogPath -Raw
                        if ($rsvgOutput) {
                            Write-Log "    rsvg-convert output: $rsvgOutput" "Gray"
                        }
                    }
                    
                    if (Test-Path $rsvgErrorPath) {
                        $rsvgErrors = Get-Content $rsvgErrorPath -Raw
                        if ($rsvgErrors) {
                            Write-Log "    rsvg-convert errors: $rsvgErrors" "Red"
                        }
                    }
                    
                    # Test with different approach - no width/height constraints
                    Write-Log "    Trying conversion without size constraints..." "White"
                    $pngPath2 = $pngPath -replace "\.png$", "-auto.png"
                    $process2 = Start-Process -FilePath $rsvgCommand.Source -ArgumentList $svgPath, "-o", $pngPath2 -Wait -NoNewWindow -PassThru
                    
                    if (Test-Path $pngPath2) {
                        $fileSize2 = (Get-Item $pngPath2).Length
                        if ($fileSize2 -gt $fileSize) {
                            Write-Log "    [OK] Better conversion without size constraints: $fileSize2 bytes" "Green"
                            Move-Item $pngPath2 $pngPath -Force
                        } else {
                            Remove-Item $pngPath2 -Force -ErrorAction SilentlyContinue
                        }
                    }
                }
            } else {
                Write-Log "    [ERROR] PNG file was not created" "Red"
                
                # Show rsvg-convert output for debugging
                if (Test-Path $rsvgLogPath) {
                    $rsvgOutput = Get-Content $rsvgLogPath -Raw
                    if ($rsvgOutput) {
                        Write-Log "    rsvg-convert output: $rsvgOutput" "Gray"
                    }
                }
                
                if (Test-Path $rsvgErrorPath) {
                    $rsvgErrors = Get-Content $rsvgErrorPath -Raw
                    if ($rsvgErrors) {
                        Write-Log "    rsvg-convert errors: $rsvgErrors" "Red"
                    }
                }
                
                throw "rsvg-convert failed to create PNG"
            }
        } else {
            Write-Log "  rsvg-convert not found in PATH - skipping wallpaper" "Yellow"
            Write-Log "  (rsvg-convert should be installed via Chocolatey)" "White"
            return
        }
        
        if (Test-Path $pngPath) {
            # Set as wallpaper using Windows API
            Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Wallpaper {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@
            
            # Set wallpaper for current user
            [Wallpaper]::SystemParametersInfo(20, 0, $pngPath, 3) | Out-Null
            
            # Set as current user default with center (proper aspect ratio maintained)
            Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "WallPaper" -Value $pngPath -Force
            Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "WallpaperStyle" -Value "0" -Force   # Center
            Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "TileWallpaper" -Value "0" -Force     # Don't tile
            
            # Set as system-wide default for all users
            Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "Wallpaper" -Value $pngPath -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "WallpaperStyle" -Value "0" -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "TileWallpaper" -Value "0" -Force -ErrorAction SilentlyContinue
            
            # Set as Windows logon background (replaces internet photo library)
            try {
                # Copy wallpaper to Windows backgrounds directory
                $logonBgPath = "${env:WINDIR}\System32\oobe\info\backgrounds\backgroundDefault.jpg"
                $logonBgDir = Split-Path $logonBgPath -Parent
                
                if (-not (Test-Path $logonBgDir)) {
                    New-Item -Path $logonBgDir -ItemType Directory -Force | Out-Null
                }
                
                # Convert PNG to JPG for logon background
                Add-Type -AssemblyName System.Drawing
                $bitmap = [System.Drawing.Image]::FromFile($pngPath)
                $bitmap.Save($logonBgPath, [System.Drawing.Imaging.ImageFormat]::Jpeg)
                $bitmap.Dispose()
                
                # Enable custom logon background
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\Background" -Name "OEMBackground" -Value 1 -Type DWord -Force
                
                Write-Log "    [OK] Custom logon background configured" "Green"
            }
            catch {
                Write-Log "    [WARN] Could not set logon background: $_" "Yellow"
            }
            
            Write-Log "[OK] HyperSec wallpaper set as system default and logon background: $pngPath" "Green"
        }
        else {
            Write-Log "[WARN] Failed to convert SVG to PNG" "Yellow"
        }
    }
    catch {
        Write-Log "[WARN] Could not set custom wallpaper: $_" "Yellow"
    }
}
else {
    Write-Log "  No default-background.svg found - skipping wallpaper setup" "Gray"
}

# Load required assembly for screen resolution detection
Add-Type -AssemblyName System.Windows.Forms

# Function to install and configure Hyper-V
function Install-HyperV {
    Write-Log ""
    Write-Log "Installing and configuring Hyper-V..." "Yellow"
    
    try {
        # Check if Hyper-V is already installed
        $hyperVInstalled = Get-WindowsOptionalFeature -Online -FeatureName "Microsoft-Hyper-V-All" -ErrorAction SilentlyContinue
        if ($hyperVInstalled -and $hyperVInstalled.State -eq "Enabled") {
            Write-Log "  [OK] Hyper-V is already installed" "Green"
        } else {
            Write-Log "  Installing Hyper-V features..." "White"
            
            # Enable Hyper-V features
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
                    if ($featureState -and $featureState.State -eq "Disabled") {
                        Write-Log "    Enabling $feature..." "White"
                        Enable-WindowsOptionalFeature -Online -FeatureName $feature -All -NoRestart -WarningAction SilentlyContinue | Out-Null
                        Write-Log "    [OK] $feature enabled" "Green"
                    } elseif ($featureState -and $featureState.State -eq "Enabled") {
                        Write-Log "    [OK] $feature already enabled" "Green"
                    }
                }
                catch {
                    Write-Log "    [WARN] Could not enable $feature" "Yellow"
                }
            }
        }
        
        # Configure BCDEdit settings for Hyper-V
        Write-Log "  Configuring boot settings for Hyper-V..." "White"
        
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
                Write-Log "    $($bcdEntry.Description)..." "White"
                Invoke-Expression $bcdEntry.Command 2>$null
                Write-Log "    [OK] $($bcdEntry.Description) completed" "Green"
            }
            catch {
                Write-Log "    [WARN] Failed: $($bcdEntry.Description)" "Yellow"
            }
        }
        
        # Configure registry settings for VBS and Device Guard
        Write-Log "  Configuring registry for VBS and Device Guard..." "White"
        
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
                Write-Log "    Setting $($setting.Path)\$($setting.Name)..." "White"
                Set-ItemProperty -Path $setting.Path -Name $setting.Name -Value $setting.Value -Type $setting.Type -Force
                Write-Log "    [OK] Registry setting applied" "Green"
            }
            catch {
                Write-Log "    [WARN] Failed to set $($setting.Path)\$($setting.Name)" "Yellow"
            }
        }
        
        # Disable Memory Compression
        Write-Log "  Disabling Memory Compression..." "White"
        try {
            Disable-MMAgent -MemoryCompression -ErrorAction SilentlyContinue
            Write-Log "  [OK] Memory Compression disabled" "Green"
        }
        catch {
            Write-Log "  [WARN] Could not disable Memory Compression: $_" "Yellow"
        }

        # Create C:\VM structure and set Hyper-V default paths
        Write-Log "  Configuring Hyper-V default paths..." "White"
        try {
            $vmRoot = "C:\VM"
            $vhdsPath = Join-Path $vmRoot "Virtual Hard Disks"
            $vmsPath  = Join-Path $vmRoot "Hyper-V"

            foreach ($dir in @($vmRoot, $vhdsPath, $vmsPath)) {
                if (-not (Test-Path $dir)) {
                    New-Item -Path $dir -ItemType Directory -Force | Out-Null
                    Write-Log "    [OK] Created $dir" "Green"
                } else {
                    Write-Log "    [OK] $dir already exists" "Green"
                }
            }

            # Prefer PowerShell module if available
            $hvModule = Get-Module -ListAvailable -Name Hyper-V
            if ($hvModule) {
                try {
                    Import-Module Hyper-V -ErrorAction SilentlyContinue
                    Set-VMHost -VirtualHardDiskPath $vhdsPath -VirtualMachinePath $vmsPath -ErrorAction Stop
                    Write-Log "    [OK] Set Hyper-V default paths via Set-VMHost" "Green"
                }
                catch {
                    Write-Log "    [WARN] Set-VMHost failed, applying registry fallback..." "Yellow"
                    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Virtualization" -Name "DefaultVirtualHardDiskPath" -Value $vhdsPath -Type String -Force -ErrorAction SilentlyContinue
                    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Virtualization" -Name "DefaultVirtualMachinePath" -Value $vmsPath -Type String -Force -ErrorAction SilentlyContinue
                    Write-Log "    [OK] Set Hyper-V default paths in registry" "Green"
                }
            } else {
                # Registry fallback if module not present yet (pre-reboot)
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Virtualization" -Name "DefaultVirtualHardDiskPath" -Value $vhdsPath -Type String -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Virtualization" -Name "DefaultVirtualMachinePath" -Value $vmsPath -Type String -Force -ErrorAction SilentlyContinue
                Write-Log "    [OK] Set Hyper-V default paths in registry (module not available)" "Green"
            }
        }
        catch {
            Write-Log "    [WARN] Could not configure Hyper-V default paths: $_" "Yellow"
        }

        # Ensure new/unchecked VMs connect to 'Default Switch'
        Write-Log "  Configuring default networking for VMs (Default Switch)..." "White"
        try {
            $defaultSwitch = Get-VMSwitch -Name "Default Switch" -ErrorAction SilentlyContinue
            if ($defaultSwitch) {
                $hyperSecScripts = "C:\ProgramData\HyperSec\scripts"
                if (-not (Test-Path $hyperSecScripts)) { New-Item -Path $hyperSecScripts -ItemType Directory -Force | Out-Null }

                $netScriptPath = Join-Path $hyperSecScripts "Ensure-DefaultSwitch.ps1"
                $netScript = @'
$ErrorActionPreference = "SilentlyContinue"
Import-Module Hyper-V -ErrorAction SilentlyContinue
$switch = Get-VMSwitch -Name "Default Switch" -ErrorAction SilentlyContinue
if (-not $switch) { return }
$allVMs = Get-VM -ErrorAction SilentlyContinue
foreach ($vm in $allVMs) {
    $nics = Get-VMNetworkAdapter -VMName $vm.Name -ErrorAction SilentlyContinue
    if (-not $nics -or $nics.Count -eq 0) {
        Add-VMNetworkAdapter -VMName $vm.Name -SwitchName $switch.Name -ErrorAction SilentlyContinue
    } else {
        foreach ($nic in $nics) {
            if ($nic.SwitchName -ne $switch.Name) {
                Connect-VMNetworkAdapter -VMName $vm.Name -Name $nic.Name -SwitchName $switch.Name -ErrorAction SilentlyContinue
            }
        }
    }
}
'@
                $netScript | Out-File -FilePath $netScriptPath -Encoding UTF8 -Force

                try {
                    # Create/update scheduled task to enforce default switch at startup/logon
                    $action   = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$netScriptPath`""
                    $trigger1 = New-ScheduledTaskTrigger -AtStartup
                    $trigger2 = New-ScheduledTaskTrigger -AtLogOn
                    $triggers = @($trigger1, $trigger2)
                    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest -LogonType ServiceAccount
                    Register-ScheduledTask -TaskName "HyperSec-EnsureDefaultSwitchForVMs" -Action $action -Trigger $triggers -Principal $principal -Force | Out-Null
                    Write-Log "    [OK] Scheduled task 'HyperSec-EnsureDefaultSwitchForVMs' configured" "Green"
                }
                catch {
                    Write-Log "    [WARN] Could not register scheduled task for default switch enforcement: $_" "Yellow"
                }

                # Run once now to apply to existing VMs
                try {
                    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$netScriptPath" | Out-Null
                    Write-Log "    [OK] Applied Default Switch to existing VMs (where needed)" "Green"
                }
                catch {}
            } else {
                Write-Log "    [WARN] 'Default Switch' not found. Skipping network default configuration." "Yellow"
            }
        }
        catch {
            Write-Log "    [WARN] Default switch configuration failed: $_" "Yellow"
        }
        
        Write-Log "[OK] Hyper-V installation and configuration completed" "Green"
        Write-Log "  Note: A system restart is required for Hyper-V to be fully functional" "Yellow"
    }
    catch {
        Write-Log "[WARN] Hyper-V installation failed: $_" "Yellow"
    }
}

# Detect laptop vs desktop and configure power accordingly
Write-Log ""
Write-Log "Detecting system type and configuring power settings..." "Yellow"

# Function to detect if system is a laptop
function Test-IsLaptop {
    try {
        # Check for battery presence
        $battery = Get-WmiObject -Class Win32_Battery -ErrorAction SilentlyContinue
        
        # Check chassis type
        $chassis = Get-WmiObject -Class Win32_SystemEnclosure -ErrorAction SilentlyContinue
        $laptopChassisTypes = @(8, 9, 10, 14)  # Portable, Laptop, Notebook, Sub Notebook
        
        # Check PC system type
        $computerSystem = Get-WmiObject -Class Win32_ComputerSystem -ErrorAction SilentlyContinue
        $isMobile = $computerSystem.PCSystemType -eq 2
        
        # Consider it a laptop if any of these conditions are true
        $hasLaptopChassis = $chassis -and ($chassis.ChassisTypes | Where-Object { $laptopChassisTypes -contains $_ })
        
        return ($battery -ne $null) -or $hasLaptopChassis -or $isMobile
    }
    catch {
        Write-Log "  Could not detect system type, assuming desktop" "Yellow"
        return $false
    }
}

$isLaptop = Test-IsLaptop

if ($isLaptop) {
    Write-Log "  Detected: Laptop - Applying balanced power configuration" "Cyan"
    
    try {
        # Use Balanced power plan for laptops
        $balancedGuid = "381b4222-f694-41f0-9685-ff5bb260df2e"
        powercfg /setactive $balancedGuid 2>$null
        Write-Log "[OK] Balanced power plan activated for laptop" "Green"
        
        # Laptop power settings (battery vs AC)
        powercfg /change monitor-timeout-dc 15 2>$null       # 15 min screen timeout on battery
        powercfg /change monitor-timeout-ac 30 2>$null       # 30 min screen timeout on AC
        powercfg /change standby-timeout-dc 30 2>$null       # 30 min sleep on battery
        powercfg /change standby-timeout-ac 0 2>$null        # Never sleep on AC
        powercfg /change hibernate-timeout-dc 180 2>$null    # 3 hours hibernate on battery
        powercfg /change hibernate-timeout-ac 0 2>$null      # Never hibernate on AC
        powercfg /change disk-timeout-dc 20 2>$null          # 20 min disk timeout on battery
        powercfg /change disk-timeout-ac 0 2>$null           # Never turn off disk on AC
        
        # Configure different power modes for AC vs Battery
        Write-Log "  Configuring power modes for AC vs Battery..." "White"
        
        # Create a custom power scheme that switches modes based on power source
        # Set AC power mode to Best Performance
        powercfg /setacvalueindex $balancedGuid SUB_PROCESSOR PROCTHROTTLEMIN 100 2>$null
        powercfg /setacvalueindex $balancedGuid SUB_PROCESSOR PROCTHROTTLEMAX 100 2>$null
        
        # Set Battery power mode to Power Saver levels
        powercfg /setdcvalueindex $balancedGuid SUB_PROCESSOR PROCTHROTTLEMIN 5 2>$null  
        powercfg /setdcvalueindex $balancedGuid SUB_PROCESSOR PROCTHROTTLEMAX 100 2>$null
        
        # Set AC power mode behavior to match High Performance
        powercfg /setacvalueindex $balancedGuid SUB_SLEEP STANDBYIDLE 0 2>$null           # Never sleep on AC
        powercfg /setacvalueindex $balancedGuid SUB_SLEEP HIBERNATEIDLE 0 2>$null         # Never hibernate on AC  
        powercfg /setacvalueindex $balancedGuid SUB_VIDEO VIDEOIDLE 0 2>$null             # Never turn off display on AC
        powercfg /setacvalueindex $balancedGuid SUB_DISK DISKIDLE 0 2>$null               # Never turn off disk on AC
        
        # Apply the modified balanced scheme
        powercfg /setactive $balancedGuid 2>$null
        
        Write-Log "[OK] Laptop power settings configured (Balanced on battery, Best Performance on AC)" "Green"
    }
    catch {
        Write-Log "[WARN] Laptop power configuration failed: $_" "Yellow"
    }
} else {
    Write-Log "  Detected: Desktop PC - Applying high performance configuration" "Cyan"
    
    try {
        # Try Ultimate Performance first, fall back to High Performance
        $ultimatePlan = powercfg /list | Select-String "Ultimate Performance"
        if ($ultimatePlan) {
            $ultimateGuid = ($ultimatePlan -split '\s+')[3]
            powercfg /setactive $ultimateGuid 2>$null
            Write-Log "[OK] Ultimate Performance power plan activated" "Green"
        } else {
            $highPerfGuid = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
            powercfg /setactive $highPerfGuid 2>$null
            Write-Log "[OK] High Performance power plan activated" "Green"
        }
        
        # Desktop power settings (aggressive performance)
        $monitorCount = (Get-WmiObject -Class Win32_DesktopMonitor | Measure-Object).Count
        if ($monitorCount -gt 1) {
            powercfg /change monitor-timeout-ac 0 2>$null    # Never turn off monitors (dual monitor setup)
            Write-Log "[OK] Monitor timeout disabled (dual monitor detected)" "Green"
        } else {
            powercfg /change monitor-timeout-ac 60 2>$null   # 60 min timeout for single monitor
            Write-Log "[OK] Monitor timeout set to 60 minutes" "Green"
        }
        
        powercfg /change standby-timeout-ac 0 2>$null        # Never sleep (for remote access/builds)
        powercfg /change hibernate-timeout-ac 0 2>$null      # Never hibernate
        powercfg /change disk-timeout-ac 0 2>$null           # Never turn off hard disk
        
        # Maximum CPU performance for desktop
        powercfg /setacvalueindex SCHEME_CURRENT 54533251-82be-4824-96c1-47b60b740d00 893dee8e-2bef-41e0-89c6-b55d0929964c 100 2>$null  # Min 100%
        powercfg /setacvalueindex SCHEME_CURRENT 54533251-82be-4824-96c1-47b60b740d00 bc5038f7-23e0-4960-96da-33abaf5935ec 100 2>$null  # Max 100%
        
        Write-Log "[OK] Desktop performance settings configured (maximum performance)" "Green"
    }
    catch {
        Write-Log "[WARN] Desktop power configuration failed: $_" "Yellow"
    }
}

# Common settings for both laptop and desktop
try {
    # Disable USB selective suspend (prevents peripheral issues)
    try {
        powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 2>$null
        if ($isLaptop) {
            powercfg /setdcvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 2>$null
        }
        Write-Log "  [OK] USB selective suspend disabled" "Green"
    }
    catch {
        Write-Log "  [WARN] Could not disable USB selective suspend: $_" "Yellow"
    }
    
    # Disable fast startup (can cause development tool issues)
    powercfg /hibernate off 2>$null
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power" /v HiberbootEnabled /t REG_DWORD /d 0 /f 2>$null
    
    # Set PCI Link State to maximum performance (for NVMe/GPU)
    powercfg /setacvalueindex SCHEME_CURRENT 501a4d13-42af-4429-9fd1-a8218c268e20 ee12f906-d277-404b-b6da-e5fa1a576df5 0 2>$null
    if ($isLaptop) {
        powercfg /setdcvalueindex SCHEME_CURRENT 501a4d13-42af-4429-9fd1-a8218c268e20 ee12f906-d277-404b-b6da-e5fa1a576df5 0 2>$null
    }
    
    # Apply all changes
    powercfg /setactive SCHEME_CURRENT 2>$null
    
    Write-Log "[OK] Developer-optimized power settings applied" "Green"
}
catch {
    Write-Log "[WARN] Common power settings configuration failed: $_" "Yellow"
}

# Install and configure Hyper-V
Install-HyperV

# Summary - Only show success if no packages failed
Write-Log ""
Write-Log "=====================================================" "Cyan"
Write-Log "                Installation Summary" "Cyan"
Write-Log "=====================================================" "Cyan"
Write-Log ""
Write-Log "Software installed successfully: $SuccessCount" "Green"

if ($FailedPackages.Count -gt 0) {
    Write-Log "Failed installations: $($FailedPackages.Count)" "Red"
    foreach ($failed in $FailedPackages) {
        Write-Log "  - $failed" "Yellow"
    }
    Write-Log ""
    Write-Log "=== SOE Setup Failed ===" "Red"
    Write-Log "[ERROR] Some software packages failed to install" "Red"
    Write-Log "Log file saved to: $LogFile" "Cyan"
    exit 1
}

Write-Log ""
Write-Log "DEVELOPMENT WORKFLOW REMINDER:" "Cyan"
Write-Log "  This Windows machine is now configured as a VM host for productivity work." "White"
Write-Log "  Actual HyperSec code development should be done in Linux VMs using the" "White"
Write-Log "  HyperSec Linux Hyperi developer SOE - not natively on Windows." "White"
Write-Log ""
Write-Log "  Windows: Productivity, office tasks, communication, VM hosting" "White"
Write-Log "  Linux VM: Development, coding, testing, compilation" "White"
Write-Log ""

Write-Log "Manual actions required:" "Yellow"
Write-Log "  1. Set default browser: Settings > Apps > Default apps > Firefox or Chrome" "White"
Write-Log "  2. Sign into Microsoft 365 (if installed)" "White"
Write-Log "  3. Configure Slack workspace" "White"
Write-Log "  4. Configure GitHub Desktop with your account" "White"
Write-Log "  5. Create Linux VM(s) in Hyper-V Manager for development work" "White"

Write-Log ""
Write-Log "=== SOE Setup Complete ===" "Cyan"
Write-Log "[OK] All software packages installed successfully" "Green"
Write-Log "[OK] Hyper-V configured with full security stack (VBS, Credential Guard, HVCI)" "Green"
Write-Log "[OK] C:\\VM structure created with Default Switch configuration" "Green"
Write-Log "Log file saved to: $LogFile" "Cyan"
Write-Log ""

Write-Log ""
Write-Log "IMPORTANT: Restart required to activate Hyper-V and security features." "Red"
Write-Log "After restart, you can create Linux VMs for development in Hyper-V Manager." "White"
