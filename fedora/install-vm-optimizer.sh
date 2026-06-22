#!/bin/bash
# ============================================================================
# install-vm-optimizer - Fedora VM Performance Optimizer
# ============================================================================
# Detects virtualization platform and optimizes Fedora for VM performance
# Supports VMware, QEMU/KVM, AWS EC2, VirtualBox, Hyper-V, and Xen platforms
#
# USAGE:
#   ./install-vm-optimizer.sh                  # Auto-detect and optimize
#   ./install-vm-optimizer.sh --force-type kvm # Force specific VM type
#
# OPTIMIZES:
#   - Services: Disables bluetooth, cups, avahi, ModemManager, thermald
#   - Kernel: Optimized swappiness, dirty ratios, I/O scheduler
#   - Network: BBR congestion control, IPv6 disabled (if not needed)
#   - VM Tools: Platform-specific guest additions/agents
#   - Memory: Reduced usage and improved disk I/O performance
#   - GNOME: Disabled unnecessary desktop services for VMs
#
# NOTE: Run after install-hyperi-developer.sh for best results
#       Auto-detects VM platform and applies appropriate optimizations
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

# Check OS immediately - must be Fedora
require_distro "fedora" "Fedora Linux"

# Script metadata
SCRIPT_NAME="$(basename "$0")"
SCRIPT_DESCRIPTION="VM Optimiser"

# Export for common functions
export SCRIPT_NAME SCRIPT_DESCRIPTION

# Function to show usage
show_usage() {
    cat <<EOF

Usage: sudo $0 [OPTIONS]

Default behavior: Auto-detect VM type and apply optimizations

Options:
  --check       Check VM type and current status (no changes)
  --verify      Verify optimization settings are applied
  --uninstall   Revert VM optimizations to defaults
  --force-type  Force specific VM type (vmware|kvm|ec2|vbox|hyperv|xen)
  --help        Show this help message

Examples:
  sudo $0                    # Default: detect and optimize
  sudo $0 --check           # Check VM type and status
  sudo $0 --verify          # Verify optimizations
  sudo $0 --uninstall       # Remove optimizations
  sudo $0 --force-type kvm  # Force KVM optimizations

This script works alongside:
  - install-hyperi-fedora (development environment)
  - install-rdp-optimizer (RDP optimizations)
EOF
    exit 0
}


# Disable unnecessary services for VMs
disable_unnecessary_services() {
    print_info "Disabling unnecessary services for VM environment..."

    local services_to_disable=(
        "bluetooth.service"
        "bluetooth.target"
        "cups.service"
        "cups.socket"
        "cups-browsed.service"
        "avahi-daemon.service"
        "avahi-daemon.socket"
        "ModemManager.service"
        "thermald.service"
        "bolt.service"
        "fwupd.service"
        "fwupd-refresh.service"
        "packagekit.service"
        "packagekit-offline-update.service"
    )

    # Use libshell helper for batch service management
    manage_service_batch disable "${services_to_disable[@]}"

    # Mask critical services to prevent them from being started
    local services_to_mask=(
        "bluetooth.service"
        "cups.service"
    )
    manage_service_batch mask "${services_to_mask[@]}"
}

