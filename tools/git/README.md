# Git Utilities

Developer utilities for git repository management and cleanup.

## Table of Contents

- [Git Data Spill Cleanup](#git-data-spill-cleanup)
- [Git Claude Contributor Fix](#git-claude-contributor-fix)

---

# Git Data Spill Cleanup

## Overview

The `git-spill-cleanup.sh` utility safely removes sensitive data accidentally committed to git history. It uses git-filter-repo (modern, officially recommended tool) and provides automatic backups to prevent data loss.

## What is a Git Data Spill?

A "data spill" occurs when sensitive information is accidentally committed to a git repository, including:

- **Credentials**: API keys, passwords, access tokens, client secrets
- **Configuration files**: `.env` files, `secrets.yml`, `credentials.json`
- **Private keys**: SSH keys (id_rsa), TLS certificates (.pem, .key)
- **Personal data**: PII, customer data, internal documents
- **Proprietary code**: Trade secrets, internal algorithms
- **AI assistant artifacts**: `.claude/`, `CLAUDE.md`, `.cursor/`, `.codex/`, etc.

Even after removing the file in a new commit, the sensitive data remains in git history and can be accessed by anyone with repository access.

## Prerequisites

### Required Tools

#### git-filter-repo (Required)

Modern, fast, and safe replacement for `git filter-branch` (officially recommended by GitHub):

```bash
# Fedora/RHEL (recommended)
sudo dnf install git-filter-repo

# Ubuntu/Debian (recommended)
sudo apt update
sudo apt install git-filter-repo

# macOS Homebrew (recommended)
brew install git-filter-repo

# From source (if not available in system repos)
curl -O https://raw.githubusercontent.com/newren/git-filter-repo/main/git-filter-repo
chmod +x git-filter-repo
sudo mv git-filter-repo /usr/libexec/git-core/
```

**Important:** Always use your system's package manager (dnf, apt, brew) instead of pip. This ensures proper integration with git and system updates.

**Note:** If git-filter-repo is not installed, the script will display friendly installation guidance with platform-specific instructions.

### Repository Requirements

- Clean working directory (no uncommitted changes)
- Git repository with commit access
- Backup space in `~/.git-spill-backups/`

## Usage

### Quick Start

```bash
# Navigate to your repository
cd /path/to/your/repo

# List potentially sensitive files in history
./tools/git/git-spill-cleanup.sh --list

# Remove a specific file (dry run first)
./tools/git/git-spill-cleanup.sh --file .env --dry-run

# Actually remove it
./tools/git/git-spill-cleanup.sh --file .env

# Remove entire directory and all contents
./tools/git/git-spill-cleanup.sh --directory .claude

# Remove all AI assistant artifacts
./tools/git/git-spill-cleanup.sh --ai

# Force push changes
git push origin --force --all
```

### Command Line Options

```
Options:
    -f, --file FILE         Remove specific file from history
    -d, --directory DIR     Remove entire directory and all contents from history
    -p, --pattern PATTERN   Remove files matching pattern (e.g., "*.env")
    -s, --string STRING     Remove string/text from all files in history
    -r, --regex REGEX       Remove text matching regex from all files
    -l, --list              List common sensitive files in current history
    -b, --backup            Create backup only (no cleanup)
    --ai                    Remove AI assistant artifacts (.claude, CLAUDE.md, etc.)
    --no-backup             Skip backup creation (dangerous!)
    --dry-run               Show what would be done without doing it
    -h, --help              Show this help message
```

## Common Scenarios

### Scenario 1: Removed .env File

You committed a `.env` file with database passwords:

```bash
# 1. Check what will be removed
./tools/git/git-spill-cleanup.sh --file .env --dry-run

# 2. Create backup and remove
./tools/git/git-spill-cleanup.sh --file .env

# 3. Review changes
git log --oneline --all

# 4. Force push
git push origin --force --all
git push origin --force --tags

# 5. Rotate all credentials in that .env file!
```

### Scenario 2: AWS Keys in Config File

You committed AWS credentials in `config/aws.yml`:

```bash
# Remove the specific file
./tools/git/git-spill-cleanup.sh --file config/aws.yml

# Force push
git push origin --force --all

# Rotate AWS keys immediately
aws iam delete-access-key --access-key-id AKIAIOSFODNN7EXAMPLE
```

### Scenario 3: API Key Hardcoded in Source

You hardcoded an API key like `sk-abc123secretkey` in source code:

```bash
# Remove the string from all files in history
./tools/git/git-spill-cleanup.sh --string "sk-abc123secretkey"

# Force push
git push origin --force --all

# Revoke and regenerate the API key
```

### Scenario 4: Multiple .env Files

You have multiple environment files (`.env`, `.env.local`, `.env.production`):

```bash
# Remove all .env files using pattern
./tools/git/git-spill-cleanup.sh --pattern "*.env*"

# Or remove each one explicitly
./tools/git/git-spill-cleanup.sh --file .env
./tools/git/git-spill-cleanup.sh --file .env.local
./tools/git/git-spill-cleanup.sh --file .env.production

# Force push
git push origin --force --all
```

### Scenario 5: Private Keys

You committed SSH private keys:

```bash
# Remove all private key files
./tools/git/git-spill-cleanup.sh --pattern "id_rsa*"
./tools/git/git-spill-cleanup.sh --pattern "*.pem"
./tools/git/git-spill-cleanup.sh --pattern "*.key"

# Force push
git push origin --force --all

# Generate new SSH keys
ssh-keygen -t ed25519 -C "your_email@example.com"
```

### Scenario 6: AI Assistant Artifacts

You accidentally committed AI assistant session files that contain private context:

```bash
# Preview what will be removed (dry run)
./tools/git/git-spill-cleanup.sh --ai --dry-run

# Remove all AI artifacts (.claude, CLAUDE.md, .cursor, .codex, etc.)
./tools/git/git-spill-cleanup.sh --ai

# Force push
git push origin --force --all
```

**Supported AI assistants:**
- **Claude Code** - `.claude/`, `CLAUDE.md`, `STATE.md`
- **Cursor** - `.cursor/`
- **Aider** - `.aider/`, `.aider.*`, `.aiderignore`
- **Continue** - `.continue/`
- **GitHub Copilot** - `.copilot/`
- **Windsurf/Codeium** - `.windsurf/`, `.codeium/`
- **Tabnine** - `.tabnine/`, `.tabnineignore`, `.tabnine_root`
- **Codex** - `.codex/`, `codex.md`
- **Cline** (formerly Claude Dev) - `.cline/`
- **Replit AI** - `.replit/`, `replit.nix`
- **Generic patterns** - `*.ai-session`, `.ai-cache/`

### Scenario 7: Remove Entire Directory

You committed a directory containing sensitive configuration:

```bash
# Preview what will be removed
./tools/git/git-spill-cleanup.sh --directory config/secrets --dry-run

# Remove the entire directory and all its contents
./tools/git/git-spill-cleanup.sh --directory config/secrets

# Force push
git push origin --force --all
```

**Note:** The `--directory` option removes the directory and ALL files within it from the entire git history.

## Team Coordination

### Before Cleanup

1. **Notify team**: Warn about upcoming history rewrite
2. **Schedule downtime**: Pick low-activity period
3. **Document**: Record what's being removed and why
4. **Branch protection**: Temporarily disable if enabled

### After Cleanup

1. **Force push**: Update remote repository
2. **Notify team**: Send re-clone instructions
3. **Monitor**: Watch for issues or questions

### Team Re-clone Instructions

Send this to your team:

```
IMPORTANT: Repository history has been rewritten to remove sensitive data.

ACTION REQUIRED:
1. Save any uncommitted work (stash or commit to a branch)
2. Delete your local clone
3. Re-clone the repository:
   git clone <repository-url> <new-directory>
4. Reapply your uncommitted work

DO NOT:
- Do NOT pull or merge (this will bring back old history)
- Do NOT push old branches (will reintroduce sensitive data)

Questions? Contact <your-name>
```

## Security Best Practices

### Immediate Actions

After removing sensitive data:

1. **Rotate credentials**: Assume compromised
2. **Monitor logs**: Check for unauthorized access
3. **Update .gitignore**: Prevent future commits
4. **Review access**: Audit who had repository access

### Prevention

Add to your `.gitignore`:

```gitignore
# Environment files
.env
.env.*
!.env.example

# Credentials
*credentials*
*secrets*
*secret*
*.pem
*.key
*.pfx
*.p12

# SSH keys
id_rsa*
*.ppk

# Cloud provider credentials
.aws/credentials
.azure/credentials
.gcloud/credentials

# AI Assistant artifacts
.claude/
.cursor/
.aider/
.aider.*
.continue/
.copilot/
.windsurf/
.codeium/
.tabnine/
.codex/
.cline/
.replit/
CLAUDE.md
STATE.md
*.ai-session
.ai-cache/
```

---

# Git Claude Contributor Fix

## Overview

The `git-claude-contrib-fix.sh` utility removes Claude Code from GitHub's contributors list when it autonomously adds itself without permission.

## The Problem

Claude Code sometimes adds "Co-Authored-By: Claude" attribution to commits without explicit user consent. This causes Claude to appear as a repository contributor on GitHub, which may not be desired for your project.

### Real Example

You ask Claude Code: *"Update the semver and push"*

Claude Code:
1. ✅ Updates the version file
2. ✅ Creates a commit
3. ❌ **Autonomously adds** `Co-Authored-By: Claude <noreply@anthropic.com>` to the commit message
4. ❌ **Result:** Claude now appears in your GitHub contributors list

This was the scenario that prompted this script's creation when bumping v2.1.2 → v2.1.3 in a project.

## How It Works

### For Default Branch (main/master)

Forces GitHub to recalculate contributors by:

1. Cloning a fresh copy of the repository
2. Removing Claude attribution from all commits using git-filter-repo
3. Creating a temporary orphan branch
4. Setting it as default (triggers GitHub reindex)
5. Verifying Claude is removed from contributors
6. Restoring original default branch
7. Cleanup

**Requires:** GitHub CLI (`gh`) for API access

### For Non-Default Branches

Simpler process:

1. Removes Claude attribution from commits
2. Force pushes the clean branch

**Doesn't require:** GitHub CLI (no reindex needed)

## Prerequisites

### Required

- **git** - For repository operations
- **Push access** - To the target repository

### Optional

- **gh (GitHub CLI)** - Only required when working on the default branch
  ```bash
  # Fedora
  sudo dnf install gh

  # Ubuntu/Debian
  sudo apt install gh

  # macOS
  brew install gh

  # Authenticate
  gh auth login
  ```

## Usage

### Quick Start

```bash
# Navigate to your repository
cd /path/to/your/repo

# Remove Claude from default branch
./tools/git/git-claude-contrib-fix.sh

# Or specify a repository URL
./tools/git/git-claude-contrib-fix.sh https://github.com/owner/repo.git
```

### Command Line Options

```
USAGE:
    ./git-claude-contrib-fix.sh [REPO_URL] [BRANCH]
    ./git-claude-contrib-fix.sh --help

ARGUMENTS:
    REPO_URL    Optional. GitHub repository URL (HTTPS or SSH)
                If not provided, uses the current repository's remote URL

    BRANCH      Optional. Branch to clean (default: repository's default branch)
                If specified branch is NOT the repo's default branch, only
                removes Claude attribution from commits (no GitHub reindex)

OPTIONS:
    --help      Show this help message and exit
```

## Examples

### Example 1: Current Repository

You're in a git repository and want to clean the default branch:

```bash
./tools/git/git-claude-contrib-fix.sh
```

### Example 2: Specific Repository

Clean a specific repository's default branch:

```bash
./tools/git/git-claude-contrib-fix.sh https://github.com/hyperi-io/hyperi-developer.git
```

### Example 3: Specific Branch

Clean a specific non-default branch (no GitHub reindex):

```bash
./tools/git/git-claude-contrib-fix.sh https://github.com/owner/repo.git feature-branch
```

### Example 4: Different Default Branch

Clean a repository that uses `develop` as default:

```bash
./tools/git/git-claude-contrib-fix.sh https://github.com/owner/repo.git develop
```

## What Gets Removed

The script removes these patterns from commit messages:

- `Co-Authored-By: Claude <noreply@anthropic.com>`
- `🤖 Generated with [Claude Code](https://claude.com/claude-code)`

After removal, commits are rewritten and force-pushed to the repository.

## Verification

After running the script:

1. Check GitHub contributors page: `https://github.com/owner/repo/graphs/contributors`
2. Verify Claude (noreply@anthropic.com) is removed
3. Check commit messages: `git log --all --grep="Co-Authored-By: Claude"`
4. Should return no results

## Prevention

### Add to .gitignore

Prevent committing AI artifacts:

```gitignore
# AI Assistant artifacts
.claude/
.cursor/
.aider/
.aider.*
.continue/
.copilot/
.windsurf/
.codeium/
.tabnine/
.codex/
.cline/
.replit/
CLAUDE.md
STATE.md
*.ai-session
.ai-cache/
```

### Pre-commit Hooks

Block Claude attribution:

```bash
# .git/hooks/commit-msg
#!/bin/bash
if grep -q "Co-Authored-By: Claude" "$1"; then
    echo "ERROR: Commit contains Claude attribution!"
    exit 1
fi
```

### Review Before Pushing

Always review commits before pushing:

```bash
git log -1 --pretty=fuller
```

Look for unwanted "Co-Authored-By" lines.

---

## Troubleshooting

### Git Data Spill Cleanup

#### Error: "Not in a git repository"

```bash
# Solution: Navigate to repository root
cd /path/to/your/repo
git rev-parse --git-dir  # Should show .git
```

#### Error: "Working directory is not clean"

```bash
# Solution: Commit or stash changes
git status
git add .
git commit -m "Save work before cleanup"
# Or
git stash save "Work in progress"
```

#### Error: "git-filter-repo not found"

The script will automatically display friendly installation guidance with platform-specific instructions. Simply follow the displayed instructions to install git-filter-repo, then run the script again.

```bash
# The script shows instructions like:
# Fedora: sudo dnf install git-filter-repo
# Ubuntu: sudo apt install git-filter-repo
# macOS: brew install git-filter-repo
```

### Git Claude Contributor Fix

#### Error: "gh command not found"

Only needed for default branch operations.

```bash
# Install GitHub CLI
sudo dnf install gh     # Fedora
sudo apt install gh     # Ubuntu
brew install gh         # macOS

# Authenticate
gh auth login
```

#### Error: "Permission denied"

You need push access to the repository:

```bash
# Check your remote URL
git remote -v

# If using HTTPS, may need to authenticate
gh auth login

# If using SSH, check SSH key
ssh -T git@github.com
```

#### Contributors List Not Updated

GitHub caching may delay the update:

1. Wait 5-10 minutes
2. Force refresh: Ctrl+Shift+R (or Cmd+Shift+R on macOS)
3. Check in incognito mode
4. If still showing after 1 hour, run script again

## Related Tools

Both utilities complement each other:

- **git-spill-cleanup.sh**: Comprehensive data removal including `--ai` option for all AI artifacts
- **git-claude-contrib-fix.sh**: Specialized for removing Claude from GitHub contributors

## License

(c) 2026 HYPERI PTY LIMITED

Licensed under the Apache License, Version 2.0. See [../../LICENSE](../../LICENSE) file for details.

## See Also

- [GitHub: Removing sensitive data](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository)
- [git-filter-repo Documentation](https://github.com/newren/git-filter-repo)
- [GitHub CLI Documentation](https://cli.github.com/manual/)
