#!/bin/bash
# cleanup.sh - Clean up test artifacts

echo "Cleaning up test artifacts..."

# Detect container runtime
if command -v docker &>/dev/null; then
    CONTAINER_CMD="docker"
elif command -v podman &>/dev/null; then
    CONTAINER_CMD="podman"
else
    echo "[INFO] No container runtime found - skipping container cleanup"
    exit 0
fi

# Remove any test containers
echo "Removing test containers..."
$CONTAINER_CMD ps -aq --filter "name=hyperi-test" 2>/dev/null | xargs -r $CONTAINER_CMD rm -f 2>/dev/null || true
$CONTAINER_CMD ps -aq --filter "name=bats-test" 2>/dev/null | xargs -r $CONTAINER_CMD rm -f 2>/dev/null || true

# Remove any test images
echo "Removing test images..."
$CONTAINER_CMD images -q "hyperi-test*" 2>/dev/null | xargs -r $CONTAINER_CMD rmi -f 2>/dev/null || true

# Clean up temp files
echo "Cleaning temporary files..."
rm -f /tmp/bats-test-*.txt 2>/dev/null || true
rm -rf /tmp/bats-test-*/ 2>/dev/null || true

# Prune system (optional - only if explicitly requested)
if [[ "$1" == "--prune" ]]; then
    echo "Pruning container system..."
    $CONTAINER_CMD system prune -f 2>/dev/null || true
fi

echo "[OK] Cleanup complete"