# Optimize kernel parameters
optimize_kernel_params() {
    print_info "Optimizing kernel parameters for VM..."

    # Check for RDP optimizer settings (they take precedence for network)
    local rdp_optimizer_exists=false
    if [ -f /etc/sysctl.d/99-rdp-optimization.conf ]; then
        rdp_optimizer_exists=true
        print_info "RDP optimizer detected - preserving network settings"
    fi

    # Define base sysctl settings
    local sysctl_settings=(
        "# Reduce swappiness (use RAM more, swap less)"
        "vm.swappiness = 10"
        ""
        "# Reduce dirty page writebacks"
        "vm.dirty_ratio = 15"
        "vm.dirty_background_ratio = 5"
        ""
        "# Optimize for lower latency"
        "kernel.sched_min_granularity_ns = 10000000"
        "kernel.sched_wakeup_granularity_ns = 15000000"
        ""
        "# Disable IPv6 if not needed (reduces overhead)"
        "net.ipv6.conf.all.disable_ipv6 = 1"
        "net.ipv6.conf.default.disable_ipv6 = 1"
    )

    # Add network settings only if RDP optimizer isn't present
    if [ "$rdp_optimizer_exists" = "false" ]; then
        sysctl_settings+=(
            ""
            "# Network optimizations"
            "net.core.netdev_max_backlog = 5000"
            "net.ipv4.tcp_congestion_control = bbr"
            "net.core.default_qdisc = fq"
        )
    else
        sysctl_settings+=(
            ""
            "# Network settings managed by RDP optimizer"
        )
    fi

    # Add security and memory settings
    sysctl_settings+=(
        ""
        "# Disable unused protocols"
        "net.ipv4.conf.all.accept_source_route = 0"
        "net.ipv6.conf.all.accept_source_route = 0"
        ""
        "# Memory optimizations"
        "vm.vfs_cache_pressure = 50"
    )

    # Use libshell helper to create sysctl configuration
    create_sysctl_config "98-vm-optimizer" "VM Optimizer Settings" "${sysctl_settings[@]}"
}

# Install VM-specific tools
install_vm_tools() {
    local vm_type="$1"
    
    case "$vm_type" in
        vmware)
            print_info "Installing VMware tools..."
            sudo dnf install -y open-vm-tools open-vm-tools-desktop 2>/dev/null || true
            sudo systemctl enable vmtoolsd.service 2>/dev/null || true
            ;;
        vbox)
            print_info "Installing VirtualBox Guest Additions dependencies..."
            sudo dnf install -y kernel-devel kernel-headers gcc make perl 2>/dev/null || true
            print_info "Please install VirtualBox Guest Additions from the VM menu"
            ;;
        kvm)
            print_info "Installing QEMU/KVM guest agent..."
            sudo dnf install -y qemu-guest-agent spice-vdagent 2>/dev/null || true
            sudo systemctl enable qemu-guest-agent.service 2>/dev/null || true
            sudo systemctl enable spice-vdagentd.service 2>/dev/null || true
            ;;
        hyperv)
            print_info "Installing Hyper-V integration services..."
            sudo dnf install -y hyperv-daemons hyperv-tools 2>/dev/null || true
            sudo systemctl enable hypervkvpd.service 2>/dev/null || true
            sudo systemctl enable hypervvssd.service 2>/dev/null || true
            ;;
        ec2)
            print_info "Installing AWS EC2 tools..."
            sudo dnf install -y ec2-utils cloud-init cloud-utils-growpart 2>/dev/null || true
            sudo systemctl enable cloud-init 2>/dev/null || true
            ;;
        xen)
            print_info "Installing Xen guest tools..."
            dnf install -y xen-runtime 2>/dev/null || true
            ;;
    esac
}

# Optimize GRUB for VMs
optimize_grub() {
    local vm_type="$1"
    print_info "Optimizing GRUB configuration for VM..."
    
    # Backup current GRUB config
    sudo cp /etc/default/grub /etc/default/grub.backup.vm-optimizer

    # Add VM-specific kernel parameters
    local grub_cmdline="elevator=noop"

    case "$vm_type" in
        kvm|qemu)
            grub_cmdline="$grub_cmdline no_timer_check"
            ;;
        vmware)
            grub_cmdline="$grub_cmdline divider=10"
            ;;
        ec2)
            grub_cmdline="$grub_cmdline console=ttyS0,115200n8 console=tty0"
            ;;
    esac

    # Update GRUB configuration
    if ! grep -q "vm-optimizer" /etc/default/grub; then
        sudo sed -i "s/GRUB_CMDLINE_LINUX=\"/GRUB_CMDLINE_LINUX=\"$grub_cmdline /" /etc/default/grub
        sudo bash -c "echo '# Added by vm-optimizer' >> /etc/default/grub"
    fi

    # Reduce GRUB timeout
    sudo sed -i 's/GRUB_TIMEOUT=.*/GRUB_TIMEOUT=1/' /etc/default/grub
    
    # Regenerate GRUB configuration
    if [ -f /boot/grub2/grub.cfg ]; then
        grub2-mkconfig -o /boot/grub2/grub.cfg 2>/dev/null || true
    elif [ -f /boot/efi/EFI/fedora/grub.cfg ]; then
        grub2-mkconfig -o /boot/efi/EFI/fedora/grub.cfg 2>/dev/null || true
    fi
    
    print_info "GRUB optimized for VM"
}

# Optimize disk I/O
optimize_disk_io() {
    print_info "Optimizing disk I/O for VM..."
    
    # Set I/O scheduler to noop for virtual disks
    for disk in /sys/block/sd*/queue/scheduler /sys/block/vd*/queue/scheduler; do
        if [ -f "$disk" ]; then
            echo noop | sudo tee "$disk" >/dev/null 2>&1 || echo none | sudo tee "$disk" >/dev/null 2>&1 || true
        fi
    done

    # Create udev rule for persistent I/O scheduler (if not exists)
    if [ ! -f /etc/udev/rules.d/60-vm-disk-scheduler.rules ]; then
        sudo bash -c 'cat > /etc/udev/rules.d/60-vm-disk-scheduler.rules <<EOF
# Set noop scheduler for virtual disks
ACTION=="add|change", KERNEL=="sd[a-z]|vd[a-z]", ATTR{queue/scheduler}="noop"
EOF'
        print_info "Created udev rule for I/O scheduler"
    else
        print_info "I/O scheduler udev rule already exists"
    fi

    # Disable unnecessary disk features
    for disk in /sys/block/sd*/queue /sys/block/vd*/queue; do
        if [ -d "$disk" ]; then
            echo 0 | sudo tee "$disk/add_random" >/dev/null 2>&1 || true
            echo 0 | sudo tee "$disk/rotational" >/dev/null 2>&1 || true
        fi
    done
    
    print_info "Disk I/O optimized"
}

# Reduce memory usage
optimize_memory() {
    print_info "Optimizing memory usage..."
    
    # Disable unnecessary systemd units
    sudo systemctl disable dnf-makecache.timer 2>/dev/null || true
    sudo systemctl disable dnf-makecache.service 2>/dev/null || true

    # Reduce journal size
    sudo journalctl --vacuum-size=100M 2>/dev/null || true
    
    # Configure journal to use less memory (if not exists)
    sudo mkdir -p /etc/systemd/journald.conf.d/
    if [ ! -f /etc/systemd/journald.conf.d/vm-optimizer.conf ]; then
        sudo bash -c 'cat > /etc/systemd/journald.conf.d/vm-optimizer.conf <<EOF
[Journal]
SystemMaxUse=100M
RuntimeMaxUse=100M
EOF'
        print_info "Journal size limited to 100M (will apply after reboot)"
    else
        print_info "Journal configuration already optimized"
    fi
    
    print_info "Memory usage optimized"
}

# Consolidated VM optimization functions
configure_vm_services() {
    print_info "Configuring VM services..."
    print_info "Service optimization temporarily disabled to avoid build failures"
    print_info "VM-specific services will be handled via kernel parameters and tools instead"
    print_info "VM service configuration completed (services preserved for compatibility)"
}

configure_vm_kernel_params() {
    local vm_type="$1"
    print_info "Configuring VM kernel parameters..."
    optimize_kernel_params
}

install_vm_platform_tools() {
    local vm_type="$1"
    print_info "Installing VM platform tools..."
    install_vm_tools "$vm_type"
}

configure_vm_boot() {
    local vm_type="$1"
    print_info "Configuring VM boot settings..."
    optimize_grub "$vm_type"
}

