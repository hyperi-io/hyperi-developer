# Hyperi Developer Tools

Utility scripts for managing the Hyperi Developer Environment project.

## Release Management

### Automated Releases with semantic-release

This project uses [semantic-release](https://semantic-release.gitbook.io/) to automate version management and releases.

#### How It Works

1. **Commit with Conventional Commits** - Your commit messages determine the version bump:
   - `feat:` → Minor version bump (2.4.4 → 2.5.0)
   - `fix:` → Patch version bump (2.4.4 → 2.4.5)
   - `feat!:` or `BREAKING CHANGE:` → Major version bump (2.4.4 → 3.0.0)
   - `docs:`, `chore:`, `ci:` → No version bump

2. **Run Release Script** - Automatically:
   - Analyzes commits since last release
   - Determines version bump
   - Updates `VERSION` file
   - Updates `CHANGELOG.md`
   - Creates git tag
   - Pushes to GitHub
   - Creates GitHub release with notes

#### Usage

```bash
# Preview what would happen (dry-run)
./tools/release.sh --dry-run

# Create actual release
./tools/release.sh
```

#### Commit Message Examples

**Features (Minor Bump):**
```bash
git commit -m "feat: add PostgreSQL installation role"
git commit -m "feat(core): add Gitleaks secret detection"
```

**Bug Fixes (Patch Bump):**
```bash
git commit -m "fix: correct Vector GPG keys for Ubuntu"
git commit -m "fix(vm): accept static state for qemu-guest-agent"
```

**Breaking Changes (Major Bump):**
```bash
git commit -m "feat!: remove Ubuntu 22.04 support"
# OR
git commit -m "feat: migrate to Ansible 2.0

BREAKING CHANGE: Requires Ansible 2.0 or later"
```

**No Version Bump:**
```bash
git commit -m "docs: update README with macOS notes"
git commit -m "chore: clean up TODO.md"
git commit -m "ci: add GitHub Actions workflow"
```

#### Workflow Example

```bash
# 1. Work on features/fixes
git checkout -b feature/add-postgres
# ... make changes ...
git commit -m "feat: add PostgreSQL installation role"
git commit -m "fix: correct connection timeout"
git commit -m "docs: add PostgreSQL documentation"

# 2. Merge to main
git checkout main
git merge feature/add-postgres
git push origin main

# 3. Create release (analyzes all commits since last release)
./tools/release.sh

# Output:
# ✅ Bumped version: 2.4.4 → 2.5.0 (minor)
# ✅ Updated VERSION file
# ✅ Updated CHANGELOG.md
# ✅ Created tag v2.5.0
# ✅ Pushed to GitHub
# ✅ Created GitHub release
```

#### First-Time Setup

```bash
# Install dependencies
npm install

# Test dry-run
./tools/release.sh --dry-run
```

#### Configuration

- `.releaserc.json` - semantic-release configuration
- `package.json` - npm dependencies and scripts

#### Manual Release (Legacy)

If you need to create a release manually:

```bash
# Update VERSION file
echo "2.5.0" > VERSION

# Update CHANGELOG.md manually
# ... edit CHANGELOG.md ...

# Commit and tag
git add VERSION CHANGELOG.md
git commit -m "chore: Release v2.5.0"
git tag -a v2.5.0 -m "Release v2.5.0"
git push origin main --tags

# Create GitHub release
gh release create v2.5.0 --latest --notes "..."
```

## Git Utilities

### git-claude-contrib-fix.sh

Removes Claude AI from GitHub contributors list (if accidentally added via Co-Authored-By).

```bash
./tools/git/git-claude-contrib-fix.sh
```

### git-spill-cleanup.sh

Cleans up accidental file spills in git history.

```bash
./tools/git/git-spill-cleanup.sh
```

See [tools/git/README.md](git/README.md) for detailed documentation.

## Diagnostics

### hyperi-doctor

Read-only report on whether this host has drifted behind what this repo's
roles declare. Never applies anything and never needs sudo.

```bash
./tools/hyperi-doctor                              # scope from the applied-state stamp, or 'developer'
./tools/hyperi-doctor --tags developer-rust,soe     # explicit role scope
./tools/hyperi-doctor --quiet                       # missing packages only, for use as a gate
```

Checks two things:

- The applied-state stamp (`/var/lib/hyperi-developer/applied.json`, written
  by `ansible/playbooks/main.yml` at the end of a successful run): its age
  and applied git SHA against this checkout's HEAD. A missing stamp means
  this host predates the stamp, or was never provisioned by this repo --
  reported plainly, not as an error. The stamp also records how many
  components warned on that run, because optional components warn and
  continue: a run can finish successfully with tools missing, so a stamp on
  its own is not a clean bill of health.
- Declared `ansible.builtin.apt` / `ansible.builtin.dnf` /
  `community.general.homebrew` package names in the role task files for the
  resolved scope, checked against `dpkg-query` / `rpm` / `brew` on this host.

Package names built from a loop, a variable, or Jinja cannot be resolved by
static YAML parsing, and hyperi-doctor says so explicitly rather than
reporting a false clean bill of health -- see the "unresolved" count in its
output. Exits non-zero when a declared package is missing, so it can be used
as a gate.
