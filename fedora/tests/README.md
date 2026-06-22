# Hyperi Installation Scripts - Test Suite

Simple test suite for the Hyperi Fedora installation scripts.

## Quick Start

```bash
# Run all tests
./run-tests.sh

# Run individual test types
bash 01-shellcheck.sh      # Static analysis
bats 02-syntax.bats         # Syntax checks
bats 03-lib-functions.bats  # Unit tests
bats 04-container.bats      # Container tests

# Clean up test artifacts
./cleanup.sh
```

## Test Types

1. **ShellCheck Static Analysis** (`01-shellcheck.sh`)
   - Catches common bash mistakes
   - No runtime needed
   - ~5 seconds

2. **Syntax Tests** (`02-syntax.bats`)
   - Verifies all scripts have valid bash syntax
   - Checks for shebangs and executability
   - ~5 seconds

3. **Library Function Tests** (`03-lib-functions.bats`)
   - Unit tests for lib.sh functions
   - Tests output, detection, and helper functions
   - ~10 seconds

4. **Container Tests** (`04-container.bats`)
   - Basic smoke tests in clean Fedora container
   - Requires Docker or Podman
   - ~30 seconds

## Dependencies

- **Required**: bash
- **Recommended**: ShellCheck, bats
- **Optional**: docker or podman (for container tests)

Install dependencies:
```bash
sudo dnf install -y ShellCheck bats
```

## Notes

- Tests are designed to be SIMPLE and FAST
- GUI components are not tested (too complex)
- Full installation tests are skipped (would take too long)
- Focus is on catching obvious errors early