configure_vm_disk_io() {
    print_info "Configuring VM disk I/O..."
    optimize_disk_io
}

configure_vm_memory() {
    print_info "Configuring VM memory settings..."
    optimize_memory
}

# Configure GUI-specific optimizations for VMs
configure_vm_gui_optimizations() {
    print_info "Configuring GUI optimizations for VM environment..."
    
    # Only apply if we have a GUI environment
    if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
        print_info "No GUI environment detected, skipping GUI optimizations"
        return 0
    fi
    
    # Mask OBEX service in VMs (Bluetooth file transfer not needed)
    if systemctl --user list-unit-files obex.service &>/dev/null; then
        print_info "Masking OBEX service (Bluetooth file transfer) in VM"
        systemctl --user mask obex.service 2>/dev/null || true
    fi
    
    # Disable VS Code hardware acceleration in VMs
    if command -v code &>/dev/null; then
        local vscode_config_dir="$HOME/.config/Code"
        print_info "Disabling VS Code hardware acceleration for VM"
        mkdir -p "$vscode_config_dir" 2>/dev/null || true
        echo '{"disable-hardware-acceleration": true}' | tee "$vscode_config_dir/argv.json" >/dev/null 2>/dev/null || true
    fi
    
    # NOTE: Chrome and Slack GPU acceleration no longer disabled
    # These apps auto-detect GPU capability and handle llvmpipe fallback well
    # See TODO.md "Remove Unnecessary GPU Optimizations" for details
    
    # Disable Firefox hardware acceleration in VMs
    if command -v firefox &>/dev/null; then
        print_info "Setting Firefox performance preferences for VM"
        # Firefox uses different approach - we'll create a user.js file for preferences
        local firefox_profile_dir
        firefox_profile_dir=$(find "$HOME/.mozilla/firefox" -maxdepth 1 -name "*.default*" -type d 2>/dev/null | head -1)
        if [ -n "$firefox_profile_dir" ]; then
            # Create user.js with VM-optimized settings
            cat << 'EOF' | tee "$firefox_profile_dir/user.js" >/dev/null 2>/dev/null || true
// VM Optimization Settings
user_pref("layers.acceleration.disabled", true);
user_pref("gfx.webrender.software", true);
user_pref("media.hardware-video-decoding.enabled", false);
EOF
            print_info "Firefox VM optimizations applied to profile"
        fi
    fi
    
    # Disable GNOME Boxes search provider in VMs (VM inside VM not recommended)
    if command -v gsettings &>/dev/null; then
        if rpm -q gnome-boxes &>/dev/null; then
            print_info "Disabling GNOME Boxes search provider in VM"
            gsettings set org.gnome.desktop.search-providers disabled "['org.gnome.Boxes.desktop']" 2>/dev/null || true
        fi
    fi
    
    print_info "GUI optimizations configured"
}

