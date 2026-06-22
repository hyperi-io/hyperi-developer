#!/bin/bash
# run-tests.sh - Main test runner for Hyperi installation scripts
# Runs ShellCheck, BATS tests, and container tests

set -euo pipefail

# Get test directory
TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$TEST_DIR"

echo "============================================================================"
echo "  Hyperi Installation Scripts - Test Suite"
echo "============================================================================"

# Track overall results
TOTAL_TESTS=0
FAILED_TESTS=0

# Function to run a test and track results
run_test() {
    local test_name="$1"
    local test_file="$2"

    echo ""
    echo "Running: $test_name"
    echo "----------------------------------------------------------------------------"

    if [[ -f "$test_file" ]]; then
        ((TOTAL_TESTS++))
        if bash "$test_file"; then
            echo "[OK] $test_name passed"
        else
            echo "[FAIL] $test_name failed"
            ((FAILED_TESTS++))
        fi
    else
        echo "[SKIP] $test_file not found"
    fi
}

# Function to run BATS tests
run_bats() {
    local test_name="$1"
    local test_file="$2"

    echo ""
    echo "Running: $test_name"
    echo "----------------------------------------------------------------------------"

    if [[ -f "$test_file" ]]; then
        ((TOTAL_TESTS++))
        if bats "$test_file"; then
            echo "[OK] $test_name passed"
        else
            echo "[FAIL] $test_name failed"
            ((FAILED_TESTS++))
        fi
    else
        echo "[SKIP] $test_file not found"
    fi
}

# Check for required tools and offer to install
check_dependencies() {
    local missing=()

    command -v shellcheck &>/dev/null || missing+=("ShellCheck")
    command -v bats &>/dev/null || missing+=("bats")

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Missing test dependencies: ${missing[*]}"
        echo ""
        read -p "Would you like to install them now? [y/N]: " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "Installing test dependencies..."
            sudo dnf install -y ShellCheck bats
        else
            echo "Please install: sudo dnf install -y ShellCheck bats"
            echo "Some tests will be skipped."
        fi
    fi
}

# Main test execution
main() {
    # Check dependencies
    check_dependencies

    # 1. ShellCheck static analysis
    if command -v shellcheck &>/dev/null; then
        run_test "ShellCheck Static Analysis" "01-shellcheck.sh"
    else
        echo "[SKIP] ShellCheck not installed"
    fi

    # 2. BATS tests
    if command -v bats &>/dev/null; then
        run_bats "Syntax Tests" "02-syntax.bats"
        run_bats "Library Function Tests" "03-lib-functions.bats"

        # Container tests only if docker/podman available
        if command -v docker &>/dev/null || command -v podman &>/dev/null; then
            run_bats "Container Tests" "04-container.bats"
        else
            echo "[SKIP] Container tests - no docker/podman found"
        fi
    else
        echo "[SKIP] BATS not installed"
    fi

    # Summary
    echo ""
    echo "============================================================================"
    echo "  Test Summary"
    echo "============================================================================"
    echo "Total tests run: $TOTAL_TESTS"
    echo "Failed tests: $FAILED_TESTS"

    if [[ $FAILED_TESTS -eq 0 ]]; then
        echo ""
        echo "[OK] All tests passed!"
        exit 0
    else
        echo ""
        echo "[FAIL] $FAILED_TESTS test(s) failed"
        exit 1
    fi
}

# Run if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi