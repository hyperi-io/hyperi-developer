#!/usr/bin/env bash
#
# hyperi-update (Linux) — update everything the hyperi-developer installer set
# up on this workstation, in one command. Ubuntu/Debian (apt) and Fedora (dnf).
#
#   * System packages  (apt or dnf, incl. 3rd-party repos: docker, vscode,
#                       chrome, brave, git, gh, node, k8s, azure, gcloud,
#                       opentofu, ...)
#   * Snap             (if installed)                   -- needs sudo
#   * Flatpak          (apps + runtimes)                -- user
#   * Firmware         (fwupd)                          -- needs sudo
#   * uv tools         (gnome-extensions-cli, ...)      -- user
#   * uv Pythons       (patch releases of each minor)   -- user
#   * rustup           (Rust toolchains)                -- user
#   * cargo, go, npm and pnpm global tools              -- user
#   * Go toolchain     (/usr/local/go, no upstream repo) -- needs sudo
#   * fnm Node majors  (the n-1 Node, per user)         -- user
#   * Release binaries (/usr/local/bin, no repo/snap)   -- needs sudo
#   * Claude Code CLI  (self-installed under ~/.local)  -- user
#   * Codex CLI        (re-run of the installer)        -- user
#   * Codex plugin     (claude plugin update)           -- user
#
# Anything a package repo, snap or flatpak carries is left to the system-package
# sections, and the sections after them cover only what nothing at the OS level
# refreshes.
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

