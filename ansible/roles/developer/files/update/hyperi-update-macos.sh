#!/usr/bin/env zsh
#
# hyperi-update (macOS) -- update everything the hyperi-developer installer set
# up on this machine, in one command.
#
#   * Homebrew         (formulae + casks: aws, gh, az, kubectl, helm,
#                       opentofu, openbao, gcloud-cli, claude-code, codex, ...)
#   * macOS updates    (softwareupdate)                  -- needs sudo
#   * uv tools         (gnome-extensions-cli, ...)       -- user
#   * uv Pythons       (patch releases of each minor)    -- user
#   * rustup           (Rust toolchains, where rustup is used) -- user
#   * cargo tools      (nextest, deny, cargo-audit, ...) -- user
#   * go tools         (gopls)                           -- user
#   * Node.js majors   (node@<newest LTS>, fnm for the rest) -- user
#   * npm globals      (npm, pnpm, maid, semantic-release) -- user
#   * pnpm globals     (eslint, prettier, typescript, ...) -- user
#   * Codex plugin     (claude plugin update)            -- user
#
# The release binaries Linux fetches (kind, argocd, kubeconform, ...) come from
# Homebrew formulae on macOS, so the Homebrew section already refreshes them.
# Claude Code and the Codex CLI are casks and ride that same section. Only the
# Codex plugin for Claude Code, which brew knows nothing about, needs one of its
# own.
#
# Each section is independent and self-guarding: a tool that isn't installed is
# skipped (printed, not fatal), and a failing step is recorded and reported in
# the summary without aborting the rest. A reboot an update needs is reported,
# never started, unless --ask was given.
#
# The password is asked for once, at the start, and nothing else asks.
#
# Run with:  hyperi-update            (one sudo password, then unattended)
#            hyperi-update --ask      (confirm first, and offer a reboot)
#            hyperi-update --install  (create the clickable "Hyperi Update" app)
#            hyperi-update --help

# emulate resets every option to zsh's defaults, so the strict options come after
# it or a failing `softwareupdate | tee` would report success.
emulate -L zsh
setopt nounset pipefail

# Make user-level tools reachable even when launched from the GUI app or a
# non-login shell (Ansible): brew lives outside the base PATH on both Apple
# silicon and Intel, and brew's rustup is keg-only, so its shims are never linked
# into the brew prefix.
export PNPM_HOME="${PNPM_HOME:-$HOME/.local/share/pnpm}"
export PATH="$HOME/.local/bin:${CARGO_HOME:-$HOME/.cargo}/bin:$HOME/go/bin:$HOME/.npm-global/bin:$PNPM_HOME:$PNPM_HOME/bin:/opt/homebrew/bin:/opt/homebrew/opt/rustup/bin:/usr/local/bin:/usr/local/opt/rustup/bin:$PATH"

ASSUME_YES=1

# --- self-resolve: absolute path to this script (symlinks resolved) -------
SELF=${${(%):-%x}:A}

usage() {
    cat <<EOF
hyperi-update -- update Homebrew, macOS, uv tools, rustup and cargo/go/npm/pnpm
                 tools in one go.

Usage:
  hyperi-update            Run all updates. Asks for the sudo password once,
                           unless sudo is already passwordless.
  hyperi-update --ask      Confirm before starting, and offer a reboot if one
                           is needed.
  hyperi-update --install  Create a clickable "Hyperi Update" app in /Applications.
  hyperi-update --help     Show this help.
EOF
}

# --- pretty output ---------------------------------------------------------
if [[ -t 1 ]]; then
    BOLD=$'\e[1m'; BLUE=$'\e[34m'; GREEN=$'\e[32m'; RED=$'\e[31m'
    YELLOW=$'\e[33m'; RESET=$'\e[0m'
else
    BOLD=''; BLUE=''; GREEN=''; RED=''; YELLOW=''; RESET=''
fi

typeset -a FAILURES

section() { printf '\n%s%s==> %s%s\n' "$BOLD" "$BLUE" "$1" "$RESET"; }
ok()      { printf '%s    \xe2\x9c\x93 %s%s\n'   "$GREEN" "$1" "$RESET"; }
skip()    { printf '%s    \xe2\x80\x93 %s%s\n'    "$YELLOW" "$1" "$RESET"; }

# run <label> <command...> : run a step, record failure but keep going.
run() {
    local label="$1"; shift
    if "$@"; then
        ok "$label"
    else
        printf '%s    \xe2\x9c\x97 %s (exit %d)%s\n' "$RED" "$label" "$?" "$RESET"
        FAILURES+=("$label")
    fi
}

# fail <label> : record a failure the same way run() does.
fail()    { printf '%s    \xe2\x9c\x97 %s%s\n' "$RED" "$1" "$RESET"; FAILURES+=("$1"); }

have() { command -v "$1" >/dev/null 2>&1; }

# Build a double-clickable .app that opens Terminal and runs this script.
# Uses osacompile (built into macOS) — no dependencies. The app tells Terminal
# to `exec` this script, so when the run finishes the shell exits and (if your
# Terminal profile is set to "close if the shell exited cleanly") the window
# closes by itself; a failed run leaves it open to read.
install_app() {
    if ! have osacompile; then
        fail "osacompile not found (not macOS?) — cannot build the app"
        return 1
    fi
    local app="/Applications/Hyperi Update.app"
    # Custom icon kept outside the bundle so re-installs never lose it; the
    # installer drops it here.
    local icon_store="$HOME/.local/share/hyperi-update/AppIcon.icns"
    section "Installing clickable app"

    rm -rf "$app"
    local tmp; tmp=$(mktemp -d)
    cat > "$tmp/run.applescript" <<EOF
tell application "Terminal"
	activate
	do script "exec " & quoted form of "$SELF"
end tell
EOF
    if ! osacompile -o "$app" "$tmp/run.applescript"; then
        fail "failed to build the app (no write access to /Applications?)"
        rm -rf "$tmp"
        return 1
    fi
    rm -rf "$tmp"

    # Apply the custom icon. osacompile apps read Contents/Resources/applet.icns;
    # remove the bundled Assets.car so it can't override our icns.
    if [[ -f "$icon_store" ]]; then
        cp "$icon_store" "$app/Contents/Resources/applet.icns"
        rm -f "$app/Contents/Resources/Assets.car"
    fi

    # Editing the bundle invalidates osacompile's signature: re-sign ad-hoc and
    # nudge the icon cache so Finder/Dock pick up the new icon.
    have codesign && codesign --force --deep --sign - "$app" >/dev/null 2>&1
    touch "$app"

    ok "created $app"
    printf '%s    Launch it from Spotlight/Launchpad as '\''Hyperi Update'\'', or drag it to the Dock.%s\n' "$GREEN" "$RESET"
    printf '%s    First launch asks permission to control Terminal — allow it once.%s\n' "$YELLOW" "$RESET"
}

case "${1:-}" in
    --install)  install_app; exit $? ;;
    -h|--help)  usage; exit 0 ;;
    -y|--yes)   ASSUME_YES=1 ;;
    --ask)      ASSUME_YES=0 ;;
    "")         ;;
    *)          print -u2 "hyperi-update: unknown option '$1'"; usage; exit 2 ;;
esac

# --- confirm ---------------------------------------------------------------
# Only with --ask: this touches every formula, cask and system update on the box.
if (( ! ASSUME_YES )); then
    printf '%s%shyperi-update%s will update EVERYTHING on this Mac:\n\n' "$BOLD" "$BLUE" "$RESET"
    have brew   && printf '  - all Homebrew formulae and casks (including --greedy self-updaters)\n'
    printf '  - macOS system and security updates\n'
    have uv     && printf '  - uv tools and uv-managed Pythons\n'
    have rustup && printf '  - rust toolchains\n'
    have cargo-install-update && printf '  - cargo-installed tools\n'
    have go     && printf '  - go-installed tools (gopls)\n'
    have npm    && printf '  - npm global tools + pnpm\n'
    have pnpm   && printf '  - pnpm global tools\n'
    have claude && printf '  - the Codex plugin for Claude Code, if installed\n'
    printf '\nIt may take a while, and may ask to reboot at the end.\n\n'
    read -r "confirm?Proceed? [y/N] "
    case "${confirm:l}" in
        y|yes) ;;
        *) printf 'Nothing done.\n'; exit 0 ;;
    esac
fi

# --- sudo: ask once, hold for the run -------------------------------------
# Homebrew and softwareupdate call sudo from their own children, which a ticket
# for this terminal does not always cover. A sudoers drop-in lets this user sudo
# without a password until the run exits, when the trap removes it.
SUDOERS_DROPIN=/etc/sudoers.d/zz-hyperi-update
section "Authenticating (sudo)"
# -k ignores a cached ticket, so only a standing NOPASSWD rule passes the first test.
if sudo -k -n true 2>/dev/null; then
    ok "sudo authenticated (passwordless)"
elif sudo -n true 2>/dev/null || { [[ -t 0 ]] && sudo -v; }; then
    trap 'sudo -n rm -f "$SUDOERS_DROPIN"' EXIT
    trap 'exit 130' INT TERM
    dropin_tmp="$(mktemp)"
    printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$(id -un)" >"$dropin_tmp"
    if sudo visudo -cqf "$dropin_tmp" &&
       sudo install -m 0440 -o root -g wheel "$dropin_tmp" "$SUDOERS_DROPIN"; then
        ok "sudo held until this run ends"
    else
        fail "sudo drop-in (later steps may ask for the password again)"
    fi
    rm -f "$dropin_tmp"
else
    printf '%s    \xe2\x9c\x97 sudo authentication failed — aborting%s\n' "$RED" "$RESET"
    printf '%s    No passwordless sudo and no terminal to prompt on.%s\n' "$RED" "$RESET"
    exit 1
fi

# --- System packages -------------------------------------------------------
section "Homebrew — system packages"
if have brew; then
    # Don't quarantine freshly-downloaded casks. Without this, every updated
    # app triggers the macOS Gatekeeper prompt on first launch.
    export HOMEBREW_CASK_OPTS="--no-quarantine"
    export HOMEBREW_NO_ENV_HINTS=1
    run "brew update"       brew update
    run "brew upgrade"      brew upgrade
    # Casks that self-update report no version to brew; --greedy catches them.
    run "brew upgrade --cask --greedy" brew upgrade --cask --greedy
    run "brew autoremove"   brew autoremove
    run "brew cleanup"      brew cleanup --prune=all
else
    skip "Homebrew not installed"
fi

# --- Node.js LTS majors ----------------------------------------------------
# brew upgrade keeps node@N on its major, so the newest LTS is installed and
# linked here. The other supported majors are fnm's (its section below).
NODE_SCHEDULE_URL='https://raw.githubusercontent.com/nodejs/Release/main/schedule.json'
NODE_OTHER_MAJORS=''
NODE_EOL_MAJORS=''

# node_majors <schedule.json> : the supported majors newest first, then the EOL ones.
node_majors() {
    python3 - "$1" 2>/dev/null <<'PY'
import datetime
import json
import re
import sys

today = datetime.datetime.now(datetime.UTC).date().isoformat()
with open(sys.argv[1], encoding="utf-8") as fh:
    lines = {k: v for k, v in json.load(fh).items() if re.fullmatch(r"v\d+", k)}
supported = sorted(
    (int(k[1:]) for k, v in lines.items() if v.get("lts", "9") <= today < v.get("end", "")),
    reverse=True,
)
eol = sorted(int(k[1:]) for k, v in lines.items() if v.get("end", "9") <= today)
print(" ".join(map(str, supported)))
print(" ".join(map(str, eol)))
PY
}

section "Node.js LTS majors"
node_schedule="$(mktemp)"
if ! have brew; then
    skip "Homebrew not installed"
elif curl -fsSL --connect-timeout 20 --max-time 600 "$NODE_SCHEDULE_URL" -o "$node_schedule" 2>/dev/null &&
     node_answer="$(node_majors "$node_schedule")" && [[ -n "${node_answer%%$'\n'*}" ]]; then
    node_supported="${node_answer%%$'\n'*}"
    NODE_EOL_MAJORS="${node_answer#*$'\n'}"
    node_system="${node_supported%% *}"
    NODE_OTHER_MAJORS="${node_supported#$node_system}"
    ok "supported LTS majors: $node_supported"
    if brew list --versions "node@$node_system" >/dev/null 2>&1; then
        ok "node@$node_system installed"
    else
        run "brew install node@$node_system" brew install "node@$node_system"
    fi
    # node@N can be an alias of the unversioned formula, so compare the binaries.
    node_linked="$(realpath "$(brew --prefix)/bin/node" 2>/dev/null)"
    node_wanted="$(realpath "$(brew --prefix "node@$node_system")/bin/node" 2>/dev/null)"
    if [[ -n "$node_wanted" && "$node_linked" == "$node_wanted" ]]; then
        ok "node@$node_system linked"
    else
        run "brew link node@$node_system" brew link --overwrite --force "node@$node_system"
    fi
else
    printf '%s    ! Node.js release schedule unreadable, Node majors left as they are%s\n' "$YELLOW" "$RESET"
fi
rm -f "$node_schedule"

# --- macOS system updates --------------------------------------------------
# Early, like the firmware section on Linux, so a slow Apple download overlaps
# nothing interactive. Output is kept: it is the only way to know a restart is
# pending, since macOS has no /run/reboot-required.
section "macOS system updates (Apple)"
SWU_LOG="$(mktemp)"
if have softwareupdate; then
    if sudo softwareupdate --install --all --agree-to-license 2>&1 | tee "$SWU_LOG"; then
        ok "softwareupdate"
    else
        fail "softwareupdate"
    fi
