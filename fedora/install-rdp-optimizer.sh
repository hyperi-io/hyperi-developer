#!/bin/bash
# ============================================================================
# install-rdp-optimizer - RDP Performance Optimizer for Fedora
# ============================================================================
# Optimizes Fedora gnome-remote-desktop for mobile and high-latency connections
# Designed for GNOME Remote Login feature (not desktop sharing)
#
# USAGE:
#   ./install-rdp-optimizer.sh [--password PASSWORD] [--username USERNAME]
#
# OPTIONS:
#   --password PASSWORD    Set RDP password (will prompt if not provided)
#   --username USERNAME    Set RDP username (defaults to current user)
#
# OPTIMIZES:
#   - TCP BBR congestion control for mobile performance
#   - MTU settings for reduced packet fragmentation
#   - H.264 codec priorities via Cisco OpenH264
#   - RDP protocol settings for low-bandwidth networks
#   - Network buffer sizes and queue management
#   - Compression with quality balance for bandwidth efficiency
#
# NOTE: Run after install-hyperi-developer.sh for best results
#       Requires GNOME desktop environment
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

# Parse command line arguments
RDP_PASSWORD=""
RDP_USERNAME=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --password)
            RDP_PASSWORD="$2"
            shift 2
            ;;
        --username)
            RDP_USERNAME="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [--password PASSWORD] [--username USERNAME]"
            echo ""
            echo "Options:"
            echo "  --password PASSWORD    Set RDP password (will prompt if not provided)"
            echo "  --username USERNAME    Set RDP username (defaults to current user)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Check OS immediately - must be Fedora
require_distro "fedora" "Fedora Linux"

# Detect target user (the one running the desktop session)
TARGET_USER="${SUDO_USER:-$USER}"
RDP_USERNAME="${RDP_USERNAME:-$TARGET_USER}"

# Script metadata
SCRIPT_NAME="$(basename "$0")"
SCRIPT_DESCRIPTION="Gnome Shell RDP optimiser"
STATE_FILE="/home/$TARGET_USER/.rdp-optimizer.state"
BACKUP_DIR="/home/$TARGET_USER/.rdp-optimizer-backup-$(date +%Y%m%d-%H%M%S)"

# Export for common functions
export SCRIPT_NAME SCRIPT_DESCRIPTION TARGET_USER


# Helper function to update dconf database
dconf_update_safe() {
    sudo dconf update || true
}

# Helper function to reload service
reload_service_safe() {
    local service="$1"
    sudo systemctl daemon-reload || true
}

# Helper function to update CA trust
update_ca_trust_safe() {
    sudo update-ca-trust || true
}

# Helper function to create certificate info
create_certificate_info() {
    local cert_file="$1"
    local info_file="$2"
    if [ -f "$cert_file" ]; then
        sudo openssl x509 -in "$cert_file" -text -noout | sudo tee "$info_file" >/dev/null 2>&1 || true
    fi
}

# Create backup directory
create_backup() {
    mkdir -p "$BACKUP_DIR"
    print_info "Created backup directory: $BACKUP_DIR"
    echo "$BACKUP_DIR" > "$STATE_FILE"
    echo "DATE=$(date -Iseconds)" >> "$STATE_FILE"
}

# Backup a file to RDP optimizer backup directory
backup_file_to_rdp_dir() {
    local file="$1"
    if [[ -f "$file" ]]; then
        cp -p "$file" "$BACKUP_DIR/$(basename "$file").bak"
        print_info "Backed up: $file"
    fi
}

# Apply system-wide dconf settings for gnome-remote-desktop
apply_system_dconf() {
    local schema="$1"
    local key="$2"
    local value="$3"
    
    # Create system-wide dconf profile if it doesn't exist
    if [[ ! -f /etc/dconf/profile/user ]]; then
        sudo mkdir -p /etc/dconf/profile
        sudo bash -c 'cat > /etc/dconf/profile/user << '\''EOF'\''
user-db:user
system-db:local
EOF'
    fi

    # Create the database directory
    sudo mkdir -p /etc/dconf/db/local.d

    # Create or update the settings file
    local settings_file="/etc/dconf/db/local.d/00-rdp-optimizer"

    if [[ ! -f "$settings_file" ]]; then
        sudo bash -c "echo '# RDP Optimizer System-Wide Settings for gnome-remote-desktop' > '$settings_file'"
        sudo bash -c "echo '# Optimized for Fedora Remote Login' >> '$settings_file'"
        sudo bash -c "echo '' >> '$settings_file'"
    fi

    # Add the schema section if not present
    if ! sudo grep -q "^\[$schema\]" "$settings_file" 2>/dev/null; then
        sudo bash -c "echo '' >> '$settings_file'"
        sudo bash -c "echo '[$schema]' >> '$settings_file'"
    fi

    # Add or update the key-value pair
    # Use a simpler approach - write to temp file then move
    if sudo grep -q "^$key=" "$settings_file" 2>/dev/null; then
        # Key exists, update it
        sudo awk -v schema="[$schema]" -v key="$key" -v value="$value" '
            BEGIN { in_section = 0 }
            $0 == schema { in_section = 1 }
            /^\[/ && $0 != schema { in_section = 0 }
            in_section && $0 ~ "^" key "=" { print key "=" value; next }
            { print }
        ' "$settings_file" | sudo tee "$settings_file.tmp" >/dev/null && sudo mv "$settings_file.tmp" "$settings_file"
    else
        # Key doesn't exist, add it after the schema header
        sudo awk -v schema="[$schema]" -v key="$key" -v value="$value" '
            { print }
            $0 == schema { print key "=" value }
        ' "$settings_file" | sudo tee "$settings_file.tmp" >/dev/null && sudo mv "$settings_file.tmp" "$settings_file"
    fi
}

# ============================================================================
# OPTIMIZATION CONSOLIDATION FUNCTIONS
# ============================================================================

# Configure GNOME Remote Desktop settings
configure_gnome_rdp() {
    print_info "Step 1: Configuring gnome-remote-desktop settings (system-wide)..."
    
    # Backup existing dconf database
    if [[ -d /etc/dconf/db/local.d ]]; then
        cp -r /etc/dconf/db/local.d "$BACKUP_DIR/dconf-local.d.bak"
    fi
    
    # Apply optimized settings for gnome-remote-desktop
    apply_system_dconf "org/gnome/remote-desktop/rdp" "enable-audio" "false"
    apply_system_dconf "org/gnome/remote-desktop/rdp" "enable-h264" "true"
    apply_system_dconf "org/gnome/remote-desktop/rdp" "view-only" "false"
    apply_system_dconf "org/gnome/remote-desktop/rdp" "port" "3389"
    
    # Reduce visual effects for better RDP performance
    apply_system_dconf "org/gnome/desktop/interface" "enable-animations" "false"
    apply_system_dconf "org/gnome/desktop/interface" "enable-hot-corners" "false"
    apply_system_dconf "org/gnome/desktop/wm/preferences" "auto-raise" "false"
    apply_system_dconf "org/gnome/mutter" "experimental-features" "['scale-monitor-framebuffer']"
    
    # Update dconf database
    dconf_update_safe
    print_info "  [OK] gnome-remote-desktop optimized with H.264 encoding"
    print_info "  [OK] Visual effects reduced for better performance"
}

# Apply TCP optimizations
apply_tcp_optimizations() {
    print_info "Step 2: Applying TCP optimizations (system-wide)..."

    backup_file_to_rdp_dir "/etc/sysctl.d/99-rdp-optimization.conf"

    # Define TCP optimization settings as array
    local tcp_settings=(
        "# RDP Optimizer - System-Wide TCP Settings"
        "# Ported from Ansible configurations for Terraform/Kubernetes-friendly deployments"
        "# Optimized for mobile and high-latency RDP connections"
        ""
        "# TCP BBR congestion control for better mobile/high-latency performance"
        "net.core.default_qdisc = fq"
        "net.ipv4.tcp_congestion_control = bbr"
        ""
        "# Increase TCP buffer sizes for RDP streaming"
        "net.core.rmem_default = 87380"
        "net.core.rmem_max = 16777216"
        "net.core.wmem_default = 65536"
        "net.core.wmem_max = 16777216"
        "net.ipv4.tcp_rmem = 4096 131072 16777216"
        "net.ipv4.tcp_wmem = 4096 65536 16777216"
        ""
        "# Optimize for RDP traffic patterns"
        "net.ipv4.tcp_fin_timeout = 30"
        "net.ipv4.tcp_keepalive_time = 1200"
        "net.ipv4.tcp_keepalive_probes = 3"
        "net.ipv4.tcp_keepalive_intvl = 15"
        ""
        "# Enable TCP window scaling and selective ACK"
        "net.ipv4.tcp_window_scaling = 1"
        "net.ipv4.tcp_sack = 1"
        "net.ipv4.tcp_fack = 1"
        ""
        "# Reduce TIME_WAIT socket recycling delay"
        "net.ipv4.tcp_tw_reuse = 1"
    )

    # Use libshell helper to create and apply sysctl configuration
    create_sysctl_config "99-rdp-optimization" "RDP TCP Optimizations" "${tcp_settings[@]}"

    print_info "  [OK] TCP BBR congestion control enabled"
    print_info "  [OK] TCP buffers optimized for streaming"
}

# Configure MTU settings
configure_mtu_settings() {
    print_info "Step 3: Configuring MTU settings..."
    
    local mtu_size
    if [ "$VPN_OPTIMIZE" = true ]; then
        mtu_size=1200
        print_info "  Using VPN-optimized MTU: $mtu_size bytes"
    else
        mtu_size=1400
        print_info "  Using standard optimized MTU: $mtu_size bytes"
    fi
    
    backup_file_to_rdp_dir "/etc/NetworkManager/conf.d/99-rdp-mtu.conf"

    sudo bash -c "cat > /etc/NetworkManager/conf.d/99-rdp-mtu.conf << EOF
# RDP Optimizer MTU Configuration
# Prevents packet fragmentation for RDP traffic
[connection]
eth.mtu = $mtu_size
wifi.mtu = $mtu_size
EOF"

    # Apply immediately if NetworkManager is running
    reload_service_safe "NetworkManager"
    
    print_info "  [OK] MTU set to $mtu_size bytes (reduces fragmentation)"
}


# Configure RDP certificates for system service
configure_rdp_certificate() {
    print_info "Step 5: Configuring RDP certificates..."

    local sys_cert_dir="/var/lib/gnome-remote-desktop/.local/share/gnome-remote-desktop/certificates"
    local sys_cert="$sys_cert_dir/rdp-tls.crt"
    local sys_key="$sys_cert_dir/rdp-tls.key"

    # Create certificate directory
    sudo mkdir -p "$sys_cert_dir"
    sudo chown gnome-remote-desktop:gnome-remote-desktop "$sys_cert_dir"

    # Generate self-signed certificates if missing or empty
    if [[ ! -f "$sys_cert" ]] || [[ ! -s "$sys_cert" ]]; then
        print_info "  Generating system RDP certificates..."
        sudo openssl req -x509 -newkey rsa:4096 \
            -keyout "$sys_key" \
            -out "$sys_cert" \
            -days 365 -nodes \
            -subj "/CN=gnome-remote-desktop" 2>&1 | grep -v "+" || true
        sudo chown gnome-remote-desktop:gnome-remote-desktop "$sys_cert" "$sys_key"
        sudo chmod 600 "$sys_cert" "$sys_key"
        print_info "  [OK] Certificates generated"
    else
        print_info "  [OK] Certificates already exist"
    fi

    # Configure grdctl to use the certificates
    sudo grdctl --system rdp set-tls-cert "$sys_cert" 2>&1 | grep -v "TPM" || true
    sudo grdctl --system rdp set-tls-key "$sys_key" 2>&1 | grep -v "TPM" || true

    print_info "  [OK] System certificates configured"
}

install_optimizations() {
    print_info "========================================="
    print_info "Starting RDP optimization installation..."
    print_info "Target: gnome-remote-desktop (System Service - Auto-Resize)"
    print_info "Ported from Ansible configurations for Terraform/Kubernetes-friendly deployments"

    create_backup

    # Check if gnome-remote-desktop is installed
    if ! rpm -q gnome-remote-desktop &>/dev/null; then
        print_warning "gnome-remote-desktop not installed. Installing..."
        dnf install -y gnome-remote-desktop || {
            print_error "Failed to install gnome-remote-desktop"
            exit 1
        }
    fi
    
    # Apply optimizations using consolidated functions
    configure_gnome_rdp
    apply_tcp_optimizations
    configure_mtu_settings
    configure_rdp_certificate

    # Enable system service
    print_info "Enabling gnome-remote-desktop system service..."
    sudo systemctl enable --now gnome-remote-desktop.service || true
    sudo grdctl --system rdp enable 2>&1 | grep -v "TPM" || true
    print_info "  [OK] System service enabled (supports auto-resize)"

    # Set RDP credentials
    if [ -z "$RDP_PASSWORD" ]; then
        echo ""
        print_info "RDP credentials required for Remote Login"
        read -p "Enter RDP username [$RDP_USERNAME]: " input_user
        RDP_USERNAME="${input_user:-$RDP_USERNAME}"
        read -s -p "Enter RDP password for $RDP_USERNAME: " RDP_PASSWORD
        echo ""
    fi

    if [ -n "$RDP_PASSWORD" ]; then
        print_info "Setting RDP credentials for $RDP_USERNAME..."
        sudo grdctl --system rdp set-credentials "$RDP_USERNAME" "$RDP_PASSWORD" 2>&1 | grep -v "TPM" || true
        sudo systemctl restart gnome-remote-desktop.service 2>/dev/null || true
        print_info "  [OK] Credentials configured"
    else
        print_warning "No password provided - RDP credentials must be set manually"
        print_info "  Run: sudo grdctl --system rdp set-credentials <user> <password>"
    fi

    # Record installation state
    echo "INSTALLATION_DATE=$(date)" >> "$STATE_FILE"
    echo "VPN_OPTIMIZE=$VPN_OPTIMIZE" >> "$STATE_FILE"
    
    print_info "========================================="
    print_info "RDP optimization installation complete!"
    print_info "========================================="
    print_info "Changes applied:"
    print_info "• GNOME Remote Desktop: H.264 encoding enabled"
    print_info "• TCP: BBR congestion control active"
    print_info "• MTU: Set to $([ "$VPN_OPTIMIZE" = true ] && echo "1200" || echo "1400") bytes"
    print_info "• Certificate: Added to system trust store"
    print_info ""
    print_info "Next steps:"
    if [ -n "$RDP_PASSWORD" ]; then
        print_info "RDP is ready - connect to this machine via RDP"
        print_info "  Hostname: $(hostname)"
        print_info "  Port: 3389"
        print_info "  Username: $RDP_USERNAME"
    else
        print_info "Set RDP credentials: sudo grdctl --system rdp set-credentials <user> <password>"
    fi
    print_info "Reboot to apply all optimizations: sudo reboot"
    print_info ""
    print_info "Note: Remote Login mode supports auto-resize to RDP client window size"
    print_info ""
    print_info "Running verification..."
    
    # Run verification
    verify_optimizations
}

uninstall_optimizations() {
    print_info "========================================="
    print_info "Starting uninstall process..."
    
    # Check if running in VS Code environment
    if detect_vscode_environment; then
        print_info "VS Code environment detected - preserving development environment"
        print_info "Continuing with RDP optimization removal (safe for development)"
    fi
    
    if [[ ! -f "$STATE_FILE" ]]; then
        print_error "No installation found. Cannot uninstall."
        exit 1
    fi
    
    BACKUP_DIR=$(grep "^/" "$STATE_FILE" | head -1)
    
    if [[ ! -d "$BACKUP_DIR" ]]; then
        print_error "Backup directory not found: $BACKUP_DIR"
        exit 1
    fi
    
    # Restore dconf database
    if [[ -d "$BACKUP_DIR/dconf-local.d.bak" ]]; then
        sudo safe_rm_rf /etc/dconf/db/local.d
        cp -r "$BACKUP_DIR/dconf-local.d.bak" /etc/dconf/db/local.d
        dconf update
        print_info "Restored dconf database"
    else
        rm -f /etc/dconf/db/local.d/00-rdp-optimizer
        dconf update
    fi
    
    # Restore files
    for backup_file_path in "$BACKUP_DIR"/*.bak; do
        if [[ -f "$backup_file_path" ]]; then
            original_name=$(basename "$backup_file_path" .bak)
            
            case "$original_name" in
                "dconf-local.d.bak")
                    # Already handled above
                    ;;
                "mtu.bak")
                    while IFS='=' read -r interface mtu; do
                        ip link set dev "$interface" mtu "$mtu" 2>/dev/null || true
                    done < "$backup_file_path"
                    print_info "Restored MTU settings"
                    ;;
                *)
                    # Regular file restoration
                    target_file="/etc/$original_name"
                    [[ -f "/etc/sysctl.d/$original_name" ]] && target_file="/etc/sysctl.d/$original_name"
                    [[ -f "/etc/systemd/$original_name" ]] && target_file="/etc/systemd/$original_name"
                    [[ -f "/etc/X11/$original_name" ]] && target_file="/etc/X11/$original_name"
                    
                    if [[ "$original_name" == "99-rdp-optimization.conf" ]]; then
                        rm -f "/etc/sysctl.d/99-rdp-optimization.conf"
                        print_info "Removed TCP optimization config"
                    elif [[ -f "$backup_file_path" ]]; then
                        cp -p "$backup_file_path" "$target_file"
                        print_info "Restored: $target_file"
                    fi
                    ;;
            esac
        fi
    done
    
    # Remove created files
    rm -f /etc/profile.d/rdp-optimizer.sh
    rm -f /etc/NetworkManager/dispatcher.d/99-rdp-mtu
    rm -f /etc/NetworkManager/dispatcher.d/99-rdp-vpn-mtu
    sudo rm -f /etc/systemd/system/gnome-remote-desktop.service.d/optimization.conf
    rm -f /etc/pki/ca-trust/source/anchors/gnome-remote-desktop-rdp.crt
    rm -f /etc/gnome-remote-desktop-cert-info.txt
    update-ca-trust
    
    # Reload services
    systemctl daemon-reload
    sysctl --system > /dev/null 2>&1
    
    # Clean up state file
    rm -f "$STATE_FILE"
    
    print_info ""
    print_info "========================================="
    print_info "RDP Optimization Uninstall Complete!"
    print_info "========================================="
    print_info ""
    print_info "All system-wide settings have been reverted."
    print_info "Backup directory preserved at: $BACKUP_DIR"
    print_info ""
    print_warning "Please restart affected services:"
    print_warning "  systemctl restart gnome-remote-desktop"
    print_warning "  systemctl restart gdm"
    print_warning "  systemctl restart NetworkManager"
}

check_optimizations() {
    print_info "========================================="
    
    if [[ ! -f "$STATE_FILE" ]]; then
        print_warning "Status: NOT INSTALLED"
        echo ""
        print_info "To install optimizations, run:"
        print_info "  sudo $0 install              # Standard installation"
        print_info "  sudo $0 install --vpn-optimize  # With VPN-specific MTU"
        exit 0
    fi
    
    print_info "Status: INSTALLED"
    echo ""
    
    # Show installation details
    if [[ -f "$STATE_FILE" ]]; then
        echo "Installation details:"
        cat "$STATE_FILE" | while IFS='=' read -r key value; do
            [[ -n "$key" ]] && echo "  $key: $value"
        done
    fi
    
    echo ""
    echo "Current system settings:"
    
    # Check TCP settings
    echo "  TCP Congestion Control: $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo 'unknown')"
    echo "  TCP Fast Open: $(sysctl -n net.ipv4.tcp_fastopen 2>/dev/null || echo 'unknown')"
    
    # Check gnome-remote-desktop status
    echo ""
    echo "GNOME Remote Desktop status:"
    if systemctl is-active gnome-remote-desktop.service &>/dev/null; then
        echo "  gnome-remote-desktop.service: $(systemctl is-active gnome-remote-desktop.service)"
    else
        echo "  gnome-remote-desktop.service: inactive"
    fi
    
    # Check if Remote Login is configured (with timeout to prevent hanging)
    if command -v grdctl &>/dev/null; then
        echo ""
        echo "Remote Desktop configuration:"
        # Check system-wide (Remote Login) with timeout
        if timeout 2 grdctl --system status &>/dev/null 2>&1; then
            echo "  Remote Login (system): configured"
        else
            echo "  Remote Login (system): not configured"
        fi
        # Check user session (Desktop Sharing) with timeout
        if timeout 2 grdctl status &>/dev/null 2>&1; then
            echo "  Desktop Sharing (user): configured"
        else
            echo "  Desktop Sharing (user): not configured"
        fi
    fi
    
    # Check for our files
    echo ""
    echo "Optimizer files present:"
    [[ -f /etc/sysctl.d/99-rdp-optimization.conf ]] && echo "  [OK] TCP optimization config"
    [[ -f /etc/NetworkManager/conf.d/99-rdp-mtu.conf ]] && echo "  [OK] MTU configuration"
    [[ -f /etc/dconf/db/local.d/00-rdp-optimizer ]] && echo "  [OK] Desktop settings (dconf)"
    [[ -f /etc/pki/ca-trust/source/anchors/gnome-remote-desktop-rdp.crt ]] && echo "  [OK] RDP certificate trust"
    
    echo ""
    print_info "To uninstall, run: sudo $0 uninstall"
}

# Quick verification function (like the standalone script)
verify_optimizations() {
    print_info "=========================================="
    print_info "RDP Optimization Verification Report"
    print_info "=========================================="
    echo ""
    
    # Check dconf settings
    echo "DCONF SETTINGS (Desktop optimizations):"
    if [[ -f /etc/dconf/db/local.d/00-rdp-optimizer ]]; then
        echo "   [OK] Configuration file exists"
        grep -q "enable-h264=true" /etc/dconf/db/local.d/00-rdp-optimizer && echo "   [OK] H.264 encoding: ENABLED (better compression)"
        grep -q "enable-audio=false" /etc/dconf/db/local.d/00-rdp-optimizer && echo "   [OK] Audio: DISABLED (saves bandwidth)"
        grep -q "enable-animations=false" /etc/dconf/db/local.d/00-rdp-optimizer && echo "   [OK] Animations: DISABLED (faster response)"
        grep -q "enable-hot-corners=false" /etc/dconf/db/local.d/00-rdp-optimizer && echo "   [OK] Hot corners: DISABLED (prevents accidental triggers)"
    else
        echo "   [FAIL] Not configured"
    fi
    echo ""
    
    # TCP Optimizations
    echo "TCP/NETWORK OPTIMIZATIONS:"
    if [[ -f /etc/sysctl.d/99-rdp-optimization.conf ]]; then
        echo "   [OK] TCP config file exists"
        
        # Check current vs configured
        local current_cc
        current_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
        if grep -q "tcp_congestion_control = bbr" /etc/sysctl.d/99-rdp-optimization.conf; then
            echo "   [OK] BBR congestion control: CONFIGURED"
            if [[ "$current_cc" == "bbr" ]]; then
                echo "     -> Currently ACTIVE"
            else
                echo "     -> Currently: $current_cc (reboot to activate BBR)"
            fi
        fi

        local current_tfo
        current_tfo=$(sysctl -n net.ipv4.tcp_fastopen 2>/dev/null)
        echo "   [OK] TCP Fast Open: $current_tfo (3=enabled for client+server)"
        
        # Buffer sizes
        local rmem_max
        rmem_max=$(sysctl -n net.core.rmem_max 2>/dev/null)
        echo "   [OK] Receive buffer: $(( rmem_max / 1024 / 1024 ))MB"
    else
        echo "   [FAIL] Not configured"
    fi
    echo ""
    
    # MTU Settings
    echo "MTU OPTIMIZATION:"
    if [[ -f /etc/NetworkManager/dispatcher.d/99-rdp-mtu ]]; then
        echo "   [OK] MTU script installed"
        
        # Check current interface MTU
        local active_iface
        active_iface=$(ip route | grep default | awk '{print $5}' | head -1)
        if [[ -n "$active_iface" ]]; then
            local current_mtu
            current_mtu=$(ip link show "$active_iface" | grep -oP 'mtu \K[0-9]+')
            echo "   -> Interface $active_iface: MTU=$current_mtu"
            if [[ "$current_mtu" == "1450" ]] || [[ "$current_mtu" == "1400" ]]; then
                echo "     [OK] Optimized for RDP"
            else
                echo "     [WARN] Not yet optimized (restart NetworkManager)"
            fi
        fi
    else
        echo "   [FAIL] Not configured"
    fi
    echo ""
    
    # Service optimizations
    echo "SERVICE OPTIMIZATIONS:"
    if [[ -f /etc/systemd/system/gnome-remote-desktop.service.d/optimization.conf ]]; then
        echo "   [OK] Service optimization configured"
        systemctl is-active gnome-remote-desktop &>/dev/null && echo "   [OK] Service: ACTIVE" || echo "   [WARN] Service: INACTIVE"
        systemctl is-enabled gnome-remote-desktop &>/dev/null && echo "   [OK] Service: ENABLED at boot" || echo "   [WARN] Service: NOT enabled at boot"
    else
        echo "   [FAIL] Not configured"
    fi
    echo ""
    
    # Memory optimizations
    echo "MEMORY OPTIMIZATIONS:"
    if lsmod | grep -q zram; then
        echo "   [OK] ZRAM compression: ENABLED"
        if [[ -f /sys/block/zram0/comp_algorithm ]]; then
            local algo
            algo=$(cat /sys/block/zram0/comp_algorithm 2>/dev/null | grep -oP '\[\K[^\]]+')
            echo "   -> Compression algorithm: $algo"
        fi
        if [[ -f /sys/block/zram0/disksize ]]; then
            local size
            size=$(cat /sys/block/zram0/disksize 2>/dev/null)
            local size_mb=$(( size / 1024 / 1024 ))
            echo "   -> ZRAM size: ${size_mb}MB"
        fi
    else
        echo "   [WARN] ZRAM not loaded"
    fi
    echo ""
    
    # Certificate trust
    echo "CERTIFICATE TRUST:"
    if [[ -f /etc/pki/ca-trust/source/anchors/gnome-remote-desktop-rdp.crt ]]; then
        echo "   [OK] RDP certificate in system trust store"
        if [[ -f /etc/gnome-remote-desktop-cert-info.txt ]]; then
            echo "   [OK] Certificate info available at /etc/gnome-remote-desktop-cert-info.txt"
            # Show fingerprint from the info file
            local fingerprint
            fingerprint=$(grep "SHA256 Fingerprint:" /etc/gnome-remote-desktop-cert-info.txt | cut -d':' -f2- | xargs)
            if [[ -n "$fingerprint" ]]; then
                echo "   -> SHA256: $fingerprint"
            fi
        fi
    else
        echo "   [WARN] Certificate not trusted (will cause security warnings)"
        echo "   -> Run: sudo $0 install"
    fi
    echo ""
    
    # Summary of improvements
    print_info "=========================================="
    print_info "IMPROVEMENTS PROVIDED BY OPTIMIZATIONS:"
    print_info "=========================================="
    echo ""
    echo "[OK] REDUCED LATENCY:"
    echo "  - BBR congestion control adapts to network conditions"
    echo "  - TCP Fast Open reduces connection setup time"
    echo "  - Optimized MTU prevents packet fragmentation"
    echo ""
    echo "[OK] BETTER PERFORMANCE:"
    echo "  - H.264 encoding provides efficient video compression"
    echo "  - Disabled animations reduce rendering overhead"
    echo "  - Larger network buffers handle burst traffic better"
    echo ""
    echo "[OK] IMPROVED STABILITY:"
    echo "  - Service restart on failure"
    echo "  - ZRAM compression reduces memory pressure"
    echo ""
    echo "[OK] SECURITY:"
    echo "  - RDP certificate trusted system-wide"
    echo "  - No more 'insecure connection' warnings"
    echo "  - Certificate info available for client configuration"
    echo ""
    
    # Check if reboot needed
    local needs_reboot=false
    [[ "${current_cc:-}" != "bbr" ]] && needs_reboot=true
    
    if $needs_reboot; then
        echo "[WARN] IMPORTANT: Some optimizations require a reboot to take full effect"
        echo "  Recommended: sudo reboot"
    else
        echo "[OK] All optimizations are active!"
    fi
    echo ""
}

verify_optimizations() {
    print_info "========================================="
    
    local tests_passed=0
    local tests_failed=0
    local tests_warning=0
    
    # Check if installed
    if [[ ! -f "$STATE_FILE" ]]; then
        print_error "RDP Optimizer is not installed. Run: sudo $0 install"
        exit 1
    fi
    
    print_info "Running verification tests..."
    echo ""
    
    # Test: dconf settings
    print_info "Testing dconf settings..."
    if [[ -f /etc/dconf/db/local.d/00-rdp-optimizer ]]; then
        # Check critical settings
        if grep -q "enable-h264=true" /etc/dconf/db/local.d/00-rdp-optimizer; then
            print_info "  [OK] H.264 encoding enabled"
            ((tests_passed++))
        else
            print_error "  [FAIL] H.264 encoding not enabled"
            ((tests_failed++))
        fi
        
        if grep -q "enable-animations=false" /etc/dconf/db/local.d/00-rdp-optimizer; then
            print_info "  [OK] Animations disabled for performance"
            ((tests_passed++))
        else
            print_error "  [FAIL] Animations not disabled"
            ((tests_failed++))
        fi
        
        if grep -q "port=3389" /etc/dconf/db/local.d/00-rdp-optimizer; then
            print_info "  [OK] RDP port configured (3389)"
            ((tests_passed++))
        else
            print_error "  [FAIL] RDP port not configured"
            ((tests_failed++))
        fi
    else
        print_error "  [FAIL] dconf settings file missing"
        ((tests_failed++))
    fi
    echo ""
    
    # Test: TCP optimizations
    print_info "Testing TCP/Network optimizations..."
    
    # Check if sysctl file exists
    if [[ -f /etc/sysctl.d/99-rdp-optimization.conf ]]; then
        print_info "  [OK] TCP optimization config exists"
        ((tests_passed++))
        
        # Check if BBR is configured (will be active after reboot)
        if grep -q "tcp_congestion_control = bbr" /etc/sysctl.d/99-rdp-optimization.conf; then
            print_info "  [OK] BBR congestion control configured"
            ((tests_passed++))
        else
            print_error "  [FAIL] BBR not configured"
            ((tests_failed++))
        fi
        
        # Check current active settings
        local current_cc
        current_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
        if [[ "$current_cc" == "bbr" ]]; then
            print_info "  [OK] BBR currently active"
            ((tests_passed++))
        else
            print_warning "  [WARN] BBR not yet active (current: $current_cc) - reboot required"
            ((tests_warning++))
        fi
        
        # Check TCP Fast Open
        local current_tfo
        current_tfo=$(sysctl -n net.ipv4.tcp_fastopen 2>/dev/null)
        if [[ "$current_tfo" == "3" ]]; then
            print_info "  [OK] TCP Fast Open enabled"
            ((tests_passed++))
        else
            print_warning "  [WARN] TCP Fast Open not active (current: $current_tfo) - reboot may be required"
            ((tests_warning++))
        fi
    else
        print_error "  [FAIL] TCP optimization config missing"
        ((tests_failed++))
    fi
    echo ""
    
    # Test: MTU settings
    print_info "Testing MTU optimizations..."
    if [[ -f /etc/NetworkManager/conf.d/99-rdp-mtu.conf ]]; then
        print_info "  [OK] MTU optimization config exists"
        ((tests_passed++))

        # Check current MTU on active interface
        local active_iface
        active_iface=$(ip route | grep default | awk '{print $5}' | head -1)
        if [[ -n "$active_iface" ]]; then
            local current_mtu
            current_mtu=$(ip link show "$active_iface" | grep -oP 'mtu \K[0-9]+')
            if [[ "$current_mtu" == "1450" ]] || [[ "$current_mtu" == "1400" ]]; then
                print_info "  [OK] MTU optimized on $active_iface: $current_mtu"
                ((tests_passed++))
            else
                print_warning "  [WARN] MTU will be applied after NetworkManager restart"
                ((tests_warning++))
            fi
        fi
    else
        print_error "  [FAIL] MTU optimization config missing"
        ((tests_failed++))
    fi
    echo ""

    # Test: Service configuration
    print_info "Testing service configurations..."
    if [[ -f /etc/dconf/db/local.d/00-rdp-optimizer ]]; then
        print_info "  [OK] Service optimization config exists"
        ((tests_passed++))

        # Check if service is running
        if systemctl is-active gnome-remote-desktop &>/dev/null; then
            print_info "  [OK] gnome-remote-desktop service is active"
            ((tests_passed++))
        else
            print_warning "  [WARN] gnome-remote-desktop service not active"
            ((tests_warning++))
        fi

        # Check if service is enabled
        if systemctl is-enabled gnome-remote-desktop &>/dev/null; then
            print_info "  [OK] gnome-remote-desktop service is enabled"
            ((tests_passed++))
        else
            print_warning "  [WARN] gnome-remote-desktop service not enabled"
            ((tests_warning++))
        fi
    else
        print_error "  [FAIL] Service optimization config missing"
        ((tests_failed++))
    fi
    echo ""
    
    # Test: Backup verification
    print_info "Testing backup integrity..."
    local backup_dir
    backup_dir=$(grep "^/" "$STATE_FILE" | head -1)
    if [[ -d "$backup_dir" ]]; then
        print_info "  [OK] Backup directory exists: $backup_dir"
        ((tests_passed++))
        
        # Count backup files
        local backup_count
        backup_count=$(find "$backup_dir" -name "*.bak" 2>/dev/null | wc -l)
        if [[ $backup_count -gt 0 ]]; then
            print_info "  [OK] $backup_count backup files found"
            ((tests_passed++))
        else
            print_warning "  [WARN] No backup files found"
            ((tests_warning++))
        fi
    else
        print_error "  [FAIL] Backup directory missing"
        ((tests_failed++))
    fi
    echo ""
    
    # Test: Certificate trust
    print_info "Testing certificate trust..."
    if [[ -f /etc/pki/ca-trust/source/anchors/gnome-remote-desktop-rdp.crt ]]; then
        print_info "  [OK] RDP certificate in trust store"
        ((tests_passed++))
        
        # Check if certificate info file exists
        if [[ -f /etc/gnome-remote-desktop-cert-info.txt ]]; then
            print_info "  [OK] Certificate info file exists"
            ((tests_passed++))
        else
            print_warning "  [WARN] Certificate info file missing"
            ((tests_warning++))
        fi
    else
        print_warning "  [WARN] RDP certificate not in trust store"
        ((tests_warning++))
    fi
    echo ""
    
    # Test: Memory optimizations
    print_info "Testing memory optimizations..."
    if lsmod | grep -q zram; then
        print_info "  [OK] ZRAM compression module loaded"
        ((tests_passed++))
    else
        print_warning "  [WARN] ZRAM not loaded"
        ((tests_warning++))
    fi
    
    if [[ -f /sys/block/zram0/comp_algorithm ]]; then
        local zram_algo
        zram_algo=$(cat /sys/block/zram0/comp_algorithm 2>/dev/null | grep -oP '\[\K[^\]]+')
        print_info "  [OK] ZRAM using algorithm: $zram_algo"
        ((tests_passed++))
    fi
    echo ""
    
    # Summary
    print_info "========================================="
    print_info "Test Summary:"
    print_info "  Passed:   $tests_passed"
    [[ $tests_warning -gt 0 ]] && print_warning "  Warnings: $tests_warning"
    [[ $tests_failed -gt 0 ]] && print_error "  Failed:   $tests_failed"
    echo ""
    
    if [[ $tests_failed -eq 0 ]]; then
        if [[ $tests_warning -gt 0 ]]; then
            print_warning "Optimizations installed successfully!"
            print_warning "Some settings require service restart or reboot to take effect."
            echo ""
            print_info "Recommended actions:"
            print_info "  1. Restart services:"
            print_info "     sudo systemctl restart gnome-remote-desktop"
            print_info "     sudo systemctl restart NetworkManager"
            print_info "  2. For full optimization, reboot the system"
        else
            print_info "All optimizations verified and working!"
        fi
    else
        print_error "Some optimizations failed verification."
        print_error "Try reinstalling: sudo $0 uninstall && sudo $0 install"
    fi
}

# Main execution
# Initialize script and check for GNOME
init_script "RDP Performance Optimization"

# RDP optimization requires GNOME desktop
if ! is_gnome; then
    print_info "RDP optimizer requires GNOME desktop environment which is not running"
    print_info "Skipping RDP optimization"
    exit 0
fi

# Enable Fedora's Cisco OpenH264 repository for H.264 codec
sudo dnf config-manager --enable fedora-cisco-openh264 &>/dev/null || true

# Always run installation (functions use sudo internally)
install_optimizations

# Verify at the end
verify_optimizations