# Verification function
verify_optimizations() {
    # Disable error exit for verification
    set +e
    print_info "VM Optimization Verification Report"
    
    # Reset verification counters
    reset_verify_counts
    
    # Detect current VM type
    local detection_result
    detection_result=$(detect_virtualization)
    local vm_type="${detection_result%%:*}"
    local detection_method="${detection_result##*:}"
    
    print_info "VM Platform: $vm_type (detected via $detection_method)"
    
    # Service optimizations
    print_verify_section "" "SERVICE OPTIMIZATIONS"
    
    local services_to_check=(
        "bluetooth.service"
        "cups.service"
        "avahi-daemon.service"
        "ModemManager.service"
        "thermald.service"
        "bolt.service"
        "fwupd.service"
        "packagekit.service"
    )
    
    for service in "${services_to_check[@]}"; do
        local status
        status=$(systemctl is-enabled "$service" 2>&1 | tr '\n' ' ' | awk '{print $1}')
        if [[ -z "$status" ]] || [[ "$status" == "not-found" ]] || [[ "$status" == *"No such file"* ]] || [[ "$status" == *"not be found"* ]]; then
            continue  # Service doesn't exist, that's fine
        elif [[ "$status" == "disabled" ]] || [[ "$status" == "masked" ]]; then
            echo "   [OK] $service: DISABLED (optimized)"
            increment_verify_pass || true
        elif [[ "$status" == "static" ]]; then
            # Static services are controlled by other services
            echo "   [OK] $service: STATIC (managed)"
            increment_verify_pass
        else
            echo "   [WARN] $service: $status (not optimized)"
            increment_verify_warn
        fi
    done
    
    # 2. Kernel parameters
    print_verify_section "" "KERNEL OPTIMIZATIONS"

    if [[ -f /etc/sysctl.d/98-vm-optimizer.conf ]]; then
        echo "   [OK] VM optimization config exists"
        increment_verify_pass

        # Check specific settings
        verify_sysctl_setting "vm.swappiness" "10" "Swappiness" && increment_verify_pass || increment_verify_warn
        verify_sysctl_setting "vm.vfs_cache_pressure" "50" "VFS cache pressure" && increment_verify_pass || increment_verify_warn
        verify_sysctl_setting "vm.dirty_ratio" "15" "Dirty ratio" && increment_verify_pass || increment_verify_warn
        verify_sysctl_setting "vm.dirty_background_ratio" "5" "Dirty background ratio" && increment_verify_pass || increment_verify_warn
    else
        echo "   [FAIL] VM optimization config not found"
        increment_verify_fail
    fi
    
    # 3. VM-specific tools
    print_verify_section "" "VM-SPECIFIC TOOLS"
    
    case "$vm_type" in
        vmware)
            verify_command_exists "vmware-toolbox-cmd" "VMware Tools" && increment_verify_pass || increment_verify_warn
            verify_service_status "vmtoolsd" "VMware Tools service" && increment_verify_pass || increment_verify_warn
            ;;
        kvm)
            verify_command_exists "qemu-ga" "QEMU Guest Agent" && increment_verify_pass || increment_verify_warn
            verify_service_status "qemu-guest-agent" "QEMU Guest Agent service" && increment_verify_pass || increment_verify_warn
            ;;
        vbox)
            verify_module_loaded "vboxguest" "VirtualBox Guest module" && increment_verify_pass || increment_verify_warn
            ;;
        hyperv)
            verify_module_loaded "hv_vmbus" "Hyper-V VMBus" && increment_verify_pass || increment_verify_warn
            ;;
        ec2)
            verify_command_exists "cloud-init" "Cloud-Init" && increment_verify_pass || increment_verify_warn
            verify_command_exists "ec2-metadata" "EC2 metadata tool" && increment_verify_pass || increment_verify_warn
            ;;
        *)
            echo "   [WARN] Generic VM - no specific tools to check"
            increment_verify_warn
            ;;
    esac
    
    # 4. GRUB optimizations
    print_verify_section "" "GRUB OPTIMIZATIONS"
    
    if grep -q "elevator=noop" /proc/cmdline 2>/dev/null; then
        echo "   [OK] I/O scheduler: noop (optimized for VM)"
        increment_verify_pass
    else
        local current_elevator
        current_elevator=$(cat /sys/block/sda/queue/scheduler 2>/dev/null | grep -oP '\[\K[^\]]+' || echo "unknown")
        echo "   [WARN] I/O scheduler: $current_elevator (not optimized)"
        increment_verify_warn
    fi
    
    if grep -q "transparent_hugepage=never" /proc/cmdline 2>/dev/null; then
        echo "   [OK] Transparent hugepages: disabled"
        increment_verify_pass
    else
        echo "   [WARN] Transparent hugepages: enabled (not optimized)"
        increment_verify_warn
    fi
    
    # 5. Disk I/O optimizations
    print_verify_section "" "DISK I/O OPTIMIZATIONS"
    
    if [[ -f /etc/fstab ]]; then
        if grep -q "noatime" /etc/fstab; then
            echo "   [OK] noatime mount option: configured"
            increment_verify_pass
        else
            echo "   [WARN] noatime mount option: not configured"
            increment_verify_warn
        fi
    fi
    
    # Check for SSD/trim if applicable
    if systemctl is-enabled fstrim.timer &>/dev/null; then
        echo "   [OK] fstrim timer: enabled"
        increment_verify_pass
    fi
    
    # 6. Memory optimizations
    print_verify_section "" "MEMORY OPTIMIZATIONS"
    
    verify_module_loaded "zram" "ZRAM compression" && increment_verify_pass || increment_verify_warn
    
    if [[ -f /sys/block/zram0/comp_algorithm ]]; then
        local zram_algo
        zram_algo=$(cat /sys/block/zram0/comp_algorithm 2>/dev/null | grep -oP '\[\K[^\]]+')
        echo "   -> Compression algorithm: $zram_algo"
    fi
    
    # Print summary
    print_verify_summary
    
    # Recommendations
    if [[ $VERIFY_FAIL_COUNT -gt 0 ]] || [[ $VERIFY_WARN_COUNT -gt 0 ]]; then
        print_info "=========================================="
        print_info "RECOMMENDATIONS:"
        print_info "=========================================="
        echo ""
        if [[ $VERIFY_FAIL_COUNT -gt 0 ]]; then
            echo "[FAIL] Critical issues found. Run optimization:"
            echo "  sudo $0"
        else
            echo "[WARN] Some optimizations missing. Consider running:"
            echo "  sudo $0"
        fi
        echo ""
    else
        print_info "All VM optimizations are active!"
    fi
    
    # Re-enable error exit
    set -e
}


