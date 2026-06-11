# Role Structure Refactor — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor Ansible roles into a two-tier base (`developer` + `core`) with composable add-on profiles (`rust`, `iac`, `gui_extras`, `openvpn`), add opt-out vars, switch VPN default to WireGuard, and ship a tool-rationale doc.

**Architecture:** Existing roles `developer` and `developer_core` collapse into a new layout: `developer` (OSS-safe), `core` (Hyperi internal, implies `developer`), plus profile roles. Profiles gate on Ansible tags set by a new `install.sh --profile` flag. Opt-outs use `install_<name>` variables with sensible defaults in `group_vars/all.yml`.

**Tech Stack:** Bash (install.sh), Ansible (roles/playbooks), bats (shell unit tests), Python (OSS-safe assertion helper).

**Spec:** `docs/plans/2026-04-18-role-structure-refactor-design.md`

**Execution discipline:**
- Follow superpowers:test-driven-development — tests first, run failing, implement, run passing, commit.
- Follow superpowers:verification-before-completion — prove each step works before moving on.
- Frequent commits. Each task ends with a commit.
- Each chunk ends with a full syntax-check + `test.sh --check` matrix run.

---

## Chunk 1: Scaffolding + `install.sh --profile` interface

Goal: land the user-facing `--profile` flag, empty role skeletons, and an updated playbook — with zero behaviour change for existing installs (backward-compat aliases preserved). All subsequent chunks populate the empty shells.

### Task 1.1: Create feature branch

**Files:**
- None (git state only)

- [ ] **Step 1: Create and switch to the refactor branch**

```bash
cd /projects/dfe-developer
git checkout main
git pull
git checkout -b feat/role-structure-refactor
```

Expected: clean working tree on new branch.

- [ ] **Step 2: Verify starting state**

```bash
git status
git log --oneline -3
```

Expected: branch tracks main, no uncommitted files.

### Task 1.2: Add bats test dependency and test scaffolding

**Files:**
- Create: `tests/bats/install_profile.bats`
- Create: `tests/bats/helpers.bash`
- Create: `tests/bats/README.md`

Context: install.sh gets a new `--profile` flag with validation rules that need to be covered by tests *before* we implement. We use `bats-core` (standard, widely packaged, minimal). If bats isn't installed, the test script installs it via the test helper.

- [ ] **Step 0 (preflight): Install bats if missing**

```bash
command -v bats || {
    case "$(. /etc/os-release && echo "$ID")" in
        ubuntu) sudo apt-get install -y bats ;;
        fedora) sudo dnf install -y bats ;;
        *) echo "Install bats manually for your distro"; exit 1 ;;
    esac
}
```

- [ ] **Step 1: Write the test helper**

```bash
# tests/bats/helpers.bash
#!/usr/bin/env bash

# Locate the script under test
INSTALL_SH="${BATS_TEST_DIRNAME}/../../install.sh"

# Dry-run the profile parser only (exits before Ansible invocation)
# Requires install.sh to honour DFE_PROFILE_TEST=1 as a short-circuit.
profile_parse() {
    DFE_PROFILE_TEST=1 bash "$INSTALL_SH" "$@" 2>&1
}
```

- [ ] **Step 2: Write failing tests for `--profile` parsing**

```bash
# tests/bats/install_profile.bats
#!/usr/bin/env bats
#
# install.sh --profile tests.
#
# Canonical output order (deterministic): developer, core, rust, iac, gui_extras, openvpn.
# Dedup rules: --profile developer,core → developer,core (not developer,developer,core).
# Implicit rules:
#   - "core" implies "developer"
#   - "openvpn" requires "core" (hard error without it)
#   - "all" expands to rust,iac,gui_extras (no openvpn)

load helpers

@test "--profile developer sets base tier to developer" {
    run profile_parse --profile developer
    [ "$status" -eq 0 ]
    [[ "$output" == *"RESOLVED_TAGS=developer"* ]]
}

@test "--profile core includes developer tier (implicit dependency)" {
    run profile_parse --profile core
    [ "$status" -eq 0 ]
    [[ "$output" == *"RESOLVED_TAGS=developer,core"* ]]
}

@test "--profile core,rust includes developer,core,rust" {
    run profile_parse --profile core,rust
    [ "$status" -eq 0 ]
    [[ "$output" == *"RESOLVED_TAGS=developer,core,rust"* ]]
}

@test "--profile all expands to developer,rust,iac,gui_extras (no openvpn, default developer base)" {
    run profile_parse --profile all
    [ "$status" -eq 0 ]
    [[ "$output" == *"RESOLVED_TAGS=developer,rust,iac,gui_extras"* ]]
}

@test "--profile core,all expands to developer,core,rust,iac,gui_extras" {
    run profile_parse --profile core,all
    [ "$status" -eq 0 ]
    [[ "$output" == *"RESOLVED_TAGS=developer,core,rust,iac,gui_extras"* ]]
}

@test "--profile openvpn alone is a hard error (requires core)" {
    run profile_parse --profile openvpn
    [ "$status" -ne 0 ]
    [[ "$output" == *"--profile openvpn requires --profile core"* ]]
}

@test "--profile core,openvpn is valid" {
    run profile_parse --profile core,openvpn
    [ "$status" -eq 0 ]
    [[ "$output" == *"RESOLVED_TAGS=developer,core,openvpn"* ]]
}

@test "--profile rust alone defaults base to developer" {
    run profile_parse --profile rust
    [ "$status" -eq 0 ]
    [[ "$output" == *"RESOLVED_TAGS=developer,rust"* ]]
}

@test "--profile developer,core dedupes to core" {
    run profile_parse --profile developer,core
    [ "$status" -eq 0 ]
    [[ "$output" == *"RESOLVED_TAGS=developer,core"* ]]
}

@test "unknown profile name is rejected" {
    run profile_parse --profile frobnicate
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown profile: frobnicate"* ]]
}

@test "--core (legacy) warns and aliases to --profile core,rust,iac" {
    run profile_parse --core
    [ "$status" -eq 0 ]
    [[ "$output" == *"[WARN]"* ]]
    [[ "$output" == *"deprecated"* ]]
    [[ "$output" == *"RESOLVED_TAGS=developer,core,rust,iac"* ]]
}

@test "--all (legacy) warns and aliases to --profile core,all" {
    run profile_parse --all
    [ "$status" -eq 0 ]
    [[ "$output" == *"[WARN]"* ]]
    [[ "$output" == *"deprecated"* ]]
    [[ "$output" == *"RESOLVED_TAGS=developer,core,rust,iac,gui_extras"* ]]
}

@test "no --profile defaults to developer only" {
    run profile_parse
    [ "$status" -eq 0 ]
    [[ "$output" == *"RESOLVED_TAGS=developer"* ]]
}
```

- [ ] **Step 3: Write the bats README**

```markdown
<!-- tests/bats/README.md -->
# Bats tests

Shell-level unit tests for `install.sh` and related bash logic. Run via:

    sudo apt-get install bats        # Ubuntu
    sudo dnf install bats            # Fedora
    bats tests/bats/                 # run all

The tests short-circuit install.sh's Ansible invocation by setting
`DFE_PROFILE_TEST=1`. When set, install.sh prints `RESOLVED_TAGS=...`
and exits before touching the system.
```

- [ ] **Step 4: Run tests to confirm they fail (no `--profile` yet)**

```bash
bats tests/bats/install_profile.bats
```

Expected: all tests FAIL because `--profile` isn't implemented.

- [ ] **Step 5: Commit tests**

```bash
git add tests/bats/
git commit -m "test(install): add bats tests for --profile parsing and aliases"
```

### Task 1.3: Implement `--profile` in install.sh

**Files:**
- Modify: `install.sh` (argument parsing block, ~lines 129-185)

- [ ] **Step 1: Add profile-definition map at the top of install.sh**

Insert after the existing color/output function block (around line 45):

```bash
# ----- Profile definitions -----
# Each profile resolves to a set of Ansible tags.
# Invariants (enforced in parse_profile):
#   - "core" implies "developer"
#   - "openvpn" requires "core" (Hyperi-specific config)
#   - "all" expands to rust,iac,gui_extras (on top of whatever base tier is selected)
declare -A VALID_PROFILES=(
    [developer]="developer"
    [core]="core"
    [rust]="rust"
    [iac]="iac"
    [gui_extras]="gui_extras"
    [openvpn]="openvpn"
    [all]="rust,iac,gui_extras"
)
```

- [ ] **Step 2: Add the profile parser function**

Insert before the argument parsing loop:

```bash
# Resolve --profile input into a canonical ordered tag list.
# Enforces validation rules and prints helpful errors.
# Sets global RESOLVED_TAGS (comma-separated).
parse_profile() {
    local input="$1"
    local -A selected
    local p
    IFS=',' read -ra profiles <<< "$input"
    for p in "${profiles[@]}"; do
        p="${p//[[:space:]]/}"
        [[ -z "$p" ]] && continue
        if [[ -z "${VALID_PROFILES[$p]+x}" ]]; then
            print_error "Unknown profile: $p"
            echo "Valid profiles: developer, core, rust, iac, gui_extras, openvpn, all"
            exit 1
        fi
        # Expand "all" into its components
        if [[ "$p" == "all" ]]; then
            local expanded
            IFS=',' read -ra expanded <<< "${VALID_PROFILES[all]}"
            local e
            for e in "${expanded[@]}"; do selected[$e]=1; done
        else
            selected[$p]=1
        fi
    done

    # Rule: openvpn requires core
    if [[ -n "${selected[openvpn]:-}" && -z "${selected[core]:-}" ]]; then
        print_error "--profile openvpn requires --profile core (OpenVPN config is Hyperi-specific)"
        exit 1
    fi

    # Rule: core implies developer
    if [[ -n "${selected[core]:-}" ]]; then
        selected[developer]=1
    fi

    # If nothing selected, default to developer
    if [[ ${#selected[@]} -eq 0 ]]; then
        selected[developer]=1
    fi

    # Canonical order: developer, core, rust, iac, gui_extras, openvpn
    local -a ordered=()
    local name
    for name in developer core rust iac gui_extras openvpn; do
        [[ -n "${selected[$name]:-}" ]] && ordered+=("$name")
    done
    RESOLVED_TAGS=$(IFS=','; echo "${ordered[*]}")
}
```

- [ ] **Step 3: Wire `--profile` into the argument parser**

Add a new case arm to the `while [[ $# -gt 0 ]]` loop:

```bash
        --profile)
            PROFILE_INPUT="$2"
            shift 2
            ;;
```

- [ ] **Step 4: Update legacy `--core` and `--all` arms to emit deprecation warnings and delegate**

