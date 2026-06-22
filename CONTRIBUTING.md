# Contributing to Hyperi Developer Environment

We welcome contributions from the community! This project follows standard Apache project guidelines.

## Table of Contents

- [How to Contribute](#how-to-contribute)
- [Code Standards](#code-standards)
- [Pull Request Guidelines](#pull-request-guidelines)
- [Development Workflow](#development-workflow)
- [Testing](#testing)
- [Reporting Issues](#reporting-issues)
- [Code of Conduct](#code-of-conduct)

## How to Contribute

### 1. Fork the Repository

```bash
# Fork via GitHub UI, then clone your fork
git clone https://github.com/YOUR-USERNAME/hyperi-developer
cd hyperi-developer
git remote add upstream https://github.com/hyperi-io/hyperi-developer
```

### 2. Create a Feature Branch

```bash
git checkout -b feature/your-feature-name
# Or for bug fixes
git checkout -b fix/issue-description
```

### 3. Make Your Changes

- Follow the KISS principle (Keep It Simple, Stupid)
- Use existing code style and conventions
- Run scripts as regular user with per-command sudo
- Test on a clean Fedora 42 system if possible
- Update documentation as needed

### 4. Test Your Changes

```bash
cd fedora/tests

# Static analysis (required)
./01-shellcheck.sh

# Syntax validation
bats 02-syntax.bats

# Unit tests
bats 03-lib-functions.bats

# Container tests (optional)
bats 04-container.bats
```

### 5. Commit Your Changes

Use conventional commit format:
- `feat:` - New features
- `fix:` - Bug fixes
- `docs:` - Documentation changes
- `chore:` - Maintenance tasks
- `refactor:` - Code refactoring
- `test:` - Test additions or fixes

```bash
git add .
git commit -m "feat: add support for Ubuntu 22.04"
```

**Important:**
- Write clear, concise commit messages
- No tool attribution in commit messages
- Reference issue numbers: `fix: resolve #123`

### 6. Push and Create Pull Request

```bash
git push origin feature/your-feature-name
```

Then create a PR via GitHub UI targeting the `main` branch.

## Code Standards

### Shell Script Guidelines

- **Shebang**: Always use `#!/bin/bash`
- **Error Handling**: Scripts must source lib.sh and use centralized error handling
- **Execution**: Run as regular user, use sudo only when needed
- **Idempotency**: Scripts must be safe to run multiple times
- **Library Functions**: Use lib.sh functions for consistency
  - `print_info()` - Informational messages
  - `print_error()` - Error messages
  - `print_warning()` - Warning messages
  - `print_success()` - Success messages

### Code Style

```bash
# Good - uses lib.sh functions
print_info "Installing package..."
sudo dnf install -y package-name

# Bad - direct echo
echo "Installing package..."
```

### File Operations

```bash
# Good - use pushd/popd
pushd /tmp >/dev/null || exit 1
# do work
popd >/dev/null || exit 1

# Bad - use cd
cd /tmp
# do work
cd -
```

### Version Detection

Always detect latest versions dynamically, never hardcode:

```bash
# Good - dynamic detection
CONFLUENT_VERSION=$(curl -sL https://packages.confluent.io/rpm/ 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | sort -V | tail -1)
if [ -z "$CONFLUENT_VERSION" ]; then
    print_warning "Could not detect latest version, using fallback"
    CONFLUENT_VERSION="8.1"
fi

# Bad - hardcoded version
CONFLUENT_VERSION="7.7"
```

### Character Policy

- **All Output**: ASCII only - no emojis or special Unicode characters
- **Console Output**: Plain text with standard symbols only
- **Log Files**: Plain ASCII only
- **Code Comments**: ASCII only
- **Commit Messages**: ASCII only

### Script Headers

All scripts must have a standardized header:

```bash
#!/bin/bash
# ============================================================================
# script-name - Brief Description
# ============================================================================
# Longer description of what the script does
#
# USAGE:
#   ./script-name.sh [options]
#
# INSTALLS/OPTIMIZES:
#   - Item 1
#   - Item 2
#
# NOTE: Important context or prerequisites
#
# LICENSE:
#   Licensed under the Apache License, Version 2.0
#   See ../LICENSE file for full license text
# ============================================================================
```

## Pull Request Guidelines

### Before Submitting

- [ ] All tests pass (ShellCheck and BATS)
- [ ] Code follows project style guidelines
- [ ] Documentation updated (README.md, STATE.md)
- [ ] CHANGELOG.md updated if applicable
- [ ] Commit messages follow conventional format
- [ ] No merge conflicts with main branch

### PR Description

Include:
1. **Summary**: What does this PR do?
2. **Motivation**: Why is this change needed?
3. **Testing**: How was it tested?
4. **Screenshots**: If UI changes
5. **Breaking Changes**: Clearly marked if any

### PR Size

- Keep PRs focused and reasonably sized
- Split large changes into multiple PRs
- One feature or fix per PR

### Review Process

1. Maintainers will review within 48 hours
2. Address review feedback promptly
3. Keep PR updated with main branch
4. Be respectful in discussions

## Development Workflow

### Setting Up Development Environment

```bash
# Clone and setup
git clone https://github.com/YOUR-USERNAME/hyperi-developer
cd hyperi-developer

# Keep your fork synced
git remote add upstream https://github.com/hyperi-io/hyperi-developer
git fetch upstream
git rebase upstream/main
```

### Making Changes

1. Check existing issues before starting work
2. Create an issue for discussion if needed
3. Create a feature branch
4. Make changes incrementally
5. Test frequently
6. Commit with clear messages

### Working with lib.sh

When adding functions to lib.sh:

1. Add function in appropriate section
2. Include error handling
3. Add BATS unit test in `tests/03-lib-functions.bats`
4. Document function in STATE.md

Example:

```bash
# In lib.sh
my_new_function() {
    local param="$1"
    if [ -z "$param" ]; then
        print_error "Parameter required"
        return 1
    fi
    # function logic
    return 0
}

# In tests/03-lib-functions.bats
@test "my_new_function works correctly" {
    run my_new_function "test"
    [ "$status" -eq 0 ]
}
```

## Testing

### Required Tests

All contributions must pass:

1. **ShellCheck**: Static analysis
   ```bash
   cd fedora/tests
   ./01-shellcheck.sh
   ```

2. **Syntax Tests**: Bash syntax validation
   ```bash
   bats 02-syntax.bats
   ```

3. **Unit Tests**: lib.sh function tests
   ```bash
   bats 03-lib-functions.bats
   ```

### Optional Tests

4. **Container Tests**: Integration tests
   ```bash
   bats 04-container.bats
   ```

### Test Coverage

- New functions must have corresponding unit tests
- Changes to existing functions require test updates
- Integration tests for installer scripts

### Manual Testing

**Test Systems:**

For HyperSec developers, test systems are available. See STATE.md (not public) for access details.

**Fedora (clean VM):**
```bash
# Reset Fedora test VM (fast - uses snapshot)
# Contact maintainers for test system access

# Test playbook:
ansible-playbook -i tests/fedora/inventory.yml playbooks/main.yml
```

**Ubuntu (clean VM):**
```bash
# Reset Ubuntu test VM (fast - uses snapshot)
# Contact maintainers for test system access

# Test playbook:
ansible-playbook -i tests/ubuntu/inventory.yml playbooks/main.yml
```

**macOS (clean system):**
```bash
# ⚠️ WARNING: Mac mini provisioning takes 20-30 minutes!
# Only reset when absolutely necessary (major changes, broken state)
# Use sparingly to avoid unnecessary costs and time
# Contact maintainers for test system access

# Reset Mac mini test system (SLOW - full OS install)
cd ansible
ansible-playbook -i tests/mac/inventory_scaleway.yml tests/provision_scaleway_mac.yml

# Test playbook:
ansible-playbook -i tests/mac/inventory_scaleway.yml playbooks/main.yml
```

**Legacy Fedora Shell Scripts:**
```bash
cd fedora

# Standard installation
./install-hyperi-developer.sh

# Core developer tools
./install-hyperi-developer-core.sh

# VM optimizations
./install-vm-optimizer.sh

# RDP optimizations
./install-rdp-optimizer.sh
```

## Reporting Issues

### Bug Reports

Use GitHub Issues and include:

1. **Fedora Version**: Output of `cat /etc/fedora-release`
2. **Script**: Which script(s) failed
3. **Error Output**: Full error messages and logs
4. **Steps to Reproduce**: Clear reproduction steps
5. **Expected Behavior**: What should have happened
6. **Actual Behavior**: What actually happened

### Feature Requests

Include:

1. **Use Case**: Why is this feature needed?
2. **Proposed Solution**: How should it work?
3. **Alternatives**: Other approaches considered
4. **Additional Context**: Relevant information

### Search First

- Check existing issues before creating new ones
- Comment on existing issues if you have the same problem
- Use issue templates when available

## Code of Conduct

### Our Standards

- Be respectful and professional
- Focus on technical merit
- Welcome newcomers and help them learn
- Provide constructive feedback
- Accept constructive criticism gracefully

### Unacceptable Behavior

- Harassment or discriminatory language
- Personal attacks or trolling
- Publishing others' private information
- Other conduct inappropriate in a professional setting

### Enforcement

Violations will result in:
1. Warning from maintainers
2. Temporary ban from project
3. Permanent ban for repeated violations

Report issues to project maintainers via GitHub Issues.

## Additional Resources

- [STATE.md](STATE.md) - Detailed project context and design decisions
- [README.md](README.md) - Project overview and quick start
- [CHANGELOG.md](CHANGELOG.md) - Version history
- [LICENSE](LICENSE) - Apache License 2.0 text

## Questions?

- Open a GitHub Issue for questions
- Check [STATE.md](STATE.md) for development context
- Review existing PRs for examples

Thank you for contributing to Hyperi Developer Environment!
