#!/usr/bin/env bash
#
# hyperi-update (Linux) — update everything the hyperi-developer installer
# set up on this Ubuntu workstation, in one command:
#
#   * APT      (system + 3rd-party repos: docker, vscode, chrome, brave,
#              git, k8s, azure, gcloud, jfrog, ...)   — needs sudo
#   * Snap     (snap packages)                        — needs sudo
#   * Flatpak  (any flatpak apps + runtimes, e.g. onlyoffice fallback) — user
#   * Firmware (fwupd)                                — needs sudo
#   * uv tools (gnome-extensions-cli, ...)            — user
#   * rustup   (Rust toolchains)                      — user
#   * Claude Code CLI (self-installed under ~/.local) — user
#
# Each section is independent and self-guarding: a tool that isn't installed
# is skipped (printed, not fatal), and a failing step is recorded and reported
# in the summary without aborting the rest. At the end, if the system needs it,
# you get a reboot prompt (default: No).
#
# Run with:  hyperi-update      (prompts once for sudo)
#            hyperi-update --help

set -uo pipefail

# Make user-level tools reachable even when launched from a GUI/.desktop
# entry that doesn't source the login shell (uv/rustup live in ~/.cargo/bin,
# claude in ~/.local/bin).
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

usage() {
    cat <<EOF
hyperi-update — update APT, Snap, Flatpak, firmware, uv tools, rustup and
                Claude Code in one go.

Usage:
  hyperi-update          Run all updates now (prompts once for sudo).
  hyperi-update --help   Show this help.
EOF
}

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    "")        ;;
    *)         printf 'hyperi-update: unknown option %q\n' "$1" >&2; usage; exit 2 ;;
esac

# --- pretty output ---------------------------------------------------------
if [[ -t 1 ]]; then
    BOLD=$'\e[1m'; BLUE=$'\e[34m'; GREEN=$'\e[32m'; RED=$'\e[31m'
    YELLOW=$'\e[33m'; RESET=$'\e[0m'
else
    BOLD=''; BLUE=''; GREEN=''; RED=''; YELLOW=''; RESET=''
fi

FAILURES=()

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

have() { command -v "$1" >/dev/null 2>&1; }

# --- sudo: ask once, keep alive -------------------------------------------
section "Authenticating (sudo)"
if sudo -v; then
    ok "sudo authenticated"
    # refresh the sudo timestamp in the background until the script exits
    ( while true; do sudo -n true 2>/dev/null; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) &
    SUDO_KEEPALIVE_PID=$!
    trap '[[ -n "${SUDO_KEEPALIVE_PID:-}" ]] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null' EXIT
else
    printf '%s    \xe2\x9c\x97 sudo authentication failed — aborting%s\n' "$RED" "$RESET"
    exit 1
fi

# --- APT -------------------------------------------------------------------
section "APT — system packages"
if have apt-get; then
    run "apt-get update"       sudo apt-get update
    run "apt-get full-upgrade" sudo apt-get -y full-upgrade
    run "apt-get autoremove"   sudo apt-get -y autoremove
    run "apt-get autoclean"    sudo apt-get -y autoclean
else
    skip "apt-get not found"
fi

# --- Snap ------------------------------------------------------------------
section "Snap — snap packages"
if have snap; then
    run "snap refresh" sudo snap refresh
else
    skip "snap not installed"
fi

# --- Flatpak ---------------------------------------------------------------
section "Flatpak — apps & runtimes"
if have flatpak; then
    run "flatpak update"          flatpak update -y
    run "flatpak remove --unused" flatpak uninstall --unused -y
else
    skip "flatpak not installed"
fi

# --- Firmware (fwupd) ------------------------------------------------------
section "Firmware — fwupd"
if have fwupdmgr; then
    # refresh metadata (don't fail the run if the remote is rate-limited)
    sudo fwupdmgr refresh --force >/dev/null 2>&1 || true
    if sudo fwupdmgr get-updates >/dev/null 2>&1; then
        run "fwupdmgr update" sudo fwupdmgr update -y --no-reboot-check
    else
        skip "no firmware updates available"
    fi
else
    skip "fwupd not installed"
fi

# --- uv tools --------------------------------------------------------------
# CLI tools installed via `uv tool install` (e.g. gnome-extensions-cli).
# Run as the normal user (NOT sudo) so it updates the user's tools.
section "uv tools"
if have uv; then
    run "uv tool upgrade --all" uv tool upgrade --all
else
    skip "uv not found"
fi

# --- rustup toolchains -----------------------------------------------------
# Updates the Rust toolchains. NOTE: cargo-installed binaries (nextest, deny,
# bacon, ...) are not refreshed by rustup; reinstall them with cargo if needed.
section "rustup toolchains"
if have rustup; then
    run "rustup update" rustup update
else
    skip "rustup not found"
fi

# --- Claude Code -----------------------------------------------------------
# Run as the normal user (NOT under sudo) so it updates ~/.local, not root's.
section "Claude Code"
if have claude; then
    run "claude update" claude update
else
    skip "claude not found in PATH"
fi

# --- Summary ---------------------------------------------------------------
section "Summary"
if [[ ${#FAILURES[@]} -eq 0 ]]; then
    printf '%s%s    All updates completed successfully.%s\n' "$BOLD" "$GREEN" "$RESET"
else
    printf '%s%s    Completed with %d issue(s):%s\n' "$BOLD" "$RED" "${#FAILURES[@]}" "$RESET"
    for f in "${FAILURES[@]}"; do printf '%s      - %s%s\n' "$RED" "$f" "$RESET"; done
fi

# --- Reboot prompt (only if required) --------------------------------------
if [[ -f /run/reboot-required || -f /var/run/reboot-required ]]; then
    echo
    printf '%s%s    A reboot is required to finish applying updates.%s\n' "$BOLD" "$YELLOW" "$RESET"
    if [[ -f /run/reboot-required.pkgs ]]; then
        printf '%s    Triggered by: %s%s\n' "$YELLOW" "$(paste -sd, /run/reboot-required.pkgs)" "$RESET"
    fi
    read -r -p "    Reboot now? [y/N] " answer
    case "${answer,,}" in
        y|yes) printf '    Rebooting...\n'; sudo systemctl reboot ;;
        *)     printf '    Reboot skipped. Remember to reboot later.\n' ;;
    esac
else
    echo
    ok "No reboot required."
    # Keep the window readable when launched from the GUI app (non-interactive
    # stdin means double-clicked, not run from an existing terminal).
    if [[ ! -t 0 ]]; then read -r -p "    Press Enter to close." _ || true; fi
fi