Replace the existing `--core)` and `--all)` arms with:

```bash
        --core)
            print_warning "--core is deprecated; use --profile core,rust,iac instead"
            PROFILE_INPUT="core,rust,iac"
            shift
            ;;
        --all)
            print_warning "--all is deprecated; use --profile core,all instead"
            PROFILE_INPUT="core,all"
            shift
            ;;
```

- [ ] **Step 5: After the parse loop, resolve profile → tags**

**CRITICAL placement:** insert this block IMMEDIATELY after the `while [[ $# -gt 0 ]]` loop closes (line 185) and BEFORE the existing winlike/maclike priority block (line 187) and the `--region` block (line 196). The region block appends its tag to `ANSIBLE_TAGS`; if it runs first on a missing `ANSIBLE_TAGS`, it creates a tags-`region`-only install that loses the profile.

```bash
# ---- Resolve --profile input into Ansible tags ----
# (Must run before winlike/maclike and region blocks — both append to ANSIBLE_TAGS.)
if [[ -n "${PROFILE_INPUT:-}" ]]; then
    parse_profile "$PROFILE_INPUT"
    if [[ -n "$ANSIBLE_TAGS" ]]; then
        print_warning "Both --profile and --tags given; --profile wins"
    fi
    ANSIBLE_TAGS="--tags $RESOLVED_TAGS"
elif [[ -z "$ANSIBLE_TAGS" ]]; then
    # No profile and no tags: default to developer
    parse_profile "developer"
    ANSIBLE_TAGS="--tags $RESOLVED_TAGS"
fi

# Short-circuit for bats tests: print resolved tags and exit before invoking Ansible.
if [[ "${DFE_PROFILE_TEST:-}" == "1" ]]; then
    echo "RESOLVED_TAGS=${RESOLVED_TAGS}"
    exit 0
fi
```

**Note on bash version:** `parse_profile` uses associative arrays (`declare -A`) which require bash 4+. install.sh already uses bash arrays elsewhere; on macOS the user is expected to have installed `bash` via Homebrew (stock macOS bash is 3.2). This is an existing precondition, not a new one.

- [ ] **Step 6: Update the help text in `show_help()`**

Replace the existing OPTIONS/EXAMPLES blocks in `show_help()` with:

```
OPTIONS:
  --check              Run in check mode (dry-run, no changes)
  --profile PROFILE    Profiles to install (comma-separated). See below.
  --tags TAGS          Ad-hoc Ansible tags (overrides --profile if both given)
  --tags-exclude TAGS  Exclude specific tags (comma-separated)
  --branch BRANCH      Git branch to use (default: main)
  --region REGION      Apply regional settings (e.g. au, en_AU.UTF-8)
  --help               Show this help message

  DEPRECATED (still works, will be removed in next release):
    --core             Alias for --profile core,rust,iac
    --all              Alias for --profile core,all

PROFILES:
  developer       OSS-safe base for external contributors on DFE/ESH.
                  Installs: git, docker, Python (uv), aws/azure/gcloud/gh,
                  vscode, browsers, utilities, CI tooling.
  core            Hyperi internal tier (implies developer). Adds:
                  Slack, Linear CLI, JFrog CLI, WireGuard, Hyperi branding.
  rust            Rust toolchain + cargo-installed dev tools (sccache, mold, etc.)
  iac             Infrastructure-as-code (Terraform, Vault, Helm, k8s CLI set)
  gui_extras      Optional GUI/TUI extras: Freelens, Bruno, Podman Desktop,
                  DBeaver Community, lazygit
  openvpn         Transitional legacy VPN (requires core). Will be removed
                  once WireGuard migration completes (~2026-06).
  all             Shortcut for rust,iac,gui_extras (applied to whichever
                  base tier you selected; defaults to developer)

EXAMPLES:
  ./install.sh --profile developer          # external contributor
  ./install.sh --profile core               # Hyperi dev (minimal)
  ./install.sh --profile core,rust          # Hyperi + Rust
  ./install.sh --profile core,all           # Hyperi + everything (no openvpn)
  ./install.sh --profile core,openvpn       # Hyperi + legacy VPN
  ./install.sh --profile core --extra-vars install_slack=false
```

- [ ] **Step 7: Re-run bats tests**

```bash
bats tests/bats/install_profile.bats
```

Expected: **all 13 tests PASS**.

- [ ] **Step 8: Commit install.sh changes**

```bash
git add install.sh
git commit -m "feat(install): add --profile with validation, alias --core/--all"
```

### Task 1.4: Create empty role skeletons

**Files:**
- Create: `ansible/roles/core/{tasks/main.yml,meta/main.yml}`
- Create: `ansible/roles/rust/{tasks/main.yml,meta/main.yml}`
- Create: `ansible/roles/iac/{tasks/main.yml,meta/main.yml}`
- Create: `ansible/roles/gui_extras/{tasks/main.yml,meta/main.yml}`
- Create: `ansible/roles/openvpn/{tasks/main.yml,meta/main.yml}`

- [ ] **Step 1: Create directory structure**

```bash
cd /projects/dfe-developer/ansible/roles
for r in core rust iac gui_extras openvpn; do
    mkdir -p "$r/tasks" "$r/meta"
done
```

- [ ] **Step 2: Write meta/main.yml for each (copy from developer_core/meta/main.yml as template, adjust the `role_name`)**

For each role, write `meta/main.yml`:

```yaml
---
galaxy_info:
  role_name: <ROLE_NAME>   # core | rust | iac | gui_extras | openvpn
  author: Derek Thoms
  description: <ONE_LINE_DESCRIPTION>
  license: Apache-2.0
  min_ansible_version: "2.20"
  platforms:
    - name: Fedora
      versions: ['42']
    - name: Ubuntu
      versions: ['noble']
dependencies: []
```

Role-specific descriptions:
- `core`: "Hyperi internal tier — comms, creds, VPN, branding"
- `rust`: "Rust toolchain and cargo-installed developer tools"
- `iac`: "Infrastructure-as-code and Kubernetes operator tooling"
- `gui_extras`: "Optional GUI/TUI extras (Freelens, Bruno, Podman Desktop, DBeaver, lazygit)"
- `openvpn`: "Legacy OpenVPN 3 stack (transitional — removal scheduled post-WireGuard migration)"

- [ ] **Step 3: Write placeholder tasks/main.yml for each**

Each skeleton declares the canonical profile tag and a sanity-check task that logs the role being entered. This keeps the check-mode matrix meaningful even before chunks 2-3 populate the roles.

```yaml
---
# <ROLE_NAME> role — to be populated in later chunks

- name: Entering <ROLE_NAME> role (skeleton)
  ansible.builtin.debug:
    msg: "<ROLE_NAME> role placeholder — populated by chunks 2-3"
```

- [ ] **Step 4: Commit role skeletons**

```bash
git add ansible/roles/core ansible/roles/rust ansible/roles/iac ansible/roles/gui_extras ansible/roles/openvpn
git commit -m "feat(roles): scaffold core, rust, iac, gui_extras, openvpn skeletons"
```

### Task 1.5: Wire new roles into the playbook

**Files:**
- Modify: `ansible/playbooks/main.yml` (roles block, around lines 148-167)

- [ ] **Step 1: Replace the existing `roles:` block with the new tiered layout**

```yaml
  roles:
    - role: developer
      become: "{{ ansible_facts['distribution'] != 'MacOSX' }}"
      tags: ['developer', 'base']    # 'base' kept as alias for backward compat

    - role: core
      become: "{{ ansible_facts['distribution'] != 'MacOSX' }}"
      tags: ['core']

    - role: rust
      become: "{{ ansible_facts['distribution'] != 'MacOSX' }}"
      tags: ['rust']

    - role: iac
      become: "{{ ansible_facts['distribution'] != 'MacOSX' }}"
      tags: ['iac']

    - role: gui_extras
      become: "{{ ansible_facts['distribution'] != 'MacOSX' }}"
      tags: ['gui_extras']

    - role: openvpn
      become: "{{ ansible_facts['distribution'] != 'MacOSX' }}"
      tags: ['openvpn']

    - role: vm_optimizer
      become: "{{ ansible_facts['distribution'] != 'MacOSX' }}"
      tags: ['vm', 'optimizer']

    - role: rdp
      become: "{{ ansible_facts['distribution'] != 'MacOSX' }}"
      tags: ['rdp']

    - role: system_cleanup
      become: "{{ ansible_facts['distribution'] != 'MacOSX' }}"
      tags: ['always']
```

**Critical:** `developer_core` is NOT in this list. Its contents are redistributed in Chunks 2-3; the role directory itself is deleted in Chunk 3.

- [ ] **Step 2: Syntax-check the playbook**

```bash
cd /projects/dfe-developer/ansible
ansible-playbook --syntax-check playbooks/main.yml -i inventories/localhost/inventory.yml
```

Expected: `playbook: playbooks/main.yml` — no syntax errors.

- [ ] **Step 3: Smoke test with check-mode `--profile developer`**

```bash
cd /projects/dfe-developer
./install.sh --check --profile developer 2>&1 | tail -30
```

Expected: Ansible runs developer role plus skeletons for core/rust/iac/gui_extras/openvpn — only developer-tagged tasks execute (skeletons are tag-gated, so they'll be skipped when their tag isn't selected).

**Note for the implementer:** The skeleton `debug` task has no tag, so it inherits the role's tag. Confirm by running `./install.sh --check --profile all` and checking that all five skeletons fire their debug messages.

- [ ] **Step 4: Commit playbook changes**

```bash
git add ansible/playbooks/main.yml
git commit -m "feat(playbook): add tiered role layout (developer, core, + profiles)"
```

### Task 1.6: Update `test.sh` with profile matrix

**Files:**
- Modify: `ansible/test.sh`

- [ ] **Step 1: Add `--profile` option to test.sh**

Replace the legacy `--all`/`--core` cases with a `--profile` case that mirrors install.sh:

```bash
        --profile)
            TAGS="$2"
            # Expand profile tokens to tag list (mirrors install.sh logic)
            case "$2" in
                *all*) TAGS="${TAGS//all/rust,iac,gui_extras}" ;;
            esac
            if [[ "$TAGS" == *core* && "$TAGS" != *developer* ]]; then
                TAGS="developer,$TAGS"
            fi
            shift 2
            ;;
```

**Note:** test.sh's profile parser is simplified (it's a test helper, not the production entry point). For the full validation rules, tests run against install.sh via bats.

- [ ] **Step 2: Add a matrix wrapper at the end of test.sh**

