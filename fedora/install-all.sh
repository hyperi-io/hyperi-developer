#!/bin/bash
# ============================================================================
# install-all - Complete Hyperi Development Environment Installation
# ============================================================================
# Runs all installation scripts in the recommended order
# Assumes a clean Fedora desktop installation
#
# USAGE:
#   sudo ./install-all.sh
#
# LICENSE:
#   Licensed under the Apache License, Version 2.0
#   See ../LICENSE file for full license text
# ============================================================================

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions library
if [[ -f "$SCRIPT_DIR/lib.sh" ]]; then
    source "$SCRIPT_DIR/lib.sh"
else
    echo "[ERROR] Cannot find lib.sh library" >&2
    exit 1
fi

# Initialize script with common setup
init_script "Complete Hyperi Development Environment Installation"

print_info "This will install all components in the recommended order"
print_info "Installation order: developer -> core -> vm -> rdp -> ghostty"
echo ""

# Track overall success
INSTALL_SUCCESS=true

# Function to run a script with error handling
run_installer() {
    local script_name="$1"
    local script_path="$SCRIPT_DIR/$script_name"

    if [ ! -f "$script_path" ]; then
        print_warning "Script not found: $script_name (skipping)"
        return 1
    fi

    if [ ! -x "$script_path" ]; then
        print_status "Making $script_name executable..."
        chmod +x "$script_path"
    fi

    print_header "Running $script_name"
    if "$script_path"; then
        print_success "$script_name completed successfully"
        return 0
    else
        print_error "$script_name failed"
        INSTALL_SUCCESS=false
        return 1
    fi
}

# 1. Main Developer Environment
if ! run_installer "install-hyperi-developer.sh"; then
    print_error "Main developer installation failed - stopping"
    exit 1
fi

# 2. Core Development Tools
if ! run_installer "install-hyperi-developer-core.sh"; then
    print_warning "Core tools installation failed - continuing"
fi

# 3. VM Optimizer (if in a VM)
if [ -n "$(systemd-detect-virt 2>/dev/null || echo '')" ] && [ "$(systemd-detect-virt)" != "none" ]; then
    print_info "VM detected - running VM optimizer"
    if ! run_installer "install-vm-optimizer.sh"; then
        print_warning "VM optimizer failed - continuing"
    fi
else
    print_info "Not in a VM - skipping VM optimizer"
fi

# 4. RDP Optimizer (if RDP session detected)
if [ -n "${SSH_CONNECTION:-}" ] || [ -n "${RDP_SESSION:-}" ] || [ -n "${REMOTE_DESKTOP_SESSION:-}" ]; then
    print_info "Remote session detected - running RDP optimizer"
    if ! run_installer "install-rdp-optimizer.sh"; then
        print_warning "RDP optimizer failed - continuing"
    fi
else
    print_info "Not in RDP session - skipping RDP optimizer"
fi

# Final summary
print_header "Installation Summary"

if [ "$INSTALL_SUCCESS" = true ]; then
    print_success "All critical components installed"
else
    print_warning "Some components failed to install - check logs above"
fi

print_info "Completed installations:"
echo "  [OK] Hyperi Developer Environment (includes Ghostty terminal)"
[ -f "$SCRIPT_DIR/install-hyperi-developer-core.sh" ] && echo "  [OK] Core Development Tools"
[ -n "$(systemd-detect-virt 2>/dev/null || echo '')" ] && [ "$(systemd-detect-virt)" != "none" ] && echo "  [OK] VM Optimizations"
[ -n "${SSH_CONNECTION:-}${RDP_SESSION:-}${REMOTE_DESKTOP_SESSION:-}" ] && echo "  [OK] RDP Optimizations"

echo ""
print_header "Next Steps"
print_info "1. Log out and back in for Docker group membership to take effect"
print_info "2. Run: source ~/.bashrc"
print_info "3. Configure your tools (JFrog, Azure CLI, ArgoCD, etc.)"
print_info "4. Check installed versions: docker --version, kubectl version, etc."

print_success "Complete Hyperi Development Environment setup finished"