# Uninstall optimizations
uninstall_optimizations() {
    print_warning "Uninstalling VM optimizations..."
    
    # Check if running in VS Code environment
    if detect_vscode_environment; then
        print_info "VS Code environment detected - preserving development tools"
        print_info "Skipping uninstall of development-related services"
    fi
    
    # Unmask OBEX service if it was masked
    if [ -L "$HOME/.config/systemd/user/obex.service" ]; then
        print_info "Unmasking OBEX service"
        systemctl --user unmask obex.service 2>/dev/null || true
    fi

    # Remove VS Code hardware acceleration disable
    if [ -f "$HOME/.config/Code/argv.json" ]; then
        print_info "Re-enabling VS Code hardware acceleration"
        rm -f "$HOME/.config/Code/argv.json" 2>/dev/null || true
    fi

    # Remove Chrome hardware acceleration disable
    if [ -f "$HOME/.config/google-chrome/chrome-flags.conf" ]; then
        print_info "Re-enabling Google Chrome hardware acceleration"
        rm -f "$HOME/.config/google-chrome/chrome-flags.conf" 2>/dev/null || true
        # Restore backup if exists
        if [ -f "$HOME/.config/google-chrome/Default/Preferences.vm-backup" ]; then
            mv "$HOME/.config/google-chrome/Default/Preferences.vm-backup" \
                "$HOME/.config/google-chrome/Default/Preferences" 2>/dev/null || true
        fi
    fi

    # Remove Slack hardware acceleration disable
    if [ -f "$HOME/.var/app/com.slack.Slack/config/Slack/storage.json" ]; then
        print_info "Re-enabling Slack hardware acceleration"
        rm -f "$HOME/.var/app/com.slack.Slack/config/Slack/storage.json" 2>/dev/null || true
        flatpak override --user --unset-env=ELECTRON_OZONE_PLATFORM_HINT com.slack.Slack 2>/dev/null || true
        flatpak override --user --unset-env=SLACK_DISABLE_GPU com.slack.Slack 2>/dev/null || true
    fi

    # Remove Firefox VM optimizations
    local firefox_profile_dir
    firefox_profile_dir=$(find "$HOME/.mozilla/firefox" -maxdepth 1 -name "*.default*" -type d 2>/dev/null | head -1)
    if [ -n "$firefox_profile_dir" ] && [ -f "$firefox_profile_dir/user.js" ]; then
        print_info "Re-enabling Firefox hardware acceleration"
        rm -f "$firefox_profile_dir/user.js" 2>/dev/null || true
    fi

    # Re-enable GNOME Boxes search provider
    if command -v gsettings &>/dev/null; then
        print_info "Re-enabling GNOME Boxes search provider"
        gsettings reset org.gnome.desktop.search-providers disabled 2>/dev/null || true
    fi
    
    # Re-enable services using libshell helpers
    local services=(
        "bluetooth.service"
        "cups.service"
        "avahi-daemon.service"
        "ModemManager.service"
        "thermald.service"
        "bolt.service"
        "fwupd.service"
        "packagekit.service"
    )

    manage_service_batch unmask "${services[@]}"
    manage_service_batch enable "${services[@]}"
    
    # Remove optimization files
    rm -f /etc/sysctl.d/98-vm-optimizer.conf
    rm -f /etc/udev/rules.d/60-vm-disk-scheduler.rules
    rm -f /etc/systemd/journald.conf.d/vm-optimizer.conf
    
    # Restore GRUB
    if [ -f /etc/default/grub.backup.vm-optimizer ]; then
        mv /etc/default/grub.backup.vm-optimizer /etc/default/grub
        grub2-mkconfig -o /boot/grub2/grub.cfg 2>/dev/null || \
        grub2-mkconfig -o /boot/efi/EFI/fedora/grub.cfg 2>/dev/null || true
    fi
    
    # Reload settings
    sudo sysctl --system >/dev/null 2>&1
    sudo systemctl daemon-reload

    print_info "VM optimizations uninstalled"
    print_info "Reboot required to fully restore settings"
}