```bash
# Allow `./test.sh --matrix` to run check-mode against every profile combo
if [[ "${1:-}" == "--matrix" ]]; then
    shift
    for profile in developer core "core,rust" "core,iac" "core,gui_extras" "core,all" "core,openvpn" "developer,rust"; do
        echo "=== Matrix: --profile $profile ==="
        "$0" --profile "$profile" --check "$@"
    done
    exit 0
fi
```

- [ ] **Step 3: Run the matrix in check-mode to validate everything includes cleanly**

```bash
cd /projects/dfe-developer/ansible
./test.sh --matrix --limit ubuntu
```

Expected: all 8 profile combos complete with 0 failed tasks (skeletons being hit is OK).

- [ ] **Step 4: Commit test.sh changes**

```bash
git add ansible/test.sh
git commit -m "test(matrix): add --profile option and --matrix check-mode runner"
```

### Chunk 1 checkpoint

- [ ] **Re-run full chunk 1 verification**

```bash
# Syntax
ansible-playbook --syntax-check ansible/playbooks/main.yml -i ansible/inventories/localhost/inventory.yml
# Bats
bats tests/bats/install_profile.bats
# Matrix
cd ansible && ./test.sh --matrix --limit ubuntu
```

All three must pass. Then merge-ready for review.

---

## Chunk 2: Extract profile roles (rust, iac, openvpn, gui_extras)

Goal: move tool installation from `developer_core`/`developer` into the new profile roles. After this chunk, the profile roles are functional; `developer_core` still exists but is shrinking.

### Task 2.1: Populate `rust` role

**Files:**
- Move: `ansible/roles/developer_core/tasks/rust.yml` → `ansible/roles/rust/tasks/rust.yml`
- Modify: `ansible/roles/rust/tasks/main.yml` (replace skeleton)
- Modify: `ansible/roles/developer_core/tasks/main.yml` (remove rust include)
- Modify: `ansible/roles/developer_core/tasks/verify.yml` (remove rust verify lines)

- [ ] **Step 1: Move rust.yml into the new role**

```bash
git mv ansible/roles/developer_core/tasks/rust.yml ansible/roles/rust/tasks/rust.yml
```

- [ ] **Step 2: Update rust role main.yml**

Replace skeleton content with:

```yaml
---
# Rust toolchain + cargo tools

- name: Install Rust and cargo tools
  ansible.builtin.include_tasks:
    file: rust.yml
```

- [ ] **Step 3: Remove rust from developer_core main.yml**

Delete the block starting `- name: Install Rust and cargo tools` (about 4 lines, up to and including the `tags: ['rust']` line). Pattern-based deletion is safer than line numbers, which drift with edits. Leave verify.yml changes for Step 4.

- [ ] **Step 4: Move Rust-specific verify blocks**

Create `ansible/roles/rust/tasks/verify.yml`. Move these verify blocks from `developer_core/tasks/verify.yml` into it:
- Verify Rust (Linux + macOS)
- Verify cargo-bacon, cargo-nextest, cargo-deny, cargo-tarpaulin, cargo-chef

Add at the end of `ansible/roles/rust/tasks/main.yml`:

```yaml
- name: Verify Rust toolchain
  ansible.builtin.include_tasks:
    file: verify.yml
  tags: ['verify']
```

Remove the corresponding blocks from `developer_core/tasks/verify.yml`.

- [ ] **Step 5: Check-mode test**

```bash
cd /projects/dfe-developer
./install.sh --check --profile rust 2>&1 | grep -E "rust|cargo"
```

Expected: output includes rust task names ("Install Rust and cargo tools").

- [ ] **Step 6: Commit**

```bash
git add ansible/roles/rust ansible/roles/developer_core/tasks/main.yml ansible/roles/developer_core/tasks/verify.yml
git commit -m "refactor(rust): extract rust.yml from developer_core into rust role"
```

### Task 2.2: Populate `iac` role (Hashicorp + Kubernetes + dive)

**Files:**
- Split: `ansible/roles/developer/tasks/cloud.yml` → `ansible/roles/developer/tasks/cloud.yml` (aws+gh only) + `ansible/roles/iac/tasks/hashicorp.yml` (terraform+vault+helm)
- Move: `ansible/roles/developer/tasks/k8s.yml` → `ansible/roles/iac/tasks/k8s.yml` (minus Freelens block)
- Modify: `ansible/roles/iac/tasks/main.yml` (replace skeleton)
- Modify: `ansible/roles/developer/tasks/main.yml` (remove k8s/cloud-hashicorp includes)

- [ ] **Step 1: Split cloud.yml**

First list all the top-level task names so the boundaries are explicit:

```bash
grep -n '^- name:' ansible/roles/developer/tasks/cloud.yml
```

Expected tasks to **move** to `ansible/roles/iac/tasks/hashicorp.yml`:
- All HashiCorp GPG key / repo configuration blocks (Ubuntu + Fedora)
- `Install Terraform`
- `Install Vault`
- `Install Helm` (if present)

Expected tasks to **keep** in `ansible/roles/developer/tasks/cloud.yml`:
- `Install AWS CLI v2` (Linux)
- Any `gh` CLI installation blocks
- Any macOS-specific aws/gh blocks

Copy the HashiCorp blocks to the new file, delete them from cloud.yml. Verify no blocks straddle the cut.

After the split, both files should syntax-check cleanly:

```bash
ansible-playbook --syntax-check ansible/playbooks/main.yml -i ansible/inventories/localhost/inventory.yml
```

- [ ] **Step 2: Move k8s.yml (minus Freelens) into iac**

```bash
git mv ansible/roles/developer/tasks/k8s.yml ansible/roles/iac/tasks/k8s.yml
```

Edit the new `iac/tasks/k8s.yml` and remove the Freelens installation block — Freelens moves to `gui_extras` in Task 2.4. Leave `dive` (it stays in iac).

- [ ] **Step 3: Update iac role main.yml**

```yaml
---
# Infrastructure-as-code + Kubernetes tooling

- name: Install HashiCorp tooling (Terraform, Vault, Helm)
  ansible.builtin.include_tasks:
    file: hashicorp.yml

- name: Install Kubernetes tooling
  ansible.builtin.include_tasks:
    file: k8s.yml
```

- [ ] **Step 4: Remove k8s include from developer role**

In `ansible/roles/developer/tasks/main.yml`:
- Delete the block starting `- name: Install Kubernetes tools` (pattern-based; spans to its `tags:` line).

- [ ] **Step 4b: Confirm the "Install cloud tools" include stays**

The cloud include remains — it now loads a slimmer cloud.yml (aws + gh only). Verify the block starting `- name: Install cloud tools` is still present in `developer/tasks/main.yml`; no change needed there.

- [ ] **Step 5: Check-mode tests**

```bash
./install.sh --check --profile iac 2>&1 | grep -iE "terraform|kubectl|vault|helm"
./install.sh --check --profile developer 2>&1 | grep -iE "terraform|kubectl" | wc -l
```

Expected:
- First: terraform/kubectl/vault/helm task names appear.
- Second: count is `0` (iac tools should NOT run in developer-only).

- [ ] **Step 6: Commit**

```bash
git add ansible/roles/iac ansible/roles/developer/tasks/cloud.yml ansible/roles/developer/tasks/main.yml
git commit -m "refactor(iac): extract Hashicorp + k8s + dive from developer into iac role"
```

### Task 2.3: Populate `openvpn` role with DRAGONFLY fixes

**Files:**
- Move: `ansible/roles/developer_core/tasks/openvpn.yml` → `ansible/roles/openvpn/tasks/openvpn.yml`
- Create: `ansible/roles/openvpn/tasks/indicator.yml`
- Create: `ansible/roles/openvpn/tasks/netcfg.yml`
- Create: `ansible/roles/openvpn/files/openvpn3-indicator.desktop`
- Modify: `ansible/roles/openvpn/tasks/main.yml`
- Modify: `ansible/roles/developer_core/tasks/main.yml` (remove openvpn include)

- [ ] **Step 1: Move openvpn.yml**

```bash
git mv ansible/roles/developer_core/tasks/openvpn.yml ansible/roles/openvpn/tasks/openvpn.yml
```

- [ ] **Step 2: Create `indicator.yml` with the D-Bus warm-up autostart fix**

```yaml
---
# openvpn3-indicator — GTK tray for OpenVPN 3
# DRAGONFLY finding: stock autostart races the D-Bus-activated services,
# producing a broken proxy with silent Connect failures. Fix with a user-level
# autostart override that forces sessions-list before launching the indicator.

- name: Install openvpn3-indicator (Ubuntu only — Fedora has native tray)
  block:
    - name: Add openvpn3-indicator PPA
      ansible.builtin.apt_repository:
        repo: "ppa:grzegorz-gutowski/openvpn3-indicator"
        filename: openvpn3-indicator
        state: present
        update_cache: true

    - name: Install openvpn3-indicator package
      ansible.builtin.apt:
        name: openvpn3-indicator
        state: present

    - name: Ensure user-level autostart directory exists
      ansible.builtin.file:
        path: "{{ user_home }}/.config/autostart"
        state: directory
        owner: "{{ actual_user }}"
        mode: '0755'

    - name: Deploy D-Bus warm-up autostart override
      ansible.builtin.copy:
        src: openvpn3-indicator.desktop
        dest: "{{ user_home }}/.config/autostart/openvpn3-indicator.desktop"
        owner: "{{ actual_user }}"
        mode: '0644'

    - name: Enable ubuntu-appindicators GNOME extension
      ansible.builtin.command: >-
        sudo -u {{ actual_user }}
        gnome-extensions enable ubuntu-appindicators@ubuntu.com
      register: appind_enable
      changed_when: "'already enabled' not in appind_enable.stderr | default('')"
      failed_when: false   # extension may not be installed on Fedora/headless

  when: ansible_facts['distribution'] == 'Ubuntu'
```

- [ ] **Step 3: Create the `.desktop` autostart file**

```bash
# ansible/roles/openvpn/files/openvpn3-indicator.desktop
[Desktop Entry]
Type=Application
Name=openvpn3-indicator
# D-Bus warm-up shim — forces activation of net.openvpn.v3.sessions before
# launching the indicator, otherwise the indicator starts against a dead proxy.
# See DRAGONFLY.md 2026-04-18 07:00 AEST entry.
Exec=sh -c 'openvpn3 sessions-list >/dev/null 2>&1; exec openvpn3-indicator'
X-GNOME-Autostart-enabled=true
NoDisplay=false
Terminal=false
```

- [ ] **Step 4: Create `netcfg.yml` with the systemd-resolved fix**

