#!/usr/bin/env bats
# 04-container.bats - Test scripts in Docker/Podman containers

setup() {
    # Detect container runtime
    if command -v docker &>/dev/null; then
        export CONTAINER_CMD="docker"
    elif command -v podman &>/dev/null; then
        export CONTAINER_CMD="podman"
    else
        skip "No container runtime (docker/podman) available"
    fi

    # Change to parent directory
    cd "$(dirname "$BATS_TEST_DIRNAME")"
}

# Basic smoke tests - just verify scripts can load without errors
@test "lib.sh loads in Fedora container" {
    run $CONTAINER_CMD run --rm \
        -v "$(pwd):/scripts:Z" \
        fedora:latest \
        bash -c "cd /scripts && source lib.sh && echo 'lib.sh loaded successfully'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"lib.sh loaded successfully"* ]]
}

@test "lib.sh functions work in container" {
    run $CONTAINER_CMD run --rm \
        -v "$(pwd):/scripts:Z" \
        fedora:latest \
        bash -c "cd /scripts && source lib.sh && is_installed bash && echo 'PASS'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

@test "init_script function works in container" {
    run $CONTAINER_CMD run --rm \
        -v "$(pwd):/scripts:Z" \
        fedora:latest \
        bash -c 'cd /scripts && SCRIPT_DIR="." && source lib.sh && init_script "Test Script" 2>&1'
    [ "$status" -eq 0 ]
    [[ "$output" == *"Test Script"* ]]
}

@test "install scripts have valid syntax in container" {
    run $CONTAINER_CMD run --rm \
        -v "$(pwd):/scripts:Z" \
        fedora:latest \
        bash -c "cd /scripts && for script in install-*.sh; do bash -n \$script || exit 1; done && echo 'All scripts valid'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"All scripts valid"* ]]
}

# Test that scripts fail gracefully when not root
@test "install-hyperi-developer.sh requires root privileges" {
    skip "Scripts currently don't check for root - may add later"
}

# Test basic package detection works
@test "package detection functions work in container" {
    run $CONTAINER_CMD run --rm \
        -v "$(pwd):/scripts:Z" \
        fedora:latest \
        bash -c "cd /scripts && source lib.sh && is_package_installed bash && echo 'Detection works'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Detection works"* ]]
}

# Test OS detection in container
@test "OS detection works in Fedora container" {
    run $CONTAINER_CMD run --rm \
        -v "$(pwd):/scripts:Z" \
        fedora:latest \
        bash -c "cd /scripts && source lib.sh && is_fedora && echo 'Fedora detected'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Fedora detected"* ]]
}

# Test that require_distro works correctly
@test "require_distro enforces Fedora requirement" {
    run $CONTAINER_CMD run --rm \
        -v "$(pwd):/scripts:Z" \
        fedora:latest \
        bash -c "cd /scripts && source lib.sh && require_distro fedora 'Fedora Linux' && echo 'Requirement met'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Requirement met"* ]]
}

# Test container detection
@test "container detection works inside container" {
    run $CONTAINER_CMD run --rm \
        -v "$(pwd):/scripts:Z" \
        fedora:latest \
        bash -c "cd /scripts && source lib.sh && is_container && echo 'Container detected'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Container detected"* ]]
}

# Integration test - dry run to check early failures
@test "install-hyperi-developer.sh dry-run in container" {
    skip "Full installation test would take too long and requires sudo"
    # This would be the full test:
    # run $CONTAINER_CMD run --rm \
    #     -v "$(pwd):/scripts:ro" \
    #     --privileged \
    #     fedora:latest \
    #     bash -c "cd /scripts && sudo ./install-hyperi-developer.sh --dry-run"
    # [ "$status" -eq 0 ]
}