# A GUI launch or a timer does not run the login shell, so a CARGO_HOME or
# RUSTUP_HOME declared there is missing here. Ask the login shell for it, or
# every cargo step below would act on ~/.cargo instead of the real home.
#
# The answer is read from sentinel lines, because a profile can print too, and
# only an absolute path is taken. It goes through a file rather than a pipe: a
# child a profile left in the background keeps a pipe open past the timeout.
if [[ -z "${CARGO_HOME:-}" || -z "${RUSTUP_HOME:-}" ]]; then
    login_env="$(mktemp)"
    # The login shell expands these, not this one.
    # shellcheck disable=SC2016
    timeout 30 bash -lc 'printf "HYPERI_ENV CARGO_HOME=%s\nHYPERI_ENV RUSTUP_HOME=%s\n" "$(printenv CARGO_HOME)" "$(printenv RUSTUP_HOME)"' \
        >"$login_env" 2>/dev/null </dev/null
    for var in CARGO_HOME RUSTUP_HOME; do
        [[ -n "${!var:-}" ]] && continue
        val="$(sed -n "s/^HYPERI_ENV $var=//p" "$login_env" | tail -n 1)"
        [[ "$val" == /* ]] && export "$var=$val"
    done
    rm -f "$login_env"
    unset login_env var val
fi
CARGO_BIN="${CARGO_HOME:-$HOME/.cargo}/bin"

# Make user-level tools reachable even when launched from a GUI/.desktop entry
# or the systemd unit, neither of which sources the login shell (rustup and the
# cargo tools live in the cargo home, uv and claude in ~/.local/bin, Go in
# /usr/local/go/bin, the go-installed tools in ~/go/bin and the pnpm globals in
# PNPM_HOME).
export PNPM_HOME="${PNPM_HOME:-$HOME/.local/share/pnpm}"
export FNM_DIR="${FNM_DIR:-$HOME/.local/share/fnm}"
export PATH="$HOME/.local/bin:$CARGO_BIN:/usr/local/go/bin:$HOME/go/bin:$PNPM_HOME:$PNPM_HOME/bin:$PATH"

ASSUME_YES=0

usage() {
    cat <<EOF
hyperi-update -- update system packages, Snap, Flatpak, firmware, uv tools
                 and Pythons, rustup, cargo/go/npm/pnpm tools, the Go
                 toolchain, release binaries, Claude Code and Codex in one go.

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

# fail <label> : record a failure the same way run() does, for steps that are
# not a single command (multi-step fetch-verify-replace sequences).
fail()    { printf '%s    \xe2\x9c\x97 %s%s\n' "$RED" "$1" "$RESET"; FAILURES+=("$1"); }

have() { command -v "$1" >/dev/null 2>&1; }

# Every network fetch is bounded, so a stalled mirror cannot hold the weekly
# timer run open indefinitely.
CURL_LIMITS=(--connect-timeout 20 --max-time 600)

# --- architecture ----------------------------------------------------------
# Debian-style token, used by both the Go toolchain section and the static
# release binaries further down. Decided once, here, rather than in whichever
# section happens to run first.
case "$(uname -m)" in
    x86_64|amd64)  ARCH_DEB=amd64 ;;
    aarch64|arm64) ARCH_DEB=arm64 ;;
    *)             ARCH_DEB='' ;;
esac

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

# Opt-in stack, absent on a machine that never enabled it.
ARCANE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hyperi/arcane"

# --- confirm ---------------------------------------------------------------
# This touches every package on the box, so say so before doing it. --yes is
# how Ansible and any other unattended caller skips this.
if [[ "$ASSUME_YES" -eq 0 ]]; then
    printf '%s%shyperi-update%s will update EVERYTHING on this machine:\n\n' "$BOLD" "$BLUE" "$RESET"
    printf '  - all system packages (%s), including third-party repos\n' "${PKG_MGR}"
    have snap     && printf '  - snap packages\n'
    have flatpak  && printf '  - flatpak apps and runtimes\n'
    have fwupdmgr && printf '  - device firmware\n'
    have uv       && printf '  - uv tools and uv-managed Pythons\n'
    have rustup   && printf '  - rust toolchains\n'
    have cargo-install-update && printf '  - cargo-installed tools\n'
    have go       && printf '  - go-installed tools in ~/go/bin (gopls, govulncheck, gosec, flarectl)\n'
    have npm      && printf '  - npm global tools + pnpm\n'
    have pnpm     && printf '  - pnpm global tools\n'
    printf '  - release binaries in /usr/local/bin that no package covers, and uv in ~/.local/bin on Ubuntu\n'
    have claude   && printf '  - Claude Code CLI\n'
    have codex    && printf '  - Codex CLI (re-run of the official installer)\n'
    have claude   && printf '  - the Codex plugin for Claude Code, if installed\n'
    [[ -f "$ARCANE_DIR/compose.yaml" ]] && printf '  - Arcane (pull + recreate)\n'
    printf '\nIt may take a while, and may ask to reboot at the end.\n\n'
    read -r -p "Proceed? [y/N] " confirm
    case "${confirm,,}" in
        y|yes) ;;
        *) printf 'Nothing done.\n'; exit 0 ;;
    esac
fi

# --- sudo: ask once, keep alive -------------------------------------------
# Probe with a real command, not `sudo -v`. Ubuntu 25.10+ replaced GNU sudo with
# sudo-rs, whose `-v` demands interactive authentication even where NOPASSWD
# grants the commands themselves — so `sudo -v` aborts this script on every
# passwordless box and under every unattended caller, which is exactly what
# --yes exists for.
#
# The keepalive only matters when a password was actually entered: NOPASSWD
# leaves no timestamp to refresh.
#
# cleanup stops the keepalive and removes the GitHub token file, however the run
# ends. Both start empty, so a value inherited from the caller's environment is
# never killed or deleted.
SUDO_KEEPALIVE_PID=''
GH_AUTH_HEADER=''
cleanup() {
    [[ -n "$SUDO_KEEPALIVE_PID" ]] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null
    [[ -n "$GH_AUTH_HEADER" ]] && rm -f "$GH_AUTH_HEADER"
    return 0
}
trap cleanup EXIT

# api.github.com allows 60 anonymous requests an hour per IP, so a token in the
# environment is sent when there is one. It goes to curl from a 0600 file rather
# than argv, and stops being exported so no child process inherits it.
gh_token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
if [[ -n "$gh_token" ]]; then
    GH_AUTH_HEADER="$(mktemp)"
    printf 'Authorization: Bearer %s\n' "$gh_token" >"$GH_AUTH_HEADER"
fi
unset gh_token
export -n GITHUB_TOKEN GH_TOKEN

section "Authenticating (sudo)"
if sudo -n true 2>/dev/null; then
    ok "sudo authenticated (passwordless)"
elif [[ -t 0 ]] && sudo -v; then
    ok "sudo authenticated"
    ( while true; do sudo -n true 2>/dev/null; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) &
    SUDO_KEEPALIVE_PID=$!
else
    printf '%s    \xe2\x9c\x97 sudo authentication failed — aborting%s\n' "$RED" "$RESET"
    printf '%s    No passwordless sudo and no terminal to prompt on.%s\n' "$RED" "$RESET"
    exit 1
fi

# --- System packages -------------------------------------------------------
# unattended-upgrades and the apt-daily timers take the dpkg lock on their own
# schedule. Without this wait the upgrade exits 100 and the run reports success
# for everything else, so the box looks updated and is not.
wait_for_apt_lock() {
    local waited=0
    while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 ||
          sudo fuser /var/lib/apt/lists/lock  >/dev/null 2>&1; do
        if [[ "$waited" -eq 0 ]]; then
            printf '    waiting for another apt process to finish...\n'
        fi
        if [[ "$waited" -ge 300 ]]; then
            fail "apt lock (held for 5 minutes)"
            return 1
        fi
        sleep 5
        waited=$((waited + 5))
    done
    return 0
}

case "$PKG_MGR" in
    apt)
        section "APT — system packages"
        wait_for_apt_lock
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
# Updates the Rust toolchains and rustup itself. The cargo-installed binaries
# are the next section's job.
section "rustup toolchains"
# rustup proxies in the cargo home with no rustup on PATH means the toolchain is
# not where the environment says it is, which is a fault to report, not a skip.
if have rustup; then
    run "rustup update" rustup update
elif [[ -e "$CARGO_BIN/cargo" ]]; then
    fail "rustup not found in $CARGO_BIN"
else
    skip "rustup not found"
fi

# --- cargo-installed tools -------------------------------------------------
# rustup updates the TOOLCHAIN; the cargo-installed binaries (nextest, deny,
# cargo-audit, cargo-hack, typos, ...) are refreshed by cargo-update's
# `install-update`, which the rust role installs as `cargo-install-update`.
# --locked, because without it this undoes the flag the role installed each
# tool with: install-update rebuilds against freshly resolved dependencies
# rather than the ones the author published a lockfile for.
section "cargo tools"
if have cargo-install-update; then
    run "cargo install-update -a --locked" cargo install-update -a --locked
elif grep -q '^"cargo-update ' "${CARGO_HOME:-$HOME/.cargo}/.crates.toml" 2>/dev/null; then
    fail "cargo-install-update not found in $CARGO_BIN (cargo tools are not being updated)"
else
    skip "cargo-install-update not found (install the cargo-update crate)"
fi

# --- npm and pnpm global tools ---------------------------------------------
# semantic-release, maid and wrangler are npm globals. eslint, prettier,
# typescript, tsx and ts-node are pnpm globals, which `npm update -g` never
# sees. pnpm itself is corepack's, so it is re-activated at latest first.
section "npm global tools"
if have npm; then
    run "npm update -g" npm update -g
    have corepack && run "corepack pnpm@latest" corepack prepare pnpm@latest --activate
else
    skip "npm not found"
fi

section "pnpm global tools"
if have pnpm; then
    # --latest, because the roles install each global at its latest release and
    # the ranges pnpm recorded would otherwise hold them at that major.
    run "pnpm update -g --latest" pnpm update -g --latest
else
    skip "pnpm not found"
fi

# --- Go toolchain ----------------------------------------------------------
# Go publishes no apt/dnf repo, so `apt/dnf upgrade` never moves it -- the
# playbook installs the current tarball into /usr/local/go and this section is
# what carries it forward. Same arrangement as rustup, where rustup-init
# bootstraps and `rustup update` tracks stable after that.
#
# The checksum is taken from the same go.dev index that gives the URL, so it
# guards against a corrupt or truncated download rather than against go.dev
# itself.
section "Go toolchain"
if [[ ! -x /usr/local/go/bin/go ]]; then
    skip "Go toolchain not found in /usr/local/go"
elif [[ -z "$ARCH_DEB" ]]; then
    skip "unsupported architecture $(uname -m)"
else
    go_installed="$(/usr/local/go/bin/go version 2>/dev/null | awk '{print $3}')"
    go_index="$(mktemp)"

    if ! curl -fsSL "${CURL_LIMITS[@]}" 'https://go.dev/dl/?mode=json' -o "$go_index" 2>/dev/null; then
        skip "could not reach go.dev — leaving ${go_installed:-the current toolchain} in place"
    else
        # The index lists newest first, so the first "version" is latest stable.
        go_latest="$(sed -n 's/.*"version": *"\(go[0-9.]*\)".*/\1/p' "$go_index" | head -1)"

        if [[ -z "$go_latest" ]]; then
            skip "could not parse the go.dev index — leaving $go_installed in place"
        elif [[ "$go_installed" == "$go_latest" ]]; then
            ok "$go_installed is current"
        else
            go_tgz="${go_latest}.linux-${ARCH_DEB}.tar.gz"
            # The index is pretty-printed and lists "sha256" a few lines after
            # the "filename" it belongs to, hence the -A window.
            go_sha="$(grep -A6 "\"$go_tgz\"" "$go_index" \
                | sed -n 's/.*"sha256": *"\([a-f0-9]\{64\}\)".*/\1/p' | head -1)"
            go_tmp="$(mktemp -d)"

            if [[ -z "$go_sha" ]]; then
                fail "Go toolchain: no checksum published for $go_tgz"
            elif ! curl -fsSL "${CURL_LIMITS[@]}" "https://go.dev/dl/${go_tgz}" -o "$go_tmp/$go_tgz"; then
                fail "Go toolchain: download of $go_tgz failed"
            elif ! printf '%s  %s\n' "$go_sha" "$go_tmp/$go_tgz" | sha256sum -c - >/dev/null 2>&1; then
                fail "Go toolchain: checksum mismatch on $go_tgz"
            # Only touch the live tree once the tarball is downloaded AND
            # verified, so a failed update leaves the working toolchain intact.
            elif sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf "$go_tmp/$go_tgz"; then
                ok "Go $go_installed -> $go_latest"
            else
                fail "Go toolchain: unpack failed"
            fi

            rm -rf "$go_tmp"
        fi
    fi

    rm -f "$go_index"
fi

# --- go-installed tools ----------------------------------------------------
# No bulk updater for `go install` tools, so each one the roles put in ~/go/bin
# is re-installed @latest. Keyed on the binary being in ~/go/bin rather than on
# PATH, because a dnf gosec or govulncheck would otherwise gain a second copy.
# After the Go toolchain section, so a toolchain it just moved builds them.
section "go tools"
GO_HOME="$HOME/go"
if have go; then
    go_found=0
    # The -X:<experiments> suffix a distro build carries is not part of the release.
    go_now="$(go env GOVERSION 2>/dev/null)"
    go_now="${go_now%%-X:*}"
    for gt in \
        "gopls:golang.org/x/tools/gopls@latest" \
        "govulncheck:golang.org/x/vuln/cmd/govulncheck@latest" \
        "gosec:github.com/securego/gosec/v2/cmd/gosec@latest" \
        "flarectl:github.com/cloudflare/cloudflare-go/cmd/flarectl@latest"; do
        bin="${gt%%:*}"; mod="${gt#*:}"
        [[ -x "$GO_HOME/bin/$bin" ]] || continue
        go_found=1
        # A tool is current when it was built by this toolchain from its module's
        # latest release. The binary records both.
        build_info="$(go version -m "$GO_HOME/bin/$bin" 2>/dev/null)"
        built_go="$(awk 'NR == 1 {print $2}' <<<"$build_info")"
        built="$(awk '$1 == "mod" {print $2, $3; exit}' <<<"$build_info")"
        if [[ -n "$built" && "${built_go%%-X:*}" == "$go_now" ]] &&
            [[ "$(go list -m -f '{{.Version}}' "${built% *}@latest" 2>/dev/null)" == "${built#* }" ]]; then
            ok "$bin ${built#* } is current"
            continue
        fi
        run "go install $bin" env GOPATH="$GO_HOME" GOBIN="$GO_HOME/bin" go install "$mod"
    done
    [[ "$go_found" -eq 1 ]] || skip "no go-installed tools in $GO_HOME/bin"
else
    skip "go not found"
fi

# --- fnm Node majors -------------------------------------------------------
# The SYSTEM node comes from the NodeSource repo and is already updated by the
# system-packages section. This refreshes the extra major fnm manages (the n-1
# slot) to its latest patch -- `fnm install <major>` is a no-op when it is
# already current.
section "fnm Node majors"
if have fnm; then
    fnm_majors="$(fnm list 2>/dev/null | sed -n 's/.*v\([0-9]\{1,\}\)\..*/\1/p' | sort -u)"
    if [[ -n "$fnm_majors" ]]; then
        for fm in $fnm_majors; do
            run "fnm install $fm" fnm install "$fm"
        done
    else
        skip "fnm has no Node versions installed"
    fi
else
    skip "fnm not found"
fi

# --- Release binaries ------------------------------------------------------
# These ship only as a release asset, with no package repo, snap or language
# manager to carry them, so the latest is fetched here. A download must match
# the sha256 its release publishes and be an ELF binary, and is then renamed
# into place, so a failed, truncated or tampered fetch leaves the working copy
# exactly as it was.
#
# Only a binary already in /usr/local/bin is touched, and only on the distro
# whose role installs it there, so a tool the other distro packages is never
# shadowed by a second copy. gron, a release binary on Fedora whose upstream has
# not released since 2022, is the one such tool left out.
section "Release binaries"

# Holds the source and digest of each binary installed into /usr/local/bin, so a
# release that has not moved is recognised without downloading it again.
STAMP_DIR=/var/lib/hyperi-update

# The invoking user's ETags and release documents, plus the stamps for the
# binaries installed into their own ~/.local/bin.
USER_STATE="${XDG_CACHE_HOME:-$HOME/.cache}/hyperi-update"

# A GitHub release's download directory, as a refetch template.
GH_DL='https://github.com/{REPO}/releases/download/{TAG}'

# Set by refetch when it replaced a binary, for a caller with a follow-up step.
REFETCH_REPLACED=0

is_elf() {  # <file> -> 0 if it begins with the ELF magic (7f 45 4c 46)
    [[ "$(head -c 4 "$1" 2>/dev/null | od -An -tx1 | tr -d ' \n')" == "7f454c46" ]]
}

sha256_of() {  # <file> -> its sha256, empty when unreadable
    sha256sum "$1" 2>/dev/null | cut -d' ' -f1
}

# installed_local <name> -> 0 if /usr/local/bin/<name> is a file under
# /usr/local. A copy found elsewhere on PATH (~/.local/bin, a package) is not
# the one these helpers manage, and refetching for it would add a second copy.
installed_local() {
    local real
    real="$(readlink -e "/usr/local/bin/$1" 2>/dev/null)" && [[ -f "$real" && "$real" == /usr/local/* ]]
}

# api_get <url> <file> : fetch a release document into <file>. The ETag of the
# last answer is sent back, and GitHub does not count the 304 that comes back
# for an unchanged document against the rate limit when the request carries a
# token. An anonymous 304 still counts. When the API refuses outright (the
# anonymous limit spent, an outage), the document from the last answer stands
# in, so a tool already current is not reported as a failure. The token goes to
# GitHub only.
api_get() {
    local key body etag hdr code auth=() cond=()
    key="$(printf '%s' "$1" | sha256sum | cut -c1-16)"
    body="$USER_STATE/api/$key.json"
    etag="$USER_STATE/api/$key.etag"
    mkdir -p "$USER_STATE/api" 2>/dev/null || return 1
    if [[ -n "$GH_AUTH_HEADER" && "$1" == https://api.github.com/* ]]; then
        auth=(-H "@$GH_AUTH_HEADER")
    fi
    if [[ -s "$body" && -s "$etag" ]]; then
        cond=(-H "If-None-Match: $(<"$etag")")
    fi
    hdr="$(mktemp)"
    code="$(curl -sSL "${CURL_LIMITS[@]}" "${auth[@]}" "${cond[@]}" -D "$hdr" -o "$2" \
        -w '%{http_code}' "$1" 2>/dev/null)"
    case "$code" in
        304) cp "$body" "$2" ;;
        200) cp "$2" "$body"
             sed -n 's/^[Ee][Tt][Aa][Gg]:[[:space:]]*//p' "$hdr" | tr -d '\r' | tail -n 1 >"$etag" ;;
        *)   if [[ -s "$body" ]]; then
                 cp "$body" "$2"
                 skip "GitHub API answered ${code:-nothing}, using the release document from the last run"
             else
                 code=''
             fi ;;
    esac
    rm -f "$hdr"
    [[ -n "$code" ]]
}

# release_tag <doc> [<min-age-days>] : the tag of a single release document,
# or, given an age, of the newest release in a list that is not a draft or a
# prerelease and was published at least that many days ago. The age rule is the
# one the roles apply through infrastructure_min_release_age_days.
release_tag() {
    python3 - "$1" "${2:-0}" 2>/dev/null <<'PY'
import json
import sys
import time

with open(sys.argv[1], encoding="utf-8") as fh:
    data = json.load(fh)
if isinstance(data, dict):
    print(data.get("tag_name", ""))
else:
    cutoff = time.strftime(
        "%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - int(sys.argv[2]) * 86400)
    )
    ready = sorted(
        (
            r
            for r in data
            if not r.get("draft")
            and not r.get("prerelease")
            and r.get("published_at")
            and r["published_at"] <= cutoff
        ),
        key=lambda r: r["published_at"],
        reverse=True,
    )
    print(ready[0]["tag_name"] if ready else "")
PY
}

# asset_digest <doc> <asset> [<tag>] : the sha256 GitHub publishes for <asset>
# in a release document or list, empty where the release predates asset
# digests. In a list only the release tagged <tag> is read, because an asset
# name without a version repeats in every release.
asset_digest() {
    python3 - "$1" "$2" "${3:-}" 2>/dev/null <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    data = json.load(fh)
for release in data if isinstance(data, list) else [data]:
    if sys.argv[3] and release.get("tag_name") != sys.argv[3]:
        continue
    for asset in release.get("assets") or []:
        if asset.get("name") == sys.argv[2]:
            digest = asset.get("digest") or ""
            print(digest[7:] if digest.startswith("sha256:") else "")
            sys.exit(0)
PY
}

# published_sum <url> <asset> : the asset's sha256 from a checksum file of
# "<digest> [*]<name>" lines, or from a file that holds one bare digest and
# nothing else.
published_sum() {
    local sums
    sums="$(curl -fsSL "${CURL_LIMITS[@]}" "$1" 2>/dev/null)" || return 1
    awk -v a="$2" '
        { n = $2; sub(/^\*/, "", n); sub(/^\.\//, "", n) }
        length($1) == 64 && $1 ~ /^[0-9a-f]+$/ {
            if (n == a) { print $1; found = 1; exit }
            if (NR == 1 && NF == 1) bare = $1
        }
        END { if (!found && NR == 1 && bare != "") print bare }' <<<"$sums"
}

# is_current <stamp> <binary> <key> / record <stamp> <binary> <key> : read or
# write the stamp that ties an installed binary to the release it came from.
# record runs with refetch's privilege, so a root-owned stamp is written as root.
is_current() {
    local line
    line="$(cat "$1" 2>/dev/null)" || return 1
    [[ "$line" == "$3 $(sha256_of "$2")" ]]
}

record() {
    "${priv[@]}" mkdir -p "${1%/*}" &&
        printf '%s %s\n' "$3" "$(sha256_of "$2")" | "${priv[@]}" tee "$1" >/dev/null
}

# unpack <format> <dir> <member> : print the path of the binary unpacked from
# <dir>/asset. Fails when the archive does not hold <member> as a regular file,
# so a symlink member cannot point the install at a file outside the archive.
unpack() {
    local out="$2/out"
    [[ "$1" == raw ]] && { printf '%s' "$2/asset"; return 0; }
    mkdir -p "$out"
    case "$1" in
        tar)        tar -xzf "$2/asset" -C "$out" "$3" ;;
        tar-nested) tar -xzf "$2/asset" -C "$out" --strip-components=1 --wildcards "*/$3" ;;
        zip)        unzip -q -o "$2/asset" "$3" -d "$out" ;;
        *)          return 1 ;;
    esac >/dev/null 2>&1 || return 1
    [[ ! -L "$out/$3" && -f "$out/$3" && -s "$out/$3" ]] && printf '%s' "$out/$3"
}