```yaml
---
# openvpn3-service-netcfg must be told to use systemd-resolved, or every
# session silently drops pushed DNS with "No DNS resolver configured".
# DRAGONFLY root cause: Exec line in
# /usr/share/dbus-1/system-services/net.openvpn.v3.netcfg.service has no
# --systemd-resolved flag, so netcfg starts with no DNS backend at all.
# Fix is persistent: writes /var/lib/openvpn3/netcfg.json.

- name: Configure openvpn3 netcfg to use systemd-resolved
  ansible.builtin.command: openvpn3-admin netcfg-service --config-set systemd-resolved yes
  register: netcfg_set
  changed_when: "'already' not in netcfg_set.stdout | default('')"
  become: true

- name: Restart openvpn3-service-netcfg to pick up config
  ansible.builtin.command: pkill -f openvpn3-service-netcfg
  failed_when: false   # netcfg is D-Bus-activated — OK if not running
  changed_when: true
  become: true
```

- [ ] **Step 5: Update openvpn role main.yml**

```yaml
---
# OpenVPN 3 legacy VPN stack (transitional — removal ~2026-06)

- name: Install OpenVPN 3 CLI + config
  ansible.builtin.include_tasks:
    file: openvpn.yml

- name: Configure openvpn3 netcfg for systemd-resolved (DNS fix)
  ansible.builtin.include_tasks:
    file: netcfg.yml
  when: ansible_facts['distribution'] in ['Fedora', 'Ubuntu']

- name: Install openvpn3-indicator GTK tray (Ubuntu)
  ansible.builtin.include_tasks:
    file: indicator.yml
  when: ansible_facts['distribution'] == 'Ubuntu'
```

- [ ] **Step 6: Remove openvpn include from developer_core main.yml**

Delete the "Install OpenVPN 3" include block from `developer_core/tasks/main.yml`.

- [ ] **Step 7: Move the OpenVPN verify tasks**

Create `ansible/roles/openvpn/tasks/verify.yml` with the "Verify OpenVPN 3 (Linux)" and "(macOS)" tasks moved from `developer_core/tasks/verify.yml`. Update the openvpn main.yml to include verify.yml with tag `verify`. Remove the originals from `developer_core/tasks/verify.yml`.

- [ ] **Step 8: Check-mode test**

```bash
./install.sh --check --profile core,openvpn 2>&1 | grep -iE "openvpn|netcfg|indicator"
```

Expected: openvpn3 install, netcfg config-set, indicator PPA setup all appear.

- [ ] **Step 9: Commit**

```bash
git add ansible/roles/openvpn ansible/roles/developer_core/tasks/main.yml ansible/roles/developer_core/tasks/verify.yml
git commit -m "refactor(openvpn): extract into role, add netcfg + indicator fixes"
```

### Task 2.4: Populate `gui_extras` role

**Files:**
- Move: Freelens block (from `iac/tasks/k8s.yml`, now in iac role after Task 2.2) → `ansible/roles/gui_extras/tasks/freelens.yml`
- Create: `ansible/roles/gui_extras/tasks/bruno.yml`
- Create: `ansible/roles/gui_extras/tasks/podman_desktop.yml`
- Create: `ansible/roles/gui_extras/tasks/dbeaver.yml`
- Create: `ansible/roles/gui_extras/tasks/lazygit.yml`
- Modify: `ansible/roles/gui_extras/tasks/main.yml`

- [ ] **Step 1: Extract Freelens into its own file**

Locate the Freelens block:

```bash
grep -n -i 'freelens' ansible/roles/iac/tasks/k8s.yml
```