else
    skip "softwareupdate not found (not macOS?)"
fi

# --- uv tools --------------------------------------------------------------
# Run as the normal user (NOT sudo) so it updates the user's tools.
section "uv tools"
if have uv; then
    run "uv tool upgrade --all" uv tool upgrade --all
else
    skip "uv not found"
fi

# --- uv-managed Pythons ----------------------------------------------------
# Nothing else moves a uv-installed Python to a newer patch. `uv python upgrade`
# touches only the minors already installed and, without --default, adds no
# python or python3 shim. The superseded patch stays installed, since uv has no
# command that removes only those and a venv may still point at it.
section "uv Pythons"
if ! have uv; then
    skip "uv not found"
elif [[ "$(uv python list --only-installed --managed-python --output-format json 2>/dev/null)" != *'"version"'* ]]; then
    skip "uv manages no Pythons"
else
    run "uv python upgrade" uv python upgrade
fi

# --- rustup toolchains -----------------------------------------------------
# Only a Mac that already had rustup keeps it. The role gives every other Mac
# brew's rust formula, which the Homebrew section updates. `rustup update` moves
# the toolchains, and rustup itself too unless brew owns it.
section "rustup toolchains"
if have rustup; then
    run "rustup update" rustup update
else
    skip "rustup not found"
fi

# --- cargo-installed tools -------------------------------------------------
# rustup updates the TOOLCHAIN; the cargo-installed binaries (nextest, deny,
# cargo-audit, cargo-hack, typos, ...) are refreshed by cargo-update's
# `install-update`. --locked, because without it this undoes the flag the role
# installed each tool with.
section "cargo tools"
if have cargo-install-update; then
    run "cargo install-update -a --locked" cargo install-update -a --locked
else
    skip "cargo-install-update not found (install the cargo-update crate)"
fi

# --- go-installed tools ----------------------------------------------------
# No bulk updater for `go install` tools, so the one the role puts in ~/go/bin
# is re-installed @latest. govulncheck, gosec and flarectl are brew formulae on
# macOS, which the Homebrew section refreshes.
section "go tools"
GO_HOME="$HOME/go"
if have go; then
    # "<module> <version>" as built into the binary, so a gopls already at the
    # module's latest release is not rebuilt.
    built="$(go version -m "$GO_HOME/bin/gopls" 2>/dev/null | awk '$1 == "mod" {print $2, $3; exit}')"
    if [[ ! -x "$GO_HOME/bin/gopls" ]]; then
        skip "gopls not found in $GO_HOME/bin"
    elif [[ -n "$built" ]] && [[ "$(go list -m -f '{{.Version}}' "${built% *}@latest" 2>/dev/null)" == "${built#* }" ]]; then
        ok "gopls ${built#* } is current"
    else
        run "go install gopls" env GOPATH="$GO_HOME" GOBIN="$GO_HOME/bin" go install golang.org/x/tools/gopls@latest
    fi
else
    skip "go not found"
fi

