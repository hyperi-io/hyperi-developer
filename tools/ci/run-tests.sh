#!/usr/bin/env bash
#
# Test entry point, invoked as `npm test` by hyperi-ci's test stage.
#
# The repo is Ansible and shell, so the real checks are ansible-playbook,
# ansible-lint and shellcheck. Each is skipped when its tool is absent: the
# CI runner is a bare Node image, and a contributor who has not installed the
# Ansible toolchain should not get a red gate for it.
#
# The heavier suites are NOT here. molecule's existing-host scenario is
# delegated against a real workstation it deliberately mutates, and
# tests/proxmox needs a Proxmox endpoint -- neither is runnable unattended.
# See ansible/molecule/README.md and ansible/tests/README.md.
#
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

failures=0
ran=0

have() { command -v "$1" >/dev/null 2>&1; }

if have ansible-playbook; then
    ran=$((ran + 1))
    echo "==> ansible-playbook --syntax-check"
    # Run from ansible/: roles_path comes from ansible.cfg there, and without
    # it every `- role:` in the playbook fails to resolve.
    if (cd ansible && ansible-playbook --syntax-check \
        playbooks/main.yml \
        -i inventories/localhost/inventory.yml); then
        echo "    ok"
    else
        echo "    FAILED"
        failures=$((failures + 1))
    fi
else
    echo "--> ansible-playbook not installed, skipping syntax check"
fi

# Advisory only. The tree carries a backlog of findings, so a blocking
# ansible-lint would fail every run regardless of the change under test.
# Blocking it is the goal once that backlog is cleared.
if have ansible-lint; then
    ran=$((ran + 1))
    echo "==> ansible-lint (advisory)"
    (cd ansible && ansible-lint -f pep8 >/dev/null 2>&1) \
        && echo "    clean" \
        || echo "    findings present -- run 'cd ansible && ansible-lint' for detail"
else
    echo "--> ansible-lint not installed, skipping"
fi

if have shellcheck; then
    ran=$((ran + 1))
    echo "==> shellcheck"
    if shellcheck install.sh tools/ci/run-tests.sh tools/hyperi-doctor \
        ansible/roles/developer-rust/files/hyperi-rust-govern; then
        echo "    ok"
    else
        echo "    FAILED"
        failures=$((failures + 1))
    fi
else
    echo "--> shellcheck not installed, skipping"
fi

# hyperi-doctor is a thin wrapper over Python, so its real tests are pytest.
# Skipped without pytest or PyYAML so a bare Node runner stays green, the same
# bargain the Ansible checks above make.
if have python3 && python3 -c "import pytest, yaml" >/dev/null 2>&1; then
    ran=$((ran + 1))
    echo "==> pytest (tools)"
    if python3 -m pytest tools/tests -q; then
        echo "    ok"
    else
        echo "    FAILED"
        failures=$((failures + 1))
    fi
else
    echo "--> pytest or PyYAML not installed, skipping tools tests"
fi

# molecule/vars.yml is the SSoT for the supported releases, but molecule cannot
# include it and the OS gate restates it. Both copies are checked here rather
# than trusted to a comment.
if have python3 && python3 -c "import yaml" >/dev/null 2>&1; then
    ran=$((ran + 1))
    echo "==> supported release matrix"
    if python3 tools/check_release_matrix.py; then
        :
    else
        failures=$((failures + 1))
    fi
else
    echo "--> PyYAML not installed, skipping the release matrix check"
fi

# Ansible resolves a copy: src: against the current role only, so a file left
# behind by a task move breaks at run time on the host, partway through a real
# install. Pure stdlib, so it runs wherever python3 does.
if have python3; then
    ran=$((ran + 1))
    echo "==> role file references"
    if python3 tools/check_role_file_refs.py; then
        :
    else
        failures=$((failures + 1))
    fi
else
    echo "--> python3 not installed, skipping the role file reference check"
fi

if [ "$ran" -eq 0 ]; then
    echo "No test tooling present on this runner -- nothing exercised."
fi

if [ "$failures" -gt 0 ]; then
    echo "$failures check(s) failed."
    exit 1
fi

echo "All available checks passed."