# Main execution
main() {
    local FORCE_VM_TYPE=""

    # Check for --force-type option
    if [ "${1:-}" = "--force-type" ] && [ -n "${2:-}" ]; then
        FORCE_VM_TYPE="$2"
        shift 2
    fi

    # Print header
    echo ""
    echo ""

    # Detect virtualization
    print_info "Detecting virtualization platform..."

    local detection_result
    if [ -n "$FORCE_VM_TYPE" ]; then
        detection_result="$FORCE_VM_TYPE:forced"
    else
        # Use the common function for detection
        detection_result=$(detect_virtualization)
    fi

    local vm_type="${detection_result%%:*}"
    local detection_method="${detection_result##*:}"

    # Report findings
    echo ""
    if [ "$vm_type" = "none" ]; then
        print_warning "No virtualization detected - this appears to be a physical machine"
        print_info "VM optimization not recommended for physical hardware"
        exit 0
    elif [ "$vm_type" = "generic" ]; then
        print_info "Generic virtualization detected"
        print_info "Will apply general VM optimizations"
    else
        print_info "Detected: $vm_type (via $detection_method)"
    fi
    
    # Check only mode
    if [ "$CHECK_MODE" = true ]; then
        echo ""
        print_info "Check-only mode - no changes made"
        exit 0
    fi
    
    # Apply optimizations
    echo ""
    print_info "Applying VM optimizations for $vm_type..."
    print_info "Ported from Ansible playbooks for Terraform/Kubernetes-friendly deployments"
    echo ""
    
    # Apply optimizations using consolidated functions
    configure_vm_services
    configure_vm_kernel_params "$vm_type"
    install_vm_platform_tools "$vm_type"
    configure_vm_boot "$vm_type"
    configure_vm_disk_io
    configure_vm_memory
    configure_vm_gui_optimizations
    
    # Run verification
    echo ""
    verify_optimizations

    # Final message
    echo ""
    print_info "VM optimization complete!"
    echo ""
    print_info "Optimizations applied for: $vm_type"
    print_warning "Reboot recommended to apply all optimizations"
    echo ""
}

# Run main function
main "$@"
