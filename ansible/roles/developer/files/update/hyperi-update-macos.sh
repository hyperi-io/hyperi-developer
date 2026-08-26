#!/usr/bin/env zsh
#
# hyperi-update (macOS) — update everything the hyperi-developer installer set
# up on this machine, in one command.
#
#   * Homebrew         (formulae + casks: aws, gh, az, kubectl, helm,
#                       opentofu, openbao, gcloud-cli, ...)
#   * macOS updates    (softwareupdate)                  — needs sudo
#   * uv tools         (gnome-extensions-cli, ...)       — user
#   * rustup           (Rust toolchains)                 — user
#   * cargo tools      (nextest, deny, cargo-audit, ...) — user
#   * go tools         (gopls, govulncheck)              — user
#   * npm globals      (maid, semantic-release, pnpm)    — user
#   * Claude Code CLI  (self-installed under ~/.local)   — user
#
# Tier 3 static binaries (kind, argocd, kubeconform, ...) come from Homebrew
# formulae on macOS, so the Homebrew section already refreshes them -- the
# GitHub re-fetch is a Linux-only concern.
#
# Each section is independent and self-guarding: a tool that isn't installed is
# skipped (printed, not fatal), and a failing step is recorded and reported in
# the summary without aborting the rest. At the end, if the system needs it, you
# get a reboot prompt (default: No).
#
# ONE confirmation, up front. After the y/N everything runs unattended -- sudo
# is taken immediately after the gate and kept alive -- and the only other
# question is the reboot prompt at the end.
#
# Run with:  hyperi-update            (confirms, then prompts once for sudo)
#            hyperi-update --yes      (no confirmation — for scripts/Ansible)
#            hyperi-update --install  (create the clickable "Hyperi Update" app)
#            hyperi-update --help

set -u
set -o pipefail
emulate -L zsh

# Make user-level tools reachable even when launched from the GUI app or a
# non-login shell (Ansible): brew lives outside the base PATH on both Apple
# silicon and Intel.
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

ASSUME_YES=0

# --- self-resolve: absolute path to this script (symlinks resolved) -------
SELF=${${(%):-%x}:A}

usage() {
    cat <<EOF
hyperi-update — update Homebrew, macOS, uv tools, rustup, cargo/go/npm tools
                and Claude Code in one go.

Usage:
  hyperi-update            Confirm, then run all updates (prompts once for sudo).
  hyperi-update --yes      Skip the confirmation. Still prompts for sudo unless
                           you have a cached ticket or passwordless sudo.
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
    "")         ;;
    *)          print -u2 "hyperi-update: unknown option '$1'"; usage; exit 2 ;;
esac

# Opt-in stack, absent on a machine that never enabled it.
ARCANE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hyperi/arcane"

# --- confirm ---------------------------------------------------------------
# This touches every formula, cask and system update on the box, so say so
# before doing it. --yes is how Ansible and any other unattended caller skips
# this -- and it is the ONLY question until the reboot prompt at the end.
if (( ! ASSUME_YES )); then
    printf '%s%shyperi-update%s will update EVERYTHING on this Mac:\n\n' "$BOLD" "$BLUE" "$RESET"
    have brew   && printf '  - all Homebrew formulae and casks (including --greedy self-updaters)\n'
    printf '  - macOS system and security updates\n'
    have uv     && printf '  - uv tools\n'
    have rustup && printf '  - rust toolchains\n'
    have cargo-install-update && printf '  - cargo-installed tools\n'
    have go     && printf '  - go-installed tools (gopls, govulncheck)\n'
    have npm    && printf '  - npm global tools + pnpm\n'
    have claude && printf '  - Claude Code CLI\n'
    [[ -f "$ARCANE_DIR/compose.yaml" ]] && printf '  - Arcane (pull + recreate)\n'
    printf '\nIt may take a while, and may ask to reboot at the end.\n\n'
    read -r "confirm?Proceed? [y/N] "
    case "${confirm:l}" in
        y|yes) ;;
        *) printf 'Nothing done.\n'; exit 0 ;;
    esac
fi

# --- sudo: ask once, keep alive -------------------------------------------
# softwareupdate needs root, and asking for it mid-run breaks the one-question
# contract -- authenticate here, straight after the gate, and keep the ticket
# alive for the long sections. NOPASSWD leaves no timestamp to refresh, so the
# keepalive only starts when a password was actually entered.
section "Authenticating (sudo)"
if sudo -n true 2>/dev/null; then
    ok "sudo authenticated (passwordless)"
elif [[ -t 0 ]] && sudo -v; then
    ok "sudo authenticated"
    ( while true; do sudo -n true 2>/dev/null; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) &
    SUDO_KEEPALIVE_PID=$!
    trap '[[ -n "${SUDO_KEEPALIVE_PID:-}" ]] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null' EXIT
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

# --- rustup toolchains -----------------------------------------------------
# rustup itself is updated by brew; this updates the toolchains it manages.
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
# No bulk updater for `go install` tools, so re-install @latest the ones that
# are already present (this adds nothing that was not there before).
section "go tools"
if have go; then
    for gt in \
        "gopls:golang.org/x/tools/gopls@latest" \
        "govulncheck:golang.org/x/vuln/cmd/govulncheck@latest"; do
        bin="${gt%%:*}"; mod="${gt#*:}"
        have "$bin" && run "go install $bin" go install "$mod"
    done
else
    skip "go not found"
fi

# --- npm global tools ------------------------------------------------------
# maid, semantic-release, typescript, tsx, ts-node -- global npm packages; plus
# pnpm via corepack.
section "npm global tools"
if have npm; then
    run "npm update -g" npm update -g
    have corepack && run "corepack pnpm@latest" corepack prepare pnpm@latest --activate
else
    skip "npm not found"
fi

# --- Claude Code -----------------------------------------------------------
# Run as the normal user (NOT under sudo) so it updates ~/.local, not root's.
section "Claude Code"
if have claude; then
    run "claude update" claude update
else
    skip "claude not found in PATH"
fi

# gcloud is intentionally NOT updated here: it is the brew cask 'gcloud-cli',
# so the Homebrew section already updates it, and `gcloud components update`
# would fork the version brew tracks from the one on disk.

# --- Arcane ----------------------------------------------------------------
# Arcane's own auto-updater deliberately skips Arcane's container, so the stack
# is pulled and recreated here instead. Only acts on a machine that opted in --
# the compose file is absent everywhere else, so no section otherwise.
if [[ -f "$ARCANE_DIR/compose.yaml" ]] && have docker; then
    section "Arcane"
    # colima's socket is not at /var/run/docker.sock, and a GUI-launched run
    # does not necessarily carry the .zshenv that points DOCKER_HOST at it.
    if [[ -z "${DOCKER_HOST:-}" && -S "$HOME/.colima/default/docker.sock" ]]; then
        export DOCKER_HOST="unix://$HOME/.colima/default/docker.sock"
    fi
    run "arcane pull"     docker compose --project-directory "$ARCANE_DIR" pull
    run "arcane recreate" docker compose --project-directory "$ARCANE_DIR" up -d
fi

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
