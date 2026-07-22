#!/usr/bin/env bash
#
# hyperi-update (Linux) — update everything the hyperi-developer installer set
# up on this workstation, in one command. Ubuntu/Debian (apt) and Fedora (dnf).
#
#   * System packages  (apt or dnf, incl. 3rd-party repos: docker, vscode,
#                       chrome, brave, git, k8s, azure, gcloud, opentofu, ...)
#   * Snap             (if installed)                   — needs sudo
#   * Flatpak          (apps + runtimes)                — user
#   * Firmware         (fwupd)                          — needs sudo
#   * uv tools         (gnome-extensions-cli, ...)      — user
#   * rustup           (Rust toolchains)                — user
#   * Claude Code CLI  (self-installed under ~/.local)  — user
#
# Each section is independent and self-guarding: a tool that isn't installed is
# skipped (printed, not fatal), and a failing step is recorded and reported in
# the summary without aborting the rest. At the end, if the system needs it, you
# get a reboot prompt (default: No).
#
# Run with:  hyperi-update          (confirms, then prompts once for sudo)
#            hyperi-update --yes    (no confirmation — for scripts/Ansible)
#            hyperi-update --help

set -uo pipefail

# Make user-level tools reachable even when launched from a GUI/.desktop entry
# that doesn't source the login shell (uv/rustup live in ~/.cargo/bin, claude in
# ~/.local/bin).
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

ASSUME_YES=0

usage() {
    cat <<EOF
hyperi-update — update system packages, Snap, Flatpak, firmware, uv tools,
                rustup and Claude Code in one go.

Usage:
  hyperi-update          Confirm, then run all updates (prompts once for sudo).
  hyperi-update --yes    Skip the confirmation. Still prompts for sudo unless
                         you have a cached ticket or passwordless sudo.
  hyperi-update --help   Show this help.
EOF
}

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    -y|--yes)  ASSUME_YES=1 ;;
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

# --- distro ----------------------------------------------------------------
# Which package manager, decided once. Detect by BINARY, not by /etc/os-release:
# what matters is whether the tool is there to run, and a Debian derivative we
# have never heard of still has apt-get.
PKG_MGR="none"
if have dnf; then
    PKG_MGR="dnf"
elif have apt-get; then
    PKG_MGR="apt"
fi

# --- confirm ---------------------------------------------------------------
# This touches every package on the box, so say so before doing it. --yes is
# how Ansible and any other unattended caller skips this.
if [[ "$ASSUME_YES" -eq 0 ]]; then
    printf '%s%shyperi-update%s will update EVERYTHING on this machine:\n\n' "$BOLD" "$BLUE" "$RESET"
    printf '  - all system packages (%s), including third-party repos\n' "${PKG_MGR}"
    have snap     && printf '  - snap packages\n'
    have flatpak  && printf '  - flatpak apps and runtimes\n'
    have fwupdmgr && printf '  - device firmware\n'
    have uv       && printf '  - uv tools\n'
    have rustup   && printf '  - rust toolchains\n'
    have cargo-install-update && printf '  - cargo-installed tools\n'
    have go       && printf '  - go-installed tools (gopls, govulncheck)\n'
    have npm      && printf '  - npm global tools + pnpm\n'
    printf '  - static release binaries (kind, argocd, kubeconform, kube-linter)\n'
    have claude   && printf '  - Claude Code CLI\n'
    printf '\nIt may take a while, and may ask to reboot at the end.\n\n'
    read -r -p "Proceed? [y/N] " confirm
    case "${confirm,,}" in
        y|yes) ;;
        *) printf 'Nothing done.\n'; exit 0 ;;
    esac
fi

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

