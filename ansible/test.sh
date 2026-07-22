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
  Create with your own hosts (never commit real ones -- this repo is public):
    cat > /tmp/inventory_test.yml << 'INV'
    [fedora]
    fedora-box.example.internal ansible_user=YOU

    [ubuntu]
    ubuntu-box.example.internal ansible_user=YOU
    INV

  Prefer SSH keys. If a host genuinely needs a password, pass --ask-pass
  rather than writing one into the inventory.
EOF
    exit 0
}

# Parse arguments
WINLIKE_OVERRIDE=false

while [[ $# -gt 0 ]]; do
    case $1 in
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
            TAGS="rdp-server"
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

# Default tags if none specified
if [[ -z "$TAGS" ]]; then
    TAGS="developer,base"
fi

# Check inventory exists
if [[ ! -f "$INVENTORY" ]]; then
    echo "[ERROR] Inventory file not found: $INVENTORY"
    echo "Create it with your own hosts:"
    echo "  cat > /tmp/inventory_test.yml << 'EOF'"
    echo "  [fedora]"
    echo "  fedora-box.example.internal ansible_user=YOU"
    echo ""
    echo "  [ubuntu]"
    echo "  ubuntu-box.example.internal ansible_user=YOU"
    echo "  EOF"
    echo ""
    echo "Prefer SSH keys; use --ask-pass rather than passwords in the file."
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