# place <dir> <name> <file> : install <file> as <dir>/<name> by renaming a
# sibling into place, so the binary is never missing or half-written.
place() {
    if "${priv[@]}" install -m 0755 "$3" "$1/.$2.new" && "${priv[@]}" mv -f "$1/.$2.new" "$1/$2"; then
        return 0
    fi
    "${priv[@]}" rm -f "$1/.$2.new"
    return 1
}

# fill <template> : expand a template from the repo, tag, arch and asset of the
# refetch call it runs inside, whose locals bash's dynamic scoping exposes here.
# Each replacement is quoted, so a & in a value is never read as the match.
fill() {
    local s="$1"
    s="${s//\{REPO\}/"$repo"}"; s="${s//\{TAG\}/"$tag"}"; s="${s//\{VER\}/"${tag#v}"}"
    s="${s//\{ARCH\}/"$arch"}"; s="${s//\{ASSET\}/"$asset"}"
    printf '%s' "$s"
}

# refetch [options] <name> <asset-template> [<member>...]
#   --repo OWNER/NAME  GitHub repo: the tag comes from its API, the asset from its downloads
#   --api URL          release document to read the tag from, for a forge other than GitHub
#   --url TEMPLATE     download URL (default: the GitHub release asset)
#   --digest SHA256    the asset's digest, already known to the caller
#   --sums TEMPLATE    checksum file to use where the release publishes no digest
#   --arch TOKEN       this machine's arch as the asset spells it (default: amd64/arm64)
#   --min-age DAYS     take the newest GitHub release at least DAYS old
#   --format FORMAT    raw (default), tar (members at the archive root),
#                      tar-nested (members one directory down) or zip
#   --dest DIR         where the binary lives (default /usr/local/bin, as root),
#                      any other directory is the invoking user's own
# Templates take {REPO} {TAG} {VER} {ARCH} {ASSET}, where {VER} is the tag
# without a leading v. The members default to <name>, and the first member is
# the binary that says whether the release is installed already.
refetch() {
    local repo='' api='' url_t='' want='' sums_t='' arch="$ARCH_DEB" min_age='' format=raw
    local dest=/usr/local/bin
    while [[ "${1:-}" == --* ]]; do
        case "$1" in
            --repo)    repo="$2" ;;
            --api)     api="$2" ;;
            --url)     url_t="$2" ;;
            --digest)  want="$2" ;;
            --sums)    sums_t="$2" ;;
            --arch)    arch="$2" ;;
            --min-age) min_age="$2" ;;
            --format)  format="$2" ;;
            --dest)    dest="$2" ;;
            *)         fail "refetch: unknown option $1"; return ;;
        esac
        shift 2
    done
    local name="$1" asset_t="$2"
    shift 2
    local members=("$@")
    [[ ${#members[@]} -gt 0 ]] || members=("$name")
    local tag='' asset='' url key doc tmp label stamp i m bin bins=() priv=()
    REFETCH_REPLACED=0

    if [[ "$dest" == /usr/local/bin ]]; then
        priv=(sudo)
        stamp="$STAMP_DIR/$name"
        installed_local "$name" || { skip "$name not installed in /usr/local/bin"; return; }
    else
        stamp="$USER_STATE/stamps/$name"
        if [[ ! -f "$dest/$name" || -L "$dest/$name" ]]; then
            skip "$name not installed in $dest"
            return
        fi
    fi

    if [[ -n "$min_age" ]]; then
        api="https://api.github.com/repos/$repo/releases?per_page=30"
    elif [[ -z "$api" && -n "$repo" ]]; then
        api="https://api.github.com/repos/$repo/releases/latest"
    fi
    doc="$(mktemp)"
    if [[ -n "$api" ]]; then
        if ! api_get "$api" "$doc"; then
            fail "$name: could not read the release from $api"
            rm -f "$doc"
            return
        fi
        tag="$(release_tag "$doc" "$min_age")"
        if [[ -z "$tag" ]]; then
            fail "$name: no release found${min_age:+ at least $min_age days old}"
            rm -f "$doc"
            return
        fi
    fi
    asset="$(fill "$asset_t")"
    [[ -n "$url_t" ]] || url_t="$GH_DL/{ASSET}"
    url="$(fill "$url_t")"
    [[ -n "$want" || ! -s "$doc" ]] || want="$(asset_digest "$doc" "$asset" "$tag")"
    rm -f "$doc"
    if [[ -z "$want" && -n "$sums_t" ]]; then
        want="$(published_sum "$(fill "$sums_t")" "$asset")"
        [[ -n "$want" ]] || { fail "$name: no published checksum for $asset"; return; }
    fi
    key="$url${want:+ $want}"
    label="${tag:-$asset}"

    # A bare asset IS the binary, so its digest settles this without a stamp,
    # which also catches an asset republished under the same URL.
    if [[ "$format" == raw && -n "$want" ]]; then
        if [[ "$(sha256_of "$dest/$name")" == "$want" ]]; then
            ok "$name $label is current"
            return
        fi
    elif is_current "$stamp" "$dest/$name" "$key"; then
        ok "$name $label is current"
        return
    fi

    tmp="$(mktemp -d)"
    if ! curl -fsSL "${CURL_LIMITS[@]}" "$url" -o "$tmp/asset" 2>/dev/null; then
        fail "$name: download of $asset failed"
        rm -rf "$tmp"
        return
    fi
    if [[ -n "$want" && "$(sha256_of "$tmp/asset")" != "$want" ]]; then
        fail "$name: $asset does not match its published sha256"
        rm -rf "$tmp"
        return
    fi
    for m in "${members[@]}"; do
        if ! bin="$(unpack "$format" "$tmp" "$m")"; then
            fail "$name: $m not found in $asset"
            rm -rf "$tmp"
            return
        fi
        if ! is_elf "$bin"; then
            fail "$name: $m from $asset is not an ELF binary"
            rm -rf "$tmp"
            return
        fi
        bins+=("$bin")
    done

    REFETCH_REPLACED=0
    for i in "${!members[@]}"; do
        [[ "$(sha256_of "${bins[$i]}")" == "$(sha256_of "$dest/${members[$i]}")" ]] && continue
        if ! place "$dest" "${members[$i]}" "${bins[$i]}"; then
            fail "$name: install of ${members[$i]} into $dest failed"
            rm -rf "$tmp"
            return
        fi
        REFETCH_REPLACED=1
    done
    record "$stamp" "$dest/$name" "$key"
    if [[ "$REFETCH_REPLACED" -eq 1 ]]; then
        ok "$name -> $label"
    else
        ok "$name $label is current"
    fi
    rm -rf "$tmp"
}

# kustomize is a monorepo whose /releases/latest can be a non-CLI component, so
# the newest kustomize CLI asset is taken from the releases list instead.
refetch_kustomize() {
    installed_local kustomize || { skip "kustomize not installed in /usr/local/bin"; return; }
    local doc url='' digest=''
    doc="$(mktemp)"
    if api_get "https://api.github.com/repos/kubernetes-sigs/kustomize/releases" "$doc"; then
        url="$(grep -oE "https://[^\"]*/kustomize_v[0-9.]+_linux_${ARCH_DEB}\.tar\.gz" "$doc" | head -1)"
        [[ -n "$url" ]] && digest="$(asset_digest "$doc" "${url##*/}")"
    fi
    rm -f "$doc"
    [[ -n "$url" ]] || { fail "kustomize: no CLI release asset found"; return; }
    if [[ -n "$digest" ]]; then
        refetch --url "$url" --digest "$digest" --format tar kustomize "${url##*/}"
    else
        refetch --url "$url" --format tar kustomize "${url##*/}"
    fi
}

if [[ -n "$ARCH_DEB" ]]; then
    # The other spellings of this machine's arch that release assets use.
    if [[ "$ARCH_DEB" == arm64 ]]; then
        ARCH_UNAME=aarch64 ARCH_MIXED=arm64 ARCH_X64=arm64
        FNM_ASSET=fnm-arm64.zip SD_TARGET=aarch64-unknown-linux-musl
    else
        ARCH_UNAME=x86_64 ARCH_MIXED=x86_64 ARCH_X64=x64
        FNM_ASSET=fnm-linux.zip SD_TARGET=x86_64-unknown-linux-gnu
    fi

    # --sums names the checksum file each release also publishes, used only
    # where the release carries no GitHub digest. kube-linter, fnm and sd
    # publish none, and yq's lists several hashes per line in its own format.
    refetch --repo kubernetes-sigs/kind --sums "$GH_DL/{ASSET}.sha256sum" kind "kind-linux-{ARCH}"
    refetch --repo argoproj/argo-cd --sums "$GH_DL/cli_checksums.txt" argocd "argocd-linux-{ARCH}"
    refetch --repo yannh/kubeconform --sums "$GH_DL/CHECKSUMS" --format tar kubeconform \
        "kubeconform-linux-{ARCH}.tar.gz"
    # kube-linter's amd64 asset carries no arch suffix; arm64 does.
    if [[ "$ARCH_DEB" == arm64 ]]; then
        refetch --repo stackrox/kube-linter --format tar kube-linter "kube-linter-linux_arm64.tar.gz"
    else
        refetch --repo stackrox/kube-linter --format tar kube-linter "kube-linter-linux.tar.gz"
    fi
    refetch --repo wagoodman/dive --sums "$GH_DL/dive_{VER}_checksums.txt" --format tar dive \
        "dive_{VER}_linux_{ARCH}.tar.gz"
    refetch --repo terraform-docs/terraform-docs --sums "$GH_DL/terraform-docs-{TAG}.sha256sum" \
        --format tar terraform-docs "terraform-docs-{TAG}-linux-{ARCH}.tar.gz"
    refetch --repo golangci/golangci-lint --sums "$GH_DL/golangci-lint-{VER}-checksums.txt" \
        --format tar-nested golangci-lint "golangci-lint-{VER}-linux-{ARCH}.tar.gz"
    refetch --repo jesseduffield/lazygit --sums "$GH_DL/checksums.txt" --arch "$ARCH_MIXED" \
        --format tar lazygit "lazygit_{VER}_linux_{ARCH}.tar.gz"
    refetch --repo rhysd/actionlint --sums "$GH_DL/actionlint_{VER}_checksums.txt" --format tar \
        actionlint "actionlint_{VER}_linux_{ARCH}.tar.gz"
    refetch --repo google/osv-scanner --sums "$GH_DL/osv-scanner_SHA256SUMS" osv-scanner \
        "osv-scanner_linux_{ARCH}"
    refetch --repo ByteNess/aws-vault --min-age 7 --sums "$GH_DL/aws-vault_sha256_checksums.txt" \
        aws-vault "aws-vault-linux-{ARCH}"
    refetch --repo hyperi-io/git-scrub --sums "$GH_DL/checksums.txt" --format tar-nested git-scrub \
        "git-scrub-{VER}-linux-{ARCH}.tar.gz"
    refetch --repo mozilla/sccache --arch "$ARCH_UNAME" --format tar-nested --sums "$GH_DL/{ASSET}.sha256" \
        sccache "sccache-{TAG}-{ARCH}-unknown-linux-musl.tar.gz"
    # The running server keeps the binary it started with, so a new one takes
    # over only once that server is replaced. The role's user unit is restarted
    # if it is running, otherwise an on-demand server is stopped and the next
    # build starts the new binary.
    if [[ "$REFETCH_REPLACED" -eq 1 ]]; then
        export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
        if systemctl --user is-active --quiet hyperi-sccache.service 2>/dev/null; then
            run "restart hyperi-sccache" systemctl --user try-restart hyperi-sccache.service
        else
            # Matched on the replaced binary rather than with `sccache
            # --stop-server`, whose new client cannot always talk to an old server.
            stale=()
            for p in $(pgrep -u "$(id -u)" -x sccache 2>/dev/null); do
                [[ "$(readlink "/proc/$p/exe" 2>/dev/null)" == "/usr/local/bin/sccache (deleted)" ]] && stale+=("$p")
            done
            if [[ ${#stale[@]} -gt 0 ]]; then
                run "stop the sccache server still running the old binary" kill "${stale[@]}"
            else
                skip "no sccache server running the old binary"
            fi
        fi
    fi
    refetch --repo Schniz/fnm --format zip fnm "$FNM_ASSET"
    refetch --api https://gitea.com/api/v1/repos/gitea/tea/releases/latest \
        --url 'https://dl.gitea.com/tea/{VER}/{ASSET}' --sums 'https://dl.gitea.com/tea/{VER}/{ASSET}.sha256' \
        tea "tea-{VER}-linux-{ARCH}"
    refetch --url 'https://downloads.hyperi.io/macbash/latest/{ASSET}' \
        --sums 'https://downloads.hyperi.io/macbash/latest/{ASSET}.sha256' macbash "macbash-linux-{ARCH}"

    case "$PKG_MGR" in
        apt)
            refetch --repo derailed/k9s --sums "$GH_DL/checksums.sha256" --format tar k9s \
                "k9s_Linux_{ARCH}.tar.gz"
            refetch_kustomize
            refetch --repo mikefarah/yq yq "yq_linux_{ARCH}"
            refetch --repo hadolint/hadolint --arch "$ARCH_MIXED" --sums "$GH_DL/checksums.sha256" \
                hadolint "hadolint-linux-{ARCH}"
            refetch --repo gitleaks/gitleaks --sums "$GH_DL/gitleaks_{VER}_checksums.txt" \
                --arch "$ARCH_X64" --format tar gitleaks "gitleaks_{VER}_linux_{ARCH}.tar.gz"
            refetch --repo nektos/act --sums "$GH_DL/checksums.txt" --arch "$ARCH_MIXED" --format tar \
                act "act_Linux_{ARCH}.tar.gz"
            # astral installs uv and uvx from this release into the user's own
            # ~/.local/bin on Ubuntu, where `uv self update` refuses to act on a
            # copy it did not install. Fedora and macOS take uv from dnf and brew.
            refetch --repo astral-sh/uv --dest "$HOME/.local/bin" --arch "$ARCH_UNAME" \
                --sums "$GH_DL/{ASSET}.sha256" --format tar-nested \
                uv "uv-{ARCH}-unknown-linux-gnu.tar.gz" uv uvx
            ;;
        dnf)
            refetch --repo chmln/sd --arch "$SD_TARGET" --format tar-nested sd "sd-{TAG}-{ARCH}.tar.gz"
            refetch --repo ahmetb/kubectx --min-age 7 --sums "$GH_DL/checksums.txt" --arch "$ARCH_MIXED" \
                --format tar kubectx "kubectx_{TAG}_linux_{ARCH}.tar.gz"
            refetch --repo ahmetb/kubectx --min-age 7 --sums "$GH_DL/checksums.txt" --arch "$ARCH_MIXED" \
                --format tar kubens "kubens_{TAG}_linux_{ARCH}.tar.gz"
            ;;
    esac
else
    skip "unknown CPU architecture ($(uname -m)) -- skipping release binaries"
fi

# --- Claude Code -----------------------------------------------------------
# The role installs the native build under ~/.local, whose own updater this is.
# Run as the normal user (NOT under sudo) so it updates ~/.local, not root's.
section "Claude Code"
if have claude; then
    run "claude update" claude update
else
    skip "claude not found in PATH"
fi

# --- Codex CLI -------------------------------------------------------------
# No apt/dnf repo, no snap, no language manager -- and not a release binary
# either, because the release asset is a package TREE that has to be staged and
# symlinked, not a bare executable refetch could drop into /usr/local/bin. So
# nothing above reaches it.
#
# Re-running the official installer IS the update path: it resolves the current
# release, verifies the package tarball against the published
# codex-package_SHA256SUMS, and short-circuits when the staged version is
# already current. There is no non-interactive `codex update` verb to prefer
# over it. The installer script has no published checksum of its own, so what
# the digest covers is the payload, not the script that fetches it.
#
# CODEX_NON_INTERACTIVE=1 is the installer's own knob for skipping prompts,
# which is what keeps this safe under --yes and the weekly timer. Run as the
# normal user (NOT under sudo) so it updates ~/.local/bin and ~/.codex, not
# root's.
section "Codex CLI"
if have codex; then
    codex_installer="$(mktemp)"
    if curl -fsSL "${CURL_LIMITS[@]}" https://chatgpt.com/codex/install.sh -o "$codex_installer"; then
        run "codex installer" env CODEX_NON_INTERACTIVE=1 sh "$codex_installer"
    else
        fail "Codex CLI: could not fetch the installer"
    fi
    rm -f "$codex_installer"
else
    skip "codex not found in PATH"
fi

# --- Codex plugin for Claude Code ------------------------------------------
# `claude update` moves the CLI only; a marketplace plugin has its own update
# verb. Gated on the plugin actually being installed as well as on claude, so
# a box that never opted into the AI tooling does not take an update attempt
# for a plugin it has never had. --json because the human-readable listing is
# not a contract; the id is, and it is plugin@marketplace.
#
# --yes because stdin is not a TTY under Ansible or the weekly timer, which is
# the documented trigger for the confirmation prompt.
#
# A string test rather than `| grep -q`: grep exits on the first match and
# closes the pipe, the producer takes SIGPIPE, and under `set -o pipefail` the
# pipeline then reports failure on a MATCH. That would skip the update on
# exactly the boxes that have the plugin, intermittently, by output size.
section "Codex plugin (Claude Code)"
if ! have claude; then
    skip "claude not found in PATH"
elif [[ "$(claude plugin list --json 2>/dev/null)" == *codex@openai-codex* ]]; then
    run "claude plugin update codex" claude plugin update codex@openai-codex --yes
else
    skip "the Codex plugin is not installed"
fi

# --- Arcane ----------------------------------------------------------------
# Arcane's own auto-updater deliberately skips Arcane's container, so the stack
# is pulled and recreated here instead. Only acts on a machine that opted in --
# the compose file is absent everywhere else. Unlike the tools above, Arcane is
# opt-in, so a machine without it is not a gap worth reporting -- no section.
if [[ -f "$ARCANE_DIR/compose.yaml" ]] && have docker; then
    section "Arcane"
    run "arcane pull"     docker compose --project-directory "$ARCANE_DIR" pull
    run "arcane recreate" docker compose --project-directory "$ARCANE_DIR" up -d
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

# Non-zero when any step failed, so a systemd unit or a caller sees it.
[[ ${#FAILURES[@]} -eq 0 ]] || exit 1