# --- System packages -------------------------------------------------------
case "$PKG_MGR" in
    apt)
        section "APT — system packages"
        run "apt-get update"       sudo apt-get update
        run "apt-get full-upgrade" sudo apt-get -y full-upgrade
        run "apt-get autoremove"   sudo apt-get -y autoremove
        run "apt-get autoclean"    sudo apt-get -y autoclean
        ;;
    dnf)
        section "DNF — system packages"
        # --refresh forces metadata expiry, so a repo added minutes ago by the
        # installer is seen now rather than on dnf's next scheduled refresh.
        run "dnf upgrade"    sudo dnf -y --refresh upgrade
        run "dnf autoremove" sudo dnf -y autoremove
        # `clean packages`, not `clean all`: dropping the metadata too just
        # means re-downloading it on the next run for no benefit.
        run "dnf clean packages" sudo dnf -y clean packages
        ;;
    *)
        section "System packages"
        skip "neither dnf nor apt-get found"
        ;;
esac

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

# --- cargo-installed tools -------------------------------------------------
# rustup updates the TOOLCHAIN; the cargo-installed binaries (nextest, deny,
# cargo-audit, cargo-hack, typos, ...) are refreshed by cargo-update's
# `install-update`, which the rust role installs as `cargo-install-update`.
section "cargo tools"
if have cargo-install-update; then
    run "cargo install-update -a" cargo install-update -a
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
# pnpm via corepack (it rides Node, but pin it to latest here).
section "npm global tools"
if have npm; then
    run "npm update -g" npm update -g
    have corepack && run "corepack pnpm@latest" corepack prepare pnpm@latest --activate
else
    skip "npm not found"
fi

# --- Tier 3: static binaries with no repo/snap/lang-manager ----------------
# These ship only as a GitHub release asset, so nothing above refreshes them --
# re-fetch the latest here. Each downloads to a temp path and is only moved into
# place on success, so a failed fetch never breaks the working copy. Only tools
# already installed are touched. (kustomize's monorepo tag selection, aws-vault,
# tea and the single-distro re-fetch cases are not yet covered here -- re-run the
# playbook to refresh those.)
section "Static binaries (GitHub releases)"
case "$(uname -m)" in
    x86_64|amd64)  ARCH_DEB=amd64 ;;
    aarch64|arm64) ARCH_DEB=arm64 ;;
    *)             ARCH_DEB='' ;;
esac

gh_latest_tag() {  # <repo> -> newest release tag (empty on failure)
    curl -fsSL "https://api.github.com/repos/$1/releases/latest" 2>/dev/null \
        | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}

# refetch_raw <name> <repo> <asset-template>  -- a bare executable asset.
# Template may use {TAG} and {ARCH}.
refetch_raw() {
    local name="$1" repo="$2" tmpl="$3" tag asset url tmp
    have "$name" || { skip "$name not installed"; return; }
    tag="$(gh_latest_tag "$repo")"
    [[ -n "$tag" ]] || { FAILURES+=("$name (no release tag)"); return; }
    asset="${tmpl//\{TAG\}/$tag}"; asset="${asset//\{ARCH\}/$ARCH_DEB}"
    url="https://github.com/$repo/releases/download/$tag/$asset"
    tmp="$(mktemp)"
    if curl -fsSL "$url" -o "$tmp" && [[ -s "$tmp" ]]; then
        sudo install -m 0755 "$tmp" "/usr/local/bin/$name" && ok "$name -> $tag" \
            || FAILURES+=("$name (install)")
    else
        FAILURES+=("$name (download)")
    fi
    rm -f "$tmp"
}

# refetch_targz <name> <repo> <asset-template> <member>  -- extract <member>
# from a .tar.gz release asset. Template may use {TAG} and {ARCH}.
refetch_targz() {
    local name="$1" repo="$2" tmpl="$3" member="$4" tag asset url tmp dir
    have "$name" || { skip "$name not installed"; return; }
    tag="$(gh_latest_tag "$repo")"
    [[ -n "$tag" ]] || { FAILURES+=("$name (no release tag)"); return; }
    asset="${tmpl//\{TAG\}/$tag}"; asset="${asset//\{ARCH\}/$ARCH_DEB}"
    url="https://github.com/$repo/releases/download/$tag/$asset"
    tmp="$(mktemp)"; dir="$(mktemp -d)"
    if curl -fsSL "$url" -o "$tmp" && tar -xzf "$tmp" -C "$dir" "$member" 2>/dev/null \
        && [[ -s "$dir/$member" ]]; then
        sudo install -m 0755 "$dir/$member" "/usr/local/bin/$name" && ok "$name -> $tag" \
            || FAILURES+=("$name (install)")
    else
        FAILURES+=("$name (download)")
    fi
    rm -rf "$tmp" "$dir"
}

if [[ -n "$ARCH_DEB" ]]; then
    refetch_raw   kind        kubernetes-sigs/kind  "kind-linux-{ARCH}"
    refetch_raw   argocd      argoproj/argo-cd      "argocd-linux-{ARCH}"
    refetch_targz kubeconform yannh/kubeconform     "kubeconform-linux-{ARCH}.tar.gz" kubeconform
    # kube-linter's amd64 asset carries no arch suffix; arm64 does.
    if [[ "$ARCH_DEB" == arm64 ]]; then
        refetch_targz kube-linter stackrox/kube-linter "kube-linter-linux_arm64.tar.gz" kube-linter
    else
        refetch_targz kube-linter stackrox/kube-linter "kube-linter-linux.tar.gz" kube-linter
    fi
else
    skip "unknown CPU architecture ($(uname -m)) -- skipping static binaries"
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
# The two distros answer this completely differently, and getting it wrong is
# silent: /run/reboot-required simply never exists on Fedora, so the old
# apt-only check reported "no reboot required" on every Fedora box forever.
reboot_needed=1   # 1 = no (shell truth), 0 = yes
reboot_reason=""

case "$PKG_MGR" in
    apt)
        if [[ -f /run/reboot-required || -f /var/run/reboot-required ]]; then
            reboot_needed=0
            [[ -f /run/reboot-required.pkgs ]] &&
                reboot_reason="$(paste -sd, /run/reboot-required.pkgs)"
        fi
        ;;
    dnf)
        # `dnf needs-restarting`, NOT `-r`. In dnf5 the -r/--reboothint flag
        # "has no effect, kept for compatibility with DNF 4" -- passing it looks
        # right and does nothing. Plain needs-restarting IS the dnf4 -r
        # behaviour. Verified against dnf5 5.4.2 (F44) and 5.2.18 (F43); both
        # ship the subcommand in the base install, no plugin needed.
        #
        # Exit codes, verified rather than assumed:
        #   0 = no reboot needed
        #   1 = reboot needed
        #   2 = no such command (dnf5's code for an unknown subcommand)
        # So an unavailable subcommand cannot be mistaken for "reboot needed".
        sudo dnf needs-restarting >/dev/null 2>&1
        case "$?" in
            0) reboot_needed=1 ;;
            1) reboot_needed=0; reboot_reason="dnf needs-restarting" ;;
            *) skip "dnf needs-restarting unavailable — cannot tell if a reboot is needed" ;;
        esac
        ;;
esac

if [[ "$reboot_needed" -eq 0 ]]; then
    echo
    printf '%s%s    A reboot is required to finish applying updates.%s\n' "$BOLD" "$YELLOW" "$RESET"
    [[ -n "$reboot_reason" ]] &&
        printf '%s    Triggered by: %s%s\n' "$YELLOW" "$reboot_reason" "$RESET"
    if [[ "$ASSUME_YES" -eq 1 ]]; then
        printf '%s    --yes given: NOT rebooting. Reboot when convenient.%s\n' "$YELLOW" "$RESET"
    else
        read -r -p "    Reboot now? [y/N] " answer
        case "${answer,,}" in
            y|yes) printf '    Rebooting...\n'; sudo systemctl reboot ;;
            *)     printf '    Reboot skipped. Remember to reboot later.\n' ;;
        esac
    fi
else
    echo
    ok "No reboot required."
    # Keep the window readable when launched from the GUI app (non-interactive
    # stdin means double-clicked, not run from an existing terminal).
    if [[ ! -t 0 && "$ASSUME_YES" -eq 0 ]]; then
        read -r -p "    Press Enter to close." _ || true
    fi
fi