The Freelens block typically spans from `- name: Install Freelens` (or similar) through the last Freelens-specific task (apt install, .deb download, or dnf install). If a Freelens repo/key/GPG setup exists immediately above that task, include it. Verify the cut boundary is clean (no other tool's task begins mid-range).

Cut the block from `iac/tasks/k8s.yml` and paste into `ansible/roles/gui_extras/tasks/freelens.yml`. Wrap the new file with the standard `---` header.

- [ ] **Step 2: Create bruno.yml**

```yaml
---
# Bruno — Git-native, local-first API client (FOSS Postman alternative)

- name: Install Bruno (Ubuntu)
  block:
    - name: Add Bruno GPG key
      ansible.builtin.get_url:
        url: https://www.usebruno.com/gpg-key.asc
        dest: /usr/share/keyrings/bruno-archive-keyring.asc
        mode: '0644'

    - name: Add Bruno APT repository
      ansible.builtin.apt_repository:
        repo: "deb [signed-by=/usr/share/keyrings/bruno-archive-keyring.asc] https://usebruno.jfrog.io/artifactory/bruno-apt bruno main"
        filename: bruno
        state: present
        update_cache: true

    - name: Install Bruno package
      ansible.builtin.apt:
        name: bruno
        state: present
  when: ansible_facts['distribution'] == 'Ubuntu'

- name: Install Bruno (Fedora via flatpak)
  ansible.builtin.command: flatpak install -y flathub com.usebruno.Bruno
  register: bruno_flatpak
  changed_when: "'already installed' not in bruno_flatpak.stdout | default('')"
  when: ansible_facts['distribution'] == 'Fedora'
```

**Note for implementer:** verify the Bruno apt repo URL and GPG key URL are still current before merging — reference https://docs.usebruno.com/bruno-basics/installation. If the URLs drift, adjust. Flatpak fallback is the safer cross-distro install.

- [ ] **Step 3: Create podman_desktop.yml**

```yaml
---
# Podman Desktop — FOSS container GUI (Docker Desktop alternative, no licence concerns)
# Upstream: https://podman-desktop.io

- name: Install Podman Desktop (flatpak — cross-distro)
  ansible.builtin.command: flatpak install -y flathub io.podman_desktop.PodmanDesktop
  register: pd_flatpak
  changed_when: "'already installed' not in pd_flatpak.stdout | default('')"
  when: ansible_facts['distribution'] in ['Fedora', 'Ubuntu']
  become: false
```

**Note:** flatpak is the upstream-recommended Linux install path; avoids distro-specific repo maintenance.

- [ ] **Step 4: Create dbeaver.yml**

```yaml
---
# DBeaver Community — universal database client

- name: Install DBeaver Community (Ubuntu)
  block:
    - name: Add DBeaver GPG key
      ansible.builtin.get_url:
        url: https://dbeaver.io/debs/dbeaver.gpg.key
        dest: /usr/share/keyrings/dbeaver-archive-keyring.asc
        mode: '0644'

    - name: Add DBeaver APT repository
      ansible.builtin.apt_repository:
        repo: "deb [signed-by=/usr/share/keyrings/dbeaver-archive-keyring.asc] https://dbeaver.io/debs/dbeaver-ce /"
        filename: dbeaver
        state: present
        update_cache: true

    - name: Install DBeaver CE
      ansible.builtin.apt:
        name: dbeaver-ce
        state: present
  when: ansible_facts['distribution'] == 'Ubuntu'

- name: Install DBeaver (Fedora via flatpak)
  ansible.builtin.command: flatpak install -y flathub io.dbeaver.DBeaverCommunity
  register: dbeaver_flatpak
  changed_when: "'already installed' not in dbeaver_flatpak.stdout | default('')"
  when: ansible_facts['distribution'] == 'Fedora'
```

- [ ] **Step 5: Create lazygit.yml**

```yaml
---
# lazygit — TUI git helper (also serves as our GH GUI helper)

- name: Install lazygit (Fedora)
  ansible.builtin.dnf:
    name: lazygit
    state: present
  when: ansible_facts['distribution'] == 'Fedora'

- name: Install lazygit (Ubuntu — upstream tarball, no apt package available)
  block:
    - name: Detect latest lazygit version from GitHub
      ansible.builtin.uri:
        url: https://api.github.com/repos/jesseduffield/lazygit/releases/latest
        return_content: true
      register: lazygit_release
      delegate_to: localhost
      become: false

    - name: Set lazygit version fact
      ansible.builtin.set_fact:
        lazygit_version: "{{ lazygit_release.json.tag_name | regex_replace('^v', '') }}"

    - name: Download lazygit tarball
      ansible.builtin.get_url:
        url: "https://github.com/jesseduffield/lazygit/releases/download/v{{ lazygit_version }}/lazygit_{{ lazygit_version }}_Linux_x86_64.tar.gz"
        dest: /tmp/lazygit.tar.gz
        mode: '0644'

    - name: Extract lazygit binary
      ansible.builtin.unarchive:
        src: /tmp/lazygit.tar.gz
        dest: /usr/local/bin
        include: ['lazygit']
        remote_src: true
        mode: '0755'

    - name: Remove lazygit tarball
      ansible.builtin.file:
        path: /tmp/lazygit.tar.gz
        state: absent
  when: ansible_facts['distribution'] == 'Ubuntu'

- name: Install lazygit (macOS)
  community.general.homebrew:
    name: jesseduffield/lazygit/lazygit
    state: present
  environment: "{{ homebrew_env }}"
  become: false
  when: ansible_facts['distribution'] == 'MacOSX'
```

- [ ] **Step 6: Update gui_extras main.yml**

```yaml
---
# Optional GUI/TUI developer extras

- name: Install Freelens (k8s cluster GUI)
  ansible.builtin.include_tasks:
    file: freelens.yml
  when: has_gnome | default(false)

- name: Install Bruno (API client)
  ansible.builtin.include_tasks:
    file: bruno.yml
  when: has_gnome | default(false)

- name: Install Podman Desktop
  ansible.builtin.include_tasks:
    file: podman_desktop.yml
  when: has_gnome | default(false)

- name: Install DBeaver Community
  ansible.builtin.include_tasks:
    file: dbeaver.yml
  when: has_gnome | default(false)

- name: Install lazygit
  ansible.builtin.include_tasks:
    file: lazygit.yml
```

- [ ] **Step 7: Check-mode test**

```bash
./install.sh --check --profile gui_extras 2>&1 | grep -iE "freelens|bruno|podman|dbeaver|lazygit"
```

Expected: all five tool names appear.

- [ ] **Step 8: Commit**

```bash
git add ansible/roles/gui_extras ansible/roles/iac/tasks/k8s.yml
git commit -m "refactor(gui_extras): populate with Freelens, Bruno, Podman Desktop, DBeaver, lazygit"
```

### Chunk 2 checkpoint

- [ ] **Run profile matrix + bats**

```bash
bats tests/bats/install_profile.bats
cd ansible && ./test.sh --matrix --limit ubuntu
```

All profiles must still check-mode cleanly.

---

## Chunk 3: Two-tier split (developer ↔ core)

Goal: extract Hyperi-specific items from `developer` and `developer_core` into the new `core` role, add `wl-clipboard` + `kcat` to BASE, add WireGuard to core, standardize opt-out variables. Delete `developer_core` at the end.

### Task 3.1: Populate `core` role — Hyperi tier contents

**Files (verified against actual repo layout):**
- Move: `ansible/roles/developer_core/tasks/slack.yml` → `ansible/roles/core/tasks/slack.yml`
- Move: `ansible/roles/developer_core/tasks/linear.yml` → `ansible/roles/core/tasks/linear.yml`
- Move: `ansible/roles/developer_core/tasks/jfrog.yml` → `ansible/roles/core/tasks/jfrog.yml`
- Move: `ansible/roles/developer_core/tasks/wallpaper.yml` → `ansible/roles/core/tasks/wallpaper.yml` (**source is developer_core, not developer**)
- Move: `ansible/roles/developer/tasks/avatar.yml` → `ansible/roles/core/tasks/avatar.yml`
- Move: `ansible/roles/developer/files/branding/background.svg` → `ansible/roles/core/files/branding/background.svg`
- Move: `ansible/roles/developer/files/branding/avatar.svg` → `ansible/roles/core/files/branding/avatar.svg`
- Modify: `ansible/roles/developer/tasks/main.yml` — remove the "Deploy user avatar for GDM login screen" block (currently around lines 60-68)
- Create: `ansible/roles/core/tasks/wireguard.yml`
- Create: `ansible/roles/core/tasks/rclone.yml`
- Modify: `ansible/roles/core/tasks/main.yml` (replace skeleton)
- Modify: `ansible/roles/core/tasks/wallpaper.yml` — update any `wallpaper_name` set_fact to reference `background.svg` (the actual filename, not `default-background.svg`)

- [ ] **Step 1a: Verify the branding files are where the plan says**

```bash
ls ansible/roles/developer/files/branding/
grep -rn 'background\|default-background\|wallpaper_name\|avatar' ansible/roles/developer*/tasks/wallpaper.yml ansible/roles/developer*/tasks/avatar.yml 2>/dev/null
```

Expected: `background.svg` and `avatar.svg` present under `ansible/roles/developer/files/branding/`. `wallpaper.yml` references these via a `wallpaper_name` set_fact or direct path. If your output shows different filenames, adjust the git-mv commands below to match.

- [ ] **Step 1b: Move task files with `git mv`**

```bash
git mv ansible/roles/developer_core/tasks/slack.yml ansible/roles/core/tasks/slack.yml
git mv ansible/roles/developer_core/tasks/linear.yml ansible/roles/core/tasks/linear.yml
git mv ansible/roles/developer_core/tasks/jfrog.yml ansible/roles/core/tasks/jfrog.yml
git mv ansible/roles/developer_core/tasks/wallpaper.yml ansible/roles/core/tasks/wallpaper.yml
git mv ansible/roles/developer/tasks/avatar.yml ansible/roles/core/tasks/avatar.yml

mkdir -p ansible/roles/core/files/branding
git mv ansible/roles/developer/files/branding/background.svg ansible/roles/core/files/branding/background.svg
git mv ansible/roles/developer/files/branding/avatar.svg ansible/roles/core/files/branding/avatar.svg
```

All moves must succeed — no `|| true` hedge. If any fail, stop and investigate.

- [ ] **Step 1c: Remove the avatar include from developer main.yml**

Now that `avatar.yml` lives in `core`, `developer/tasks/main.yml` must stop including it. Delete the block starting `- name: Deploy user avatar for GDM login screen` (pattern-based).

- [ ] **Step 1d: Update file references in the moved task files**

Open `ansible/roles/core/tasks/wallpaper.yml` and `ansible/roles/core/tasks/avatar.yml`. Any `src:` or `copy:` references to `branding/background.svg` / `branding/avatar.svg` remain valid (paths are role-relative). Only update if the original task used `files: ../../developer/files/...` or similar cross-role references. Typically no edits needed. Verify with:

```bash
grep -rn 'branding\|background.svg\|avatar.svg' ansible/roles/core/
```

- [ ] **Step 1e: Create rclone.yml**

rclone is a multi-backend cloud storage CLI used against Hyperi's storage (MinIO on `storage.devex.hyperi.io`). Installed as part of the Hyperi tier, not general OSS, because its presence implies a Hyperi workflow.

```yaml
---
# rclone — multi-backend cloud storage sync CLI
# Upstream: https://rclone.org

- name: Install rclone (Fedora)
  ansible.builtin.dnf:
    name: rclone
    state: present
  when: ansible_facts['distribution'] == 'Fedora'

- name: Install rclone (Ubuntu)
  ansible.builtin.apt:
    name: rclone
    state: present
  when: ansible_facts['distribution'] == 'Ubuntu'

- name: Install rclone (macOS via Homebrew)
  community.general.homebrew:
    name: rclone
    state: present
  environment: "{{ homebrew_env }}"
  become: false
  when: ansible_facts['distribution'] == 'MacOSX'
```

- [ ] **Step 2: Create wireguard.yml**

```yaml
---
# WireGuard — default Hyperi VPN (replaces legacy OpenVPN in BASE)
# Peer configuration is deployed if available; otherwise just the package.

- name: Install WireGuard (Fedora)
  ansible.builtin.dnf:
    name:
      - wireguard-tools
      - systemd-resolved
    state: present
  when: ansible_facts['distribution'] == 'Fedora'

- name: Install WireGuard (Ubuntu)
  ansible.builtin.apt:
    name:
      - wireguard
      - wireguard-tools
    state: present
  when: ansible_facts['distribution'] == 'Ubuntu'

- name: Install WireGuard (macOS via Homebrew)
  community.general.homebrew:
    name: wireguard-tools
    state: present
  environment: "{{ homebrew_env }}"
  become: false
  when: ansible_facts['distribution'] == 'MacOSX'

# Hyperi peer config deployment is deliberately opt-in via variable.
# The config file itself is NOT bundled in this repo (would be a secrets leak);
# operators provide it out-of-band (OpenBao, manual install, etc.).
- name: Deploy Hyperi WireGuard peer config (if provided)
  ansible.builtin.copy:
    src: "{{ wireguard_peer_config }}"
    dest: "/etc/wireguard/hyperi.conf"
    owner: root
    group: root
    mode: '0600'
  when:
    - wireguard_peer_config is defined
    - wireguard_peer_config | length > 0
  become: true
```

- [ ] **Step 3: Update core main.yml**

```yaml
---
# Core — Hyperi internal tier (implies developer)

- name: Install Slack
  ansible.builtin.include_tasks:
    file: slack.yml
  when: install_slack | default(true)
  tags: ['slack']

- name: Install Linear CLI
  ansible.builtin.include_tasks:
    file: linear.yml
  when: install_linear | default(true)
  tags: ['linear']

- name: Install JFrog CLI
  ansible.builtin.include_tasks:
    file: jfrog.yml
  tags: ['jfrog']

- name: Install rclone (Hyperi storage sync)
  ansible.builtin.include_tasks:
    file: rclone.yml
  tags: ['rclone']

- name: Install WireGuard (default Hyperi VPN)
  ansible.builtin.include_tasks:
    file: wireguard.yml
  tags: ['wireguard', 'vpn']

- name: Deploy Hyperi-branded wallpaper
  ansible.builtin.include_tasks:
    file: wallpaper.yml
  when: has_gnome | default(false)
  tags: ['wallpaper']

- name: Deploy user avatar (Hyperi default)
  ansible.builtin.include_tasks:
    file: avatar.yml
  when: has_gnome | default(false)
  tags: ['avatar']
```

- [ ] **Step 4: Check-mode test**

```bash
./install.sh --check --profile core 2>&1 | grep -iE "slack|linear|jfrog|rclone|wireguard|wallpaper|avatar"
```

Expected: all seven surface.

```bash
./install.sh --check --profile developer 2>&1 | grep -iE "slack|linear|jfrog|rclone|wireguard|hyperi" | wc -l
```

Expected: **0** (Hyperi items must NOT run in OSS tier).

- [ ] **Step 5: Commit**

```bash
git add ansible/roles/core ansible/roles/developer ansible/roles/developer_core
git commit -m "refactor(core): populate with Slack/Linear/JFrog/WireGuard/branding from old roles"
```

### Task 3.2: Move `azure` and `gcloud` into `developer`

Previously `azure.yml` and `gcloud.yml` lived in `developer_core`. The spec places them in `developer` as universal cloud CLIs.

**Files:**
- Move: `ansible/roles/developer_core/tasks/azure.yml` → `ansible/roles/developer/tasks/azure.yml`
- Move: `ansible/roles/developer_core/tasks/gcloud.yml` → `ansible/roles/developer/tasks/gcloud.yml`
- Modify: `ansible/roles/developer/tasks/main.yml` (add includes)
- Modify: `ansible/roles/developer_core/tasks/main.yml` (remove includes)

- [ ] **Step 1: Move files**

```bash
git mv ansible/roles/developer_core/tasks/azure.yml ansible/roles/developer/tasks/azure.yml
git mv ansible/roles/developer_core/tasks/gcloud.yml ansible/roles/developer/tasks/gcloud.yml
```

- [ ] **Step 2: Add includes to developer/tasks/main.yml**

Near the existing `cloud` include (around line 133-138), add:

```yaml
- name: Install Azure CLI
  ansible.builtin.include_tasks:
    file: azure.yml
  tags: ['azure', 'cloud']

- name: Install Google Cloud CLI
  ansible.builtin.include_tasks:
    file: gcloud.yml
  tags: ['gcloud', 'cloud']
```

- [ ] **Step 3: Remove the two includes from `developer_core/tasks/main.yml`**

Delete the "Install Azure CLI" and "Install Google Cloud CLI" blocks (they're defined at developer_core/tasks/main.yml:19-27 currently).

- [ ] **Step 4: Commit**

```bash
git add ansible/roles/developer ansible/roles/developer_core
git commit -m "refactor(developer): move azure/gcloud CLIs from developer_core (universal tier)"
```

### Task 3.3: Move remaining `developer_core` items into `developer`

The remainders in `developer_core` (after rust/slack/linear/jfrog/azure/gcloud/openvpn moved out): `c_tools`, `nodejs`, `office` (Mailspring), `bitwarden`, `claude`, `gitleaks`, `act`, `telemetry`, `wallpaper`, `verify` — these all belong in `developer` per the spec.

**Files:**
- Move each of: `c_tools.yml`, `nodejs.yml`, `bitwarden.yml`, `claude.yml`, `gitleaks.yml`, `act.yml`, `telemetry.yml` from `developer_core/tasks/` → `developer/tasks/`
- **Reconcile** `office.yml` vs existing `onlyoffice.yml` (see Step 1b below — they currently coexist with `office.yml` deferring to `onlyoffice.yml`)
- Move the verify blocks for each into `developer/tasks/verify.yml`
- Modify: `developer/tasks/main.yml` (add includes with appropriate opt-out `when:` clauses)
- Modify: `developer_core/tasks/main.yml` (remove matching include blocks)

- [ ] **Step 1a: git mv the straightforward files**

```bash
for f in c_tools.yml nodejs.yml bitwarden.yml claude.yml gitleaks.yml act.yml telemetry.yml; do
    git mv "ansible/roles/developer_core/tasks/$f" "ansible/roles/developer/tasks/$f"
done
```

- [ ] **Step 1b: Reconcile office.yml vs onlyoffice.yml**

Context: `ansible/roles/developer/tasks/onlyoffice.yml` (primary, native apt/dnf OnlyOffice install) and `ansible/roles/developer_core/tasks/office.yml` (Flatpak fallback for OnlyOffice + Mailspring install) currently coexist. Read both files:

```bash
cat ansible/roles/developer/tasks/onlyoffice.yml
cat ansible/roles/developer_core/tasks/office.yml
```

Pick one of these two reconciliations:

**Option A (preferred, cleaner):** Split `office.yml` into a Mailspring-only `mailspring.yml`, drop the OnlyOffice Flatpak fallback (native install in `onlyoffice.yml` handles all supported distros — Fedora 42+ and Ubuntu 24.04+ both have OnlyOffice in their apt/dnf repos):

```bash
# After manual edit that strips OnlyOffice from office.yml and leaves only Mailspring tasks:
git mv ansible/roles/developer_core/tasks/office.yml ansible/roles/developer/tasks/mailspring.yml
```

**Option B (minimal change):** Keep both files as-is and move `office.yml` to developer. Both will run; the flatpak fallback is idempotent and will no-op when native OnlyOffice is detected.

```bash
git mv ansible/roles/developer_core/tasks/office.yml ansible/roles/developer/tasks/office.yml
```

Record which option chosen in the commit message. Default to Option A unless the flatpak fallback is known to still serve a use case.

- [ ] **Step 2: Merge the verify blocks**

Open `ansible/roles/developer_core/tasks/verify.yml` and `ansible/roles/developer/tasks/verify.yml`. Move every remaining verify task from developer_core into developer (append to the existing developer verify.yml). Then delete `developer_core/tasks/verify.yml`.

- [ ] **Step 3: Add includes to developer main.yml**

Near the existing includes in `developer/tasks/main.yml`, add (grouped logically). The Mailspring include below assumes Option A above; if Option B was chosen, replace the Mailspring block with a single `office.yml` include gated on `install_onlyoffice or install_mailspring`.

```yaml
- name: Install C development tools
  ansible.builtin.include_tasks:
    file: c_tools.yml
  tags: ['c_tools', 'dev']

- name: Install Node.js and semantic-release
  ansible.builtin.include_tasks:
    file: nodejs.yml
  tags: ['nodejs']

# Note: onlyoffice.yml include already exists in developer/tasks/main.yml.
# Only add Mailspring here (assumes Option A — mailspring.yml was split from office.yml).
- name: Install Mailspring email client
  ansible.builtin.include_tasks:
    file: mailspring.yml
  when: install_mailspring | default(true)
  tags: ['mailspring', 'email']

- name: Install Bitwarden
  ansible.builtin.include_tasks:
    file: bitwarden.yml
  when: install_bitwarden | default(true)
  tags: ['bitwarden']

- name: Install Claude Code CLI
  ansible.builtin.include_tasks:
    file: claude.yml
  tags: ['claude']

- name: Install Gitleaks
  ansible.builtin.include_tasks:
    file: gitleaks.yml
  tags: ['gitleaks']

- name: Install act (local GitHub Actions)
  ansible.builtin.include_tasks:
    file: act.yml
  tags: ['act', 'ci']

- name: Disable telemetry and advertising
  ansible.builtin.include_tasks:
    file: telemetry.yml
  tags: ['telemetry']
```

Update the existing `onlyoffice.yml` include's `when:` clause to use the opt-out variable if not already: `install_onlyoffice | default(true)`.

- [ ] **Step 4: Remove matching blocks from developer_core/tasks/main.yml**

After these moves, `developer_core/tasks/main.yml` should only have includes for items already relocated earlier (rust → rust role, openvpn → openvpn role, slack/linear/jfrog → core role, azure/gcloud → developer). Remove any remaining blocks that reference the tasks just moved: `c_tools`, `nodejs`, `office`, `bitwarden`, `claude`, `gitleaks`, `act`, `telemetry`, and `wallpaper` (wallpaper is handled in Task 3.1). Use pattern-based deletion — look for each `- name: Install <thing>` or `- name: Disable telemetry` block.

- [ ] **Step 5: Check-mode test**

```bash
./install.sh --check --profile developer 2>&1 | grep -iE "bitwarden|onlyoffice|mailspring|gitleaks|claude|act|nodejs"
```

Expected: all mentioned tool names appear. No Slack/Linear/JFrog/WireGuard in the output.

- [ ] **Step 6: Commit**

```bash
git add ansible/roles/developer ansible/roles/developer_core
git commit -m "refactor(developer): absorb remaining developer_core tooling (c_tools/nodejs/office/...)"
```

### Task 3.4: Add `wl-clipboard` to utilities and `kcat` to data_tools

**Files:**
- Modify: `ansible/roles/developer/tasks/utilities.yml`
- Modify: `ansible/roles/developer/tasks/data_tools.yml`

- [ ] **Step 1: Add `wl-clipboard` to the utilities package list**

In both the Fedora and Ubuntu package lists in `utilities.yml`, add:

```yaml
      - wl-clipboard            # Wayland screenshot→clipboard bridge (DRAGONFLY)
```

- [ ] **Step 2: Verify package names on each target distro**

kcat was renamed from `kafkacat` in 2021, but some distro repos still ship the old name. Before writing the task, confirm:

```bash
# Ubuntu 24.04
apt-cache search '^kcat$\|^kafkacat$'
# Fedora 42 (may need copr or epel — confirm)
dnf search kcat
```

Adjust the `name:` values below to match what's actually available. If kcat isn't in Fedora's default repos, either enable a COPR or skip Fedora with a `when: ansible_facts['distribution'] != 'Fedora'` conditional and note it as a known gap.

- [ ] **Step 3: Add kcat to data_tools.yml**

Append to `data_tools.yml` (adjust package names per Step 2 findings):

```yaml
# ---- kcat (kafkacat) — FOSS Kafka CLI ----
- name: Install kcat (Fedora)
  ansible.builtin.dnf:
    name: kcat          # verify with `dnf search kcat` — may be kafkacat
    state: present
  when: ansible_facts['distribution'] == 'Fedora'

- name: Install kcat (Ubuntu)
  ansible.builtin.apt:
    name: kafkacat      # verify with `apt-cache search`; may be kcat on 26.04
    state: present
  when: ansible_facts['distribution'] == 'Ubuntu'

- name: Install kcat (macOS via Homebrew)
  community.general.homebrew:
    name: kcat
    state: present
  environment: "{{ homebrew_env }}"
  become: false
  when: ansible_facts['distribution'] == 'MacOSX'
```

- [ ] **Step 3: Check-mode test**

```bash
./install.sh --check --profile developer 2>&1 | grep -iE "wl-clipboard|kcat|kafkacat"
```

Expected: both surface.

- [ ] **Step 4: Commit**

```bash
git add ansible/roles/developer/tasks/utilities.yml ansible/roles/developer/tasks/data_tools.yml
git commit -m "feat(developer): add wl-clipboard and kcat to base tier (DRAGONFLY gap fix)"
```

### Task 3.5: Create `group_vars/all.yml` with opt-out defaults

**Files:**
- Create: `ansible/inventories/localhost/group_vars/all.yml`

Context: centralizing opt-out defaults makes them discoverable and overridable via inventory or `--extra-vars`.

- [ ] **Step 1: Create the group_vars directory**

The `group_vars/` subdirectory does not exist in the current repo. Create it:

```bash
mkdir -p ansible/inventories/localhost/group_vars
```

- [ ] **Step 2: Write group_vars/all.yml**

```yaml
---
# Opt-out defaults for user-facing applications.
# Override via inventory, group_vars, or --extra-vars "install_slack=false"

# --- developer tier (OSS) ---
install_bitwarden: true
install_onlyoffice: true
install_mailspring: true
install_brave: true

# --- core tier (Hyperi internal) ---
install_slack: true
install_linear: true

# WireGuard peer config path (deliberately empty by default — operators set this)
# If set, core/wireguard.yml will copy the file to /etc/wireguard/hyperi.conf.
# wireguard_peer_config: /path/to/hyperi.conf
```

- [ ] **Step 3: Commit**

```bash
git add ansible/inventories/localhost/group_vars/all.yml
git commit -m "feat(vars): centralize opt-out defaults in group_vars/all.yml"
```

### Task 3.6: Delete `developer_core` role

**Files:**
- Delete: `ansible/roles/developer_core/`

- [ ] **Step 1: Confirm nothing remains**

```bash
find ansible/roles/developer_core -type f
```

Expected: only `meta/main.yml` and an empty `tasks/` directory (or possibly stragglers).

- [ ] **Step 2: Verify nothing references `developer_core`**

Run two greps — one that must be zero hits (code/config), one that allows documentation references:

```bash
# Must be zero hits — any result here blocks deletion:
grep -rn 'developer_core' ansible/ install.sh ansible/test.sh
# Advisory — doc-only references are OK:
grep -rn 'developer_core' docs/ README.md CHANGELOG.md 2>/dev/null
```

If the first command returns any hits, investigate and either move the referenced item or update the reference before proceeding.

- [ ] **Step 3: Delete the role directory**

```bash
git rm -r ansible/roles/developer_core/
```

- [ ] **Step 4: Run full check-mode matrix**

```bash
cd ansible && ./test.sh --matrix --limit ubuntu
```

Expected: all 8 profile combos pass.

- [ ] **Step 5: Commit**

```bash
git commit -m "refactor: delete developer_core role (fully absorbed into developer/core/rust/iac/openvpn)"
```

### Chunk 3 checkpoint

- [ ] **Full syntax + matrix run**

```bash
ansible-playbook --syntax-check ansible/playbooks/main.yml -i ansible/inventories/localhost/inventory.yml
bats tests/bats/install_profile.bats
cd ansible && ./test.sh --matrix --limit ubuntu
```

All pass.

---

## Chunk 4: Audit + OSS-safe assertion + VM smoke tests

Goal: verify every external URL and version pin is current, prove the `developer` tier contains zero Hyperi tooling on a real VM, document findings.

### Task 4.1: Run URL/pin audit

**Files:**
- Create: `tests/audit/urls_and_pins.sh`
- Create: `docs/plans/2026-04-18-audit-findings.md`

- [ ] **Step 1: Write the audit script**

The script uses Python for CSV output because YAML lines are riddled with colons (URLs especially), which breaks naive awk field-splitting. Keep the script simple and rerunnable.

```python
#!/usr/bin/env python3
# tests/audit/urls_and_pins.py — scan Ansible tasks for external references
# and version pins. Emits a well-quoted CSV to stdout.

import csv
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2] / "ansible" / "roles"

# Patterns per the spec's audit section:
#   url:, baseurl:, gpgkey:, key:, repo:, src: (for download URLs)
#   apt_key:, rpm_key: keyed blocks
#   version: values and *_version set_fact variables
#   PPAs (ppa:<owner>/<repo>)
PATTERNS = [
    ("url",     re.compile(r'^\s*(url|baseurl|gpgkey|key|src):\s*(.+)$')),
    ("repo",    re.compile(r'^\s*repo:\s*(.+)$')),
    ("apt_key", re.compile(r'^\s*apt_key:\s*(.+)$')),
    ("rpm_key", re.compile(r'^\s*rpm_key:\s*(.+)$')),
    ("ppa",     re.compile(r'^\s*.*?ppa:[\w.-]+/[\w.-]+')),
    ("version", re.compile(r'^\s*(\w+_version|version):\s*["\']?[\d.]+')),
]

writer = csv.writer(sys.stdout)
writer.writerow(["file", "line", "type", "match"])

for yml in sorted(ROOT.rglob("*.yml")):
    for idx, line in enumerate(yml.read_text().splitlines(), start=1):
        for kind, pat in PATTERNS:
            if pat.search(line):
                writer.writerow([str(yml.relative_to(ROOT.parent.parent)), idx, kind, line.strip()])
                break  # one hit per line to avoid spam
```

Save to `tests/audit/urls_and_pins.py`, make executable:

```bash
chmod +x tests/audit/urls_and_pins.py
```

- [ ] **Step 2: Run the audit**

```bash
./tests/audit/urls_and_pins.py > /tmp/audit.csv
wc -l /tmp/audit.csv
```

- [ ] **Step 3: Triage findings into buckets**

For each finding in `/tmp/audit.csv`, manually evaluate:
- (a) URL reachable? (`curl -IfsS $url > /dev/null && echo OK || echo FAIL`)
- (b) Pin justified? (intentional like `grd_patched_version` → leave; accidental → fix)
- (c) Upstream drifted? (package renamed, PPA gone silent > 6 months, etc.)

Write findings to `docs/plans/2026-04-18-audit-findings.md`:

```markdown
# URL + Version Audit — Findings

**Date:** 2026-04-18
**Source:** tests/audit/urls_and_pins.sh run output

## Fix-now (this refactor)
<!-- items that get fixed in this chunk -->
- [file:line]: [what] — [fix taken]

## Flag for Track 2 (Ubuntu 26.04)
<!-- items that only break on 26.04; handled in Track 2 spec -->
- [file:line]: [what] — [note for Track 2]

## Defer (follow-up)
<!-- real work; move to TODO.md -->
- [file:line]: [what] — [TODO.md entry created]
```

- [ ] **Step 4: Apply fix-now changes**

For each fix-now finding, make the targeted edit. Each fix gets its own commit:

```bash
git commit -m "fix(audit): correct <tool> repo URL (<file>)"
```

- [ ] **Step 5: Commit the audit script and findings doc**

```bash
git add tests/audit/ docs/plans/2026-04-18-audit-findings.md
git commit -m "chore(audit): run URL/pin audit, record findings"
```

### Task 4.2: OSS-safe assertion script

**Files:**
- Create: `tests/assertions/oss_safe.sh`

- [ ] **Step 1: Write the assertion**

```bash
#!/usr/bin/env bash
# Verify that a --profile developer install did NOT leak Hyperi-specific
# tooling onto the target host. Intended to run after an Ansible install on
# a fresh VM.

set -euo pipefail

FAIL=0
check_absent() {
    local name="$1" cmd="$2"
    if eval "$cmd" >/dev/null 2>&1; then
        echo "FAIL: $name is present (should not be in developer tier)"
        FAIL=1
    else
        echo "OK:   $name absent"
    fi
}

# Hyperi-specific packages
check_absent "slack-desktop"         "dpkg -l slack-desktop 2>/dev/null | grep -q '^ii'"
check_absent "slack (rpm)"           "rpm -q slack 2>/dev/null"
check_absent "linear-cli binary"     "command -v linear"
check_absent "jfrog cli binary"      "command -v jf"
check_absent "wireguard-tools"       "dpkg -l wireguard-tools 2>/dev/null | grep -q '^ii'"
check_absent "wireguard-tools (rpm)" "rpm -q wireguard-tools 2>/dev/null"
check_absent "openvpn3"              "command -v openvpn3"

# Hyperi branding leak — wallpaper.yml copies to /usr/local/share/backgrounds/
check_absent "hyperi background"     "test -f /usr/local/share/backgrounds/background.svg"
check_absent "hyperi avatar"         "test -s /var/lib/AccountsService/icons/${USER} || find /var/lib/AccountsService/icons -size +0c 2>/dev/null | grep -q ."

if [[ $FAIL -ne 0 ]]; then
    echo ""
    echo "OSS-safe check FAILED — Hyperi tooling leaked into developer tier."
    exit 1
fi
echo "OSS-safe check PASSED."
```

- [ ] **Step 2: Commit**

```bash
chmod +x tests/assertions/oss_safe.sh
git add tests/assertions/oss_safe.sh
git commit -m "test(oss-safe): add post-install assertion against Hyperi leaks in developer tier"
```

### Task 4.3: VM smoke tests

Context: the check-mode matrix caught Ansible-level regressions. Real-VM smoke tests catch packaging and sequencing regressions.

**Test infrastructure (2026-04-18):** `proxmox.tyrell.com.au` is offline for ~1 week, so use the **devex Proxmox** at `devex.hyperi.io:8006` instead. The canonical Ubuntu 24.04 test template is **VMID 9010**.

**Fedora testing is deferred** for this refactor — no Fedora VM is currently available. Fedora-specific tasks (dnf blocks, Fedora-only conditionals) rely on check-mode syntax validation only. A follow-up run once a Fedora template exists on `devex.hyperi.io` will close this gap; track as a follow-up item in TODO.md.

- [ ] **Step 0: Provision a fresh test VM from VMID 9010**

Clone the Ubuntu 24.04 template to a disposable test VM. Run from the devex Proxmox host (`ssh root@devex.hyperi.io`) or via the Proxmox UI:

```bash
# Pick an unused VMID for the clone (e.g., 9100).
CLONE_ID=9100
qm clone 9010 $CLONE_ID --name dfe-test-ubuntu-2404 --full
qm start $CLONE_ID
# Wait ~60s for boot, then find the IP:
qm guest exec $CLONE_ID -- ip -4 -o addr show scope global
```

Record the IP or assigned hostname. The template is expected to have:
- Ubuntu 24.04 base install
- `dfe` user with passwordless sudo and the user's SSH key in `authorized_keys`
- SSH reachable on port 22

If the template hasn't been set up that way, log in via the Proxmox console once, create the user, paste the key, then snapshot before proceeding.

- [ ] **Step 0b: Create `/tmp/inventory_test.yml` pointing at the clone**

```bash
cat > /tmp/inventory_test.yml << 'EOF'
[ubuntu]
dfe-test-ubuntu-2404 ansible_host=<CLONE_IP> ansible_user=dfe ansible_become_password=dfe
EOF
```

Replace `<CLONE_IP>` with the IP from Step 0. (If passwordless sudo is already configured for `dfe`, drop the `ansible_become_password=` entry.)

- [ ] **Step 0c: Take a pre-install snapshot**

```bash
qm snapshot $CLONE_ID pre-dfe
```

This snapshot is the rollback point between the two smoke-test runs (`--profile developer` then `--profile core,all`). After each test, roll back with:

```bash
qm rollback $CLONE_ID pre-dfe
qm start $CLONE_ID
```

- [ ] **Step 0d: Cleanup policy**

When the smoke tests pass, destroy the clone:

```bash
qm stop $CLONE_ID
qm destroy $CLONE_ID
```

Don't leave it running — it's a disposable artifact.

- [ ] **Step 1: Run `--profile developer` against the clone**

```bash
cd /projects/dfe-developer/ansible
INVENTORY=/tmp/inventory_test.yml ./test.sh --profile developer --limit ubuntu
```

Expected: `PLAY RECAP` with `failed=0`.

- [ ] **Step 2: Run OSS-safe assertion on the clone**

```bash
CLONE_HOST=dfe@<CLONE_IP>    # from Step 0
scp tests/assertions/oss_safe.sh "$CLONE_HOST":/tmp/
ssh "$CLONE_HOST" "bash /tmp/oss_safe.sh"
```

Expected: "OSS-safe check PASSED."

- [ ] **Step 3: Roll back the clone, run `--profile core,all`**

```bash
# On devex.hyperi.io Proxmox host:
qm rollback 9100 pre-dfe && qm start 9100
# Wait ~60s for SSH to come back.

# On your workstation:
INVENTORY=/tmp/inventory_test.yml ./test.sh --profile core,all --limit ubuntu
```

Expected: `PLAY RECAP` with `failed=0`. SSH back in and manually verify Slack, Linear CLI, JFrog CLI, WireGuard, Freelens are all installed.

- [ ] **Step 4: Record results**

Append results + any issues to `docs/plans/2026-04-18-audit-findings.md` (under a "VM smoke test results" section).

- [ ] **Step 5: If issues found, fix and re-run. Otherwise commit the VM test evidence**

```bash
git add docs/plans/2026-04-18-audit-findings.md
git commit -m "test(vm): record --profile developer and --profile core,all VM smoke test results"
```

---

## Chunk 5: Documentation + release prep

### Task 5.1: Create `docs/TOOLS.md`

**Files:**
- Create: `docs/TOOLS.md`

Writing TOOLS.md is ~30-60 minutes total. Splitting into per-bucket sub-tasks keeps progress trackable and commit-friendly — one commit per bucket of content filled in.

- [ ] **Step 1: Write the skeleton and TOC**

```markdown
# DFE Developer Environment — Installed Tools

Per-tool rationale: what it is, why we installed it, why we picked it.

## Table of contents

- [developer tier (OSS-safe base)](#developer-tier-oss-safe-base)
- [core tier (Hyperi internal)](#core-tier-hyperi-internal)
- [rust profile](#rust-profile)
- [iac profile](#iac-profile)
- [gui_extras profile](#gui_extras-profile)
- [openvpn profile (transitional)](#openvpn-profile-transitional)
- [Opt-out variables](#opt-out-variables)

## developer tier (OSS-safe base)

[ ... one subsection per tool ... ]

## core tier (Hyperi internal)

[ ... ]

## rust profile

[ ... ]

## iac profile

[ ... ]

## gui_extras profile

[ ... ]

## openvpn profile (transitional)

[ ... ]

## Opt-out variables

| Variable | Default | Effect |
|----------|---------|--------|
| `install_bitwarden` | `true` | Bitwarden desktop |
| `install_onlyoffice` | `true` | OnlyOffice desktop editors |
| `install_mailspring` | `true` | Mailspring email client |
| `install_brave` | `true` | Brave browser |
| `install_slack` | `true` | Slack desktop (core tier only) |
| `install_linear` | `true` | Linear CLI (core tier only) |
| `wireguard_peer_config` | unset | Path to Hyperi WireGuard config |

Override examples:

    ./install.sh --profile developer --extra-vars "install_mailspring=false"
    ./install.sh --profile core --extra-vars "install_slack=false install_linear=false"
```

Template per tool (use this for every subsection):

```markdown
### <Tool name>

**Upstream:** <URL>
**What it does:** <one sentence>
**Why it's installed:** <what workflow this supports at Hyperi>
**Why this tool:** <rationale vs alternatives>
```

Example (Bruno):

```markdown
### Bruno

**Upstream:** https://www.usebruno.com/
**What it does:** Git-native, local-first API client for REST/GraphQL/gRPC/WebSocket.
**Why it's installed:** API exploration and testing without leaking requests to a cloud service.
**Why this tool:** Chosen over Postman and Insomnia because Bruno is truly local-first with no account requirement, stores collections as plain-text `.bru` files suitable for version control, and has no telemetry. Postman now requires an account even for local use and pushes cloud sync; Insomnia's post-Kong-acquisition direction follows the same pattern.
```

- [ ] **Step 2: Fill in `developer` tier subsections**

Target 500-900 words. Cover every tool listed under the developer tier in the spec. Commit:

```bash
git add docs/TOOLS.md && git commit -m "docs(tools): developer tier rationale"
```

- [ ] **Step 3: Fill in `core` tier subsections**

Cover Slack, Linear CLI, JFrog CLI, WireGuard, wallpaper/avatar. Commit:

```bash
git add docs/TOOLS.md && git commit -m "docs(tools): core tier rationale"
```

- [ ] **Step 4: Fill in `rust` profile subsections**

Cover rustup, cargo, bacon, nextest, deny, tarpaulin, chef, cargo-sweep, sccache, mold. Commit:

```bash
git add docs/TOOLS.md && git commit -m "docs(tools): rust profile rationale"
```

- [ ] **Step 5: Fill in `iac` profile subsections**

Cover terraform, vault, helm, kubectl, k9s, kubectx/kubens, minikube, argocd, dive. Commit:

```bash
git add docs/TOOLS.md && git commit -m "docs(tools): iac profile rationale"
```

- [ ] **Step 6: Fill in `gui_extras` profile subsections**

Cover Freelens, Bruno, Podman Desktop, DBeaver, lazygit (Bruno example already provided above — use it verbatim). Commit:

```bash
git add docs/TOOLS.md && git commit -m "docs(tools): gui_extras profile rationale"
```

- [ ] **Step 7: Fill in `openvpn` profile + opt-out variables table**

Document openvpn3, indicator, netcfg fix; confirm opt-out table matches `group_vars/all.yml`. Commit:

```bash
git add docs/TOOLS.md && git commit -m "docs(tools): openvpn profile + opt-out vars table"
```

### Task 5.2: Update README.md

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Replace the Installation section with `--profile`-first examples**

```markdown
## Installation

The DFE developer environment installs as a set of composable profiles.

### Profiles

- **`developer`** — OSS-safe base for external contributors on DFE/ESH. No Hyperi internals.
- **`core`** — Hyperi internal tier (implies `developer`). Adds Slack, Linear, JFrog, WireGuard, branding.
- **`rust`** — Rust toolchain + cargo tooling.
- **`iac`** — Terraform, Vault, Helm, Kubernetes CLI set.
- **`gui_extras`** — Freelens, Bruno, Podman Desktop, DBeaver Community, lazygit.
- **`openvpn`** — Transitional legacy VPN (requires `core`). Scheduled for removal ~2026-06.

### Common invocations

    ./install.sh --profile developer          # External contributor (minimal)
    ./install.sh --profile core               # Hyperi dev (minimal)
    ./install.sh --profile core,all           # Hyperi + rust + iac + gui_extras
    ./install.sh --profile core,openvpn       # Hyperi + legacy VPN (transition)

### Opt-out individual tools

    ./install.sh --profile core --extra-vars "install_slack=false"

See [docs/TOOLS.md](docs/TOOLS.md) for the full tool list and rationale.

### Deprecations

- `--core` and `--all` are aliased (with a warning) for one release, then removed.
  Replace with `--profile core,rust,iac` and `--profile core,all` respectively.
- `--tags developer_core` is **not** aliased — scripts/CI using this tag must be
  updated to `--profile core,rust,iac`.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs(readme): switch installation section to --profile-first invocations"
```

### Task 5.3: Update CHANGELOG.md

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Add a new entry**

```markdown
## [Unreleased] — Role Structure Refactor

### Added
- Two-tier base split: `developer` (OSS-safe) and `core` (Hyperi internal).
- Profile-based installation via `--profile`: `rust`, `iac`, `gui_extras`, `openvpn`.
- Opt-out variables in `group_vars/all.yml` for user-facing apps.
- New tools in `developer`: `wl-clipboard`, `kcat`.
- New profile `gui_extras`: Freelens, Bruno, Podman Desktop, DBeaver Community, lazygit.
- WireGuard as the default Hyperi VPN (in `core`).
- OpenVPN moved to opt-in `openvpn` profile (transitional).
- Per-tool rationale document at `docs/TOOLS.md`.
- Bats tests for `install.sh --profile` validation.

### Changed
- `developer_core` role dissolved — contents redistributed into `developer`, `core`, `rust`, `iac`, `openvpn`.
- `playbooks/main.yml` restructured around the new role layout.
- Default install (`./install.sh` with no args) now runs `--profile developer` — a behaviour change for users expecting "install everything."

### Deprecated
- `--core` flag → use `--profile core,rust,iac`. Alias removed in next release.
- `--all` flag → use `--profile core,all`. Alias removed in next release.

### Removed
- NetBird CLI (removed in earlier commit, reaffirmed here).
- `developer_core` role directory.
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs(changelog): add role structure refactor entry"
```

### Task 5.4: Final verification + PR

- [ ] **Step 1: Run full verification**

```bash
ansible-playbook --syntax-check ansible/playbooks/main.yml -i ansible/inventories/localhost/inventory.yml
bats tests/bats/install_profile.bats
cd ansible && ./test.sh --matrix --limit ubuntu
```

All three must pass. If any fail, fix before proceeding.

- [ ] **Step 2: Push branch**

```bash
git push -u origin feat/role-structure-refactor
```

- [ ] **Step 3: Open PR**

```bash
gh pr create --title "Refactor Ansible roles into tiered profiles (developer/core + add-ons)" --body "$(cat <<'EOF'
## Summary

Implements the Track 1 role structure refactor per
`docs/plans/2026-04-18-role-structure-refactor-design.md`.

- Two-tier base: `developer` (OSS-safe) + `core` (Hyperi internal)
- New profiles: `rust`, `iac`, `gui_extras`, `openvpn`
- `--profile` invocation replaces ad-hoc `--tags` (legacy `--core`/`--all` aliased with deprecation)
- Opt-out vars for user-facing apps
- WireGuard default in `core`; OpenVPN now transitional opt-in
- New tools: wl-clipboard, kcat, Bruno, Podman Desktop, DBeaver, lazygit
- `developer_core` role deleted; contents redistributed
- Per-tool rationale in `docs/TOOLS.md`

## Test plan

- [ ] bats tests pass (`bats tests/bats/install_profile.bats`)
- [ ] Syntax check passes
- [ ] Check-mode profile matrix passes (`./test.sh --matrix`)
- [ ] `--profile developer` VM smoke test on Ubuntu 24.04 (devex VMID 9010 clone) + OSS-safe assertion
- [ ] `--profile core,all` VM smoke test on Ubuntu 24.04 (devex VMID 9010 clone)
- [ ] `--profile core,openvpn` VM smoke test (transition path)
- [ ] Peer review before merge

**Fedora coverage:** deferred — no Fedora test VM currently available. Fedora paths verified via check-mode matrix only. Follow-up issue to re-run the full matrix against Fedora once a test template exists on devex.hyperi.io.

## Follow-ups

- Track 2: Ubuntu 26.04 compatibility + DRAGONFLY gaps.
  Items flagged during audit in `docs/plans/2026-04-18-audit-findings.md`.
- Fedora VM smoke testing: provision a Fedora 42 template on
  `devex.hyperi.io` and re-run the full profile matrix against it.
EOF
)"
```

- [ ] **Step 4: Record PR URL and merge after review**

```bash
# PR URL returned by gh pr create
```

---

## Rollback plan

If the refactor must be reverted after merge:

1. **Revert the merge commit:** `git revert -m 1 <merge-sha>`. This restores `developer_core/` and the pre-refactor playbook.
2. **In-progress installs on the refactor branch:** advise users to roll back their VM to the pre-install snapshot rather than trying to un-install. The two-tier refactor touches many task files and partial reverts on a live host are error-prone.
3. **Tools added to BASE** (wl-clipboard, kcat, Bruno/Podman/DBeaver/Freelens/lazygit in gui_extras) disappear with the revert. If one of these is later deemed valuable independently, add back via a separate focused PR rather than a partial refactor cherry-pick.
4. **Deprecation aliases** (`--core`, `--all`) are still live in the refactor commit — users who hit the deprecation warning can keep using the old flags during the rollback window.
5. **WireGuard default** reverts with the rest; users already on WireGuard keep their peer config (the config file itself isn't in the repo).

## Related

- Spec: `docs/plans/2026-04-18-role-structure-refactor-design.md`
- Track 2 (pending): Ubuntu 26.04 compat, DRAGONFLY gaps
- DRAGONFLY source notes: `~/Downloads/DRAGONFLY.md`