# --- fnm Node majors -------------------------------------------------------
# Every supported major but the system one, plus any other major already
# installed, at its latest patch. A version past end of life is removed.
section "fnm Node majors"
if have fnm; then
    fnm_eol=(${=NODE_EOL_MAJORS})
    fnm_wanted=(${=NODE_OTHER_MAJORS})
    for version in ${(f)"$(fnm list 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | sort -u)"}; do
        major="${${version#v}%%.*}"
        if (( ${fnm_eol[(Ie)$major]} )); then
            run "fnm uninstall $version (end of life)" fnm uninstall "$version"
        elif (( ! ${fnm_wanted[(Ie)$major]} )); then
            fnm_wanted+=("$major")
        fi
    done
    if (( ${#fnm_wanted} == 0 )); then
        skip "no fnm Node majors to install or refresh"
    fi
    for fm in "${fnm_wanted[@]}"; do
        run "fnm install $fm" fnm install "$fm"
    done
else
    skip "fnm not found"
fi

# --- npm and pnpm global tools ---------------------------------------------
# npm itself, pnpm, semantic-release and maid are npm globals, and eslint,
# prettier, typescript and tsx are pnpm globals.
RELEASE_MIN_AGE="${HYPERI_RELEASE_MIN_AGE_DAYS:-7}"
[[ "$RELEASE_MIN_AGE" == <-> ]] || RELEASE_MIN_AGE=7
NPM_BEFORE="$(date -u -v-"${RELEASE_MIN_AGE}"d +%F)"
section "npm global tools"
if have npm; then
    run "npm and pnpm" npm install --global npm@latest pnpm@latest --before "$NPM_BEFORE"
    run "npm update -g" npm update --global --before "$NPM_BEFORE"
else
    skip "npm not found"
fi

section "pnpm global tools"
if have pnpm; then
    # --latest, because the roles install each global at its latest release and
    # the ranges pnpm recorded would otherwise hold them at that major. A
    # release inside the cooldown holds every global until it ages out.
    pnpm_out="$(env PNPM_CONFIG_MINIMUM_RELEASE_AGE="$((RELEASE_MIN_AGE * 1440))" pnpm update -g --latest 2>&1)"
    pnpm_rc=$?
    printf '%s\n' "$pnpm_out"
    if (( pnpm_rc == 0 )); then
        ok "pnpm update -g --latest"
    elif [[ "$pnpm_out" == *ERR_PNPM_NO_MATURE_MATCHING_VERSION* ]]; then
        printf '%s    ! pnpm globals held: a release is inside the %s-day cooldown%s\n' "$YELLOW" "$RELEASE_MIN_AGE" "$RESET"
    else
        fail "pnpm update -g --latest (exit $pnpm_rc)"
    fi
else
    skip "pnpm not found"
fi

# --- Codex plugin for Claude Code ------------------------------------------
# The codex binary is the `codex` cask, so the Homebrew section above already
# moved it; a marketplace plugin is outside brew and has its own update verb,
# which `claude update` does not cover. Gated on the plugin actually being
# installed as well as on claude, so a Mac that never opted into the AI tooling
# does not take an update attempt for a plugin it has never had. --json because
# the human-readable listing is not a contract; the id is, and it is
# plugin@marketplace.
#
# --yes because stdin is not a TTY under Ansible or the GUI app, which is the
# documented trigger for the confirmation prompt.
#
# A string test rather than `| grep -q`: grep exits on the first match and
# closes the pipe, the producer takes SIGPIPE, and under `set -o pipefail` the
# pipeline then reports failure on a MATCH. That would skip the update on
# exactly the Macs that have the plugin, intermittently, by output size.
section "Codex plugin (Claude Code)"
if ! have claude; then
    skip "claude not found in PATH"
elif [[ "$(claude plugin list --json 2>/dev/null)" == *codex@openai-codex* ]]; then
    run "claude plugin update codex" claude plugin update codex@openai-codex --yes
else
    skip "the Codex plugin is not installed"
fi

# gcloud is intentionally NOT updated here: it is the brew cask 'gcloud-cli',
# so the Homebrew section already updates it, and `gcloud components update`
# would fork the version brew tracks from the one on disk.

# --- Summary ---------------------------------------------------------------
section "Summary"
if (( ${#FAILURES} == 0 )); then
    printf '%s%s    All updates completed successfully.%s\n' "$BOLD" "$GREEN" "$RESET"
else
    printf '%s%s    Completed with %d issue(s):%s\n' "$BOLD" "$RED" "${#FAILURES}" "$RESET"
    for f in $FAILURES; do printf '%s      - %s%s\n' "$RED" "$f" "$RESET"; done
fi

# --- Reboot prompt (only if required) --------------------------------------
# softwareupdate says "restart" in its output when an installed update needs
# one; that output is the only signal macOS gives.
reboot_needed=1   # 1 = no (shell truth), 0 = yes
if [[ -s "$SWU_LOG" ]] && grep -qi 'restart' "$SWU_LOG"; then
    reboot_needed=0
fi
rm -f "$SWU_LOG"

if (( reboot_needed == 0 )); then
    echo
    printf '%s%s    A reboot is required to finish applying updates.%s\n' "$BOLD" "$YELLOW" "$RESET"
    if (( ASSUME_YES )); then
        printf '%s    --yes given: NOT rebooting. Reboot when convenient.%s\n' "$YELLOW" "$RESET"
    else
        read -r "answer?    Reboot now? [y/N] "
        case "${answer:l}" in
            y|yes) printf '    Rebooting...\n'; sudo shutdown -r now ;;
            *)     printf '    Reboot skipped. Remember to reboot later.\n' ;;
        esac
    fi
else
    echo
    ok "No reboot required."
    # Keep the window readable when launched from the GUI app (non-interactive
    # stdin means double-clicked, not run from an existing terminal).
    if [[ ! -t 0 ]] && (( ! ASSUME_YES )); then
        read -r "pause?    Press Enter to close." || true
    fi
fi

# Non-zero when any step failed, so a calling script or scheduler sees it.
(( ${#FAILURES} == 0 )) || exit 1
