# Contributing to HyperI Developer Environment

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
- Match the existing code style and conventions in the file you are editing
- Ansible tasks must be idempotent - run twice and the second run is all green
- Run the playbook as a regular user with per-command sudo
- Update documentation as needed

### 4. Test Your Changes

This project is Ansible-first. From `ansible/`:

```bash
# Lint + syntax (required)
ansible-lint
ansible-playbook --syntax-check playbooks/main.yml -i inventories/localhost/inventory.yml

# Shell scripts (required if you touched any)
shellcheck ../install.sh

# Container matrix - clean install on Ubuntu + Fedora, current and n-1 (no hosts needed)
molecule test -s matrix
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

- **Shebang**: `#!/bin/bash`, with `set -euo pipefail` at the top
- **Portability**: the bootstrap `install.sh` must run on macOS's Bash 3.2 (it
  runs before any newer bash is installed) - no Bash 4+ features there
- **Error Handling**: check command results and clean up temp files on exit (trap)
- **Execution**: run as a regular user, use sudo only when needed
- **Idempotency**: safe to run multiple times
- **Output helpers**: each script defines its own `print_info` / `print_error` /
  `print_warning` / `print_success` (see `install.sh`) - there is no shared `lib.sh`
- **shellcheck clean**: silence a genuine false positive with a scoped
  `# shellcheck disable=` plus a reason, never blanket-disable

### Code Style

```bash
# Good - uses the script's print helpers
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

- [ ] ansible-lint + `--syntax-check` clean, shellcheck clean on any shell touched
- [ ] molecule matrix passes for playbook changes
- [ ] Code follows project style guidelines
- [ ] Documentation updated (README.md)
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

### Adding or changing an Ansible role

1. Put the task in the right role: generic dev tooling in `developer` (or a
   `developer-<lang>` / `developer-gui` sibling), IaC/cloud in `infrastructure`,
   HyperI-only policy in `soe` / `soe-gui`, the CI toolchain in `contributor`.
2. Tag it so it can be selected on its own (`./install.sh --list-apps` lists every tag).
3. Make it idempotent, and guard by platform with
   `when: ansible_facts['distribution'] == ...`.
4. If you DROP a tool, add a tombstone in `developer/tasks/removals.yml` in the
   same change - Ansible cannot prune what you stop declaring.
5. For an optional upstream download, wrap it in `block:`/`rescue:` that records
   into `deploy_warnings`, so one dead upstream does not abort the whole run
   (see `docs/resilient-deploy.md`).

## Testing

The test suite needs no HyperI infrastructure. Run everything from `ansible/`.

### Required

1. **Lint + syntax**
   ```bash
   ansible-lint
   ansible-playbook --syntax-check playbooks/main.yml -i inventories/localhost/inventory.yml
   ```

2. **shellcheck** on any shell script you changed
   ```bash
   shellcheck ../install.sh
   ```

3. **Container matrix** - a clean install on Ubuntu + Fedora, current and n-1,
   in Docker (no VMs, no cloud):
   ```bash
   molecule test -s matrix
   ```
   Other scenarios: `existing-host` (convergence on a long-lived box) and
   `remediation` (an old host converges to current).

### Optional

- **The self-updater**, across the same container matrix:
  ```bash
  tests/update/test-hyperi-update.sh
  ```
- **A real VM**: `tests/proxmox/` resets Fedora/Ubuntu VMs from a snapshot and
  runs the playbook. Every host and secret is read from `.env` via
  `lookup('env', ...)` - copy `tests/.env.sample` to `tests/.env` and fill it
  in. Nothing internal is ever committed.

### Manual testing

Run the playbook straight on a throwaway machine or VM:

```bash
./install.sh --check     # dry run first
./install.sh             # the default lightweight base
```

macOS is tested by running `./install.sh` on the Mac itself.

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

- `./install.sh --list-apps` - the full role and tag list
- [README.md](README.md) - Project overview and quick start
- [CHANGELOG.md](CHANGELOG.md) - Version history
- [LICENSE](LICENSE) - Apache License 2.0 text

## Questions?

- Open a GitHub Issue for questions
- Run `./install.sh --list-apps` for the role and tag list
- Review existing PRs for examples

Thank you for contributing to Hyperi Developer Environment!
