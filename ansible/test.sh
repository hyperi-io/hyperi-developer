#!/bin/bash
# Test script for running ansible playbooks with install.sh-equivalent flags
#
# Usage:
#   ./test.sh --all                    # Full installation (maclike)
#   ./test.sh --all --winlike          # Full installation (winlike)
#   ./test.sh --core                   # Core tools only
#   ./test.sh --winlike                # Just winlike GNOME config
#   ./test.sh --maclike                # Just maclike GNOME config
#   ./test.sh --rdp                    # Just RDP config
#   ./test.sh --tags developer,base    # Custom tags
#
# Requires inventory file at /tmp/inventory_test.yml or specify with -i

set -euo pipefail

INVENTORY="${INVENTORY:-/tmp/inventory_test.yml}"
LIMIT=""
TAGS=""
EXTRA_ARGS=""

show_help() {
    cat << 'EOF'
Usage: ./test.sh [OPTIONS] [ANSIBLE_ARGS...]

OPTIONS:
  --all                 Full installation: developer,base,core,advanced,vm,optimizer,rdp,maclike
  --all --winlike       Full installation with winlike instead of maclike
  --core                Core tools: developer,base,core,advanced
  --winlike             Windows-style GNOME: developer,base,winlike
  --maclike             macOS-style GNOME: developer,base,maclike
  --rdp                 RDP only: rdp
  --tags TAGS           Custom tags (passed directly to ansible)
  --limit HOST          Limit to specific host (fedora, ubuntu)
  -i INVENTORY          Use custom inventory file
  --check               Dry-run mode
  --help                Show this help

EXAMPLES:
  ./test.sh --all --limit fedora           # Full install on Fedora only
  ./test.sh --core --limit ubuntu          # Core tools on Ubuntu only
  ./test.sh --winlike --limit fedora       # Just GNOME winlike on Fedora
  ./test.sh --all --winlike --limit fedora # Full install with winlike

INVENTORY:
  Default: /tmp/inventory_test.yml
  Create with:
    cat > /tmp/inventory_test.yml << 'INV'
    [fedora]
    dfe-dev.tyrell.com.au ansible_user=dfe ansible_password=dfe ansible_become_password=dfe

    [ubuntu]
    dfe-dev-u.tyrell.com.au ansible_user=dfe ansible_password=dfe ansible_become_password=dfe
    INV
EOF
    exit 0
}

# Parse arguments
WINLIKE_OVERRIDE=false
MATRIX_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --matrix)
            MATRIX_MODE=true
            shift
            ;;
        --profile)
            TAGS="$2"
            case "$2" in
                *all*) TAGS="${TAGS//all/rust,iac,gui_extras}" ;;
            esac
            if [[ "$TAGS" == *core* && "$TAGS" != *developer* ]]; then
                TAGS="developer,$TAGS"
            fi
            shift 2
            ;;
        --all)
            TAGS="developer,base,core,advanced,vm,optimizer,rdp,maclike"
            shift
            ;;
        --core)
            TAGS="developer,base,core,advanced"
            shift
            ;;
        --winlike)
            WINLIKE_OVERRIDE=true
            if [[ -z "$TAGS" ]]; then
                TAGS="developer,base,winlike"
            else
                TAGS="${TAGS},winlike"
            fi
            shift
            ;;
        --maclike)
            if [[ -z "$TAGS" ]]; then
                TAGS="developer,base,maclike"
            else
                TAGS="${TAGS},maclike"
            fi
            shift
            ;;
        --rdp)
            TAGS="rdp"
            shift
            ;;
        --tags)
            TAGS="$2"
            shift 2
            ;;
        --limit)
            LIMIT="--limit $2"
            shift 2
            ;;
        -i)
            INVENTORY="$2"
            shift 2
            ;;
        --check)
            EXTRA_ARGS="$EXTRA_ARGS --check"
            shift
            ;;
        --help|-h)
            show_help
            ;;
        *)
            EXTRA_ARGS="$EXTRA_ARGS $1"
            shift
            ;;
    esac
done

# Handle winlike override (remove maclike if winlike specified with --all)
if $WINLIKE_OVERRIDE && [[ "$TAGS" == *"maclike"* ]]; then
    echo "[INFO] winlike specified - removing maclike from tags"
    TAGS="${TAGS//,maclike/}"
    TAGS="${TAGS//maclike,/}"
    TAGS="${TAGS//maclike/}"
fi

# Matrix mode: run each profile combination in --check mode and exit
# Pass through --limit and -i so invocations like `./test.sh --matrix --limit ubuntu`
# actually reach the intended host instead of silently running against the default.
if $MATRIX_MODE; then
    for profile in developer core "core,rust" "core,iac" "core,gui_extras" "core,all" "core,openvpn" "developer,rust"; do
        echo "=== Matrix: --profile $profile ==="
        "$0" --profile "$profile" --check -i "$INVENTORY" $LIMIT $EXTRA_ARGS
    done
    exit 0
fi

# Default tags if none specified
if [[ -z "$TAGS" ]]; then
    TAGS="developer,base"
fi

# Check inventory exists
if [[ ! -f "$INVENTORY" ]]; then
    echo "[ERROR] Inventory file not found: $INVENTORY"
    echo "Create it with:"
    echo "  cat > /tmp/inventory_test.yml << 'EOF'"
    echo "  [fedora]"
    echo "  dfe-dev.tyrell.com.au ansible_user=dfe ansible_password=dfe ansible_become_password=dfe"
    echo ""
    echo "  [ubuntu]"
    echo "  dfe-dev-u.tyrell.com.au ansible_user=dfe ansible_password=dfe ansible_become_password=dfe"
    echo "  EOF"
    exit 1
fi

echo "[INFO] Running: ansible-playbook -i $INVENTORY playbooks/main.yml --tags $TAGS $LIMIT $EXTRA_ARGS"
echo ""

ansible-playbook \
    -i "$INVENTORY" \
    playbooks/main.yml \
    --tags "$TAGS" \
    $LIMIT \
    $EXTRA_ARGS
