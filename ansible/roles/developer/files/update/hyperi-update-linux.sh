#!/usr/bin/env bash
#
# hyperi-update (Linux) — update everything the hyperi-developer installer set
# up on this workstation, in one command. Ubuntu/Debian (apt) and Fedora (dnf).
#
#   * System packages  (apt or dnf, incl. 3rd-party repos: docker, vscode,
#                       chrome, brave, git, gh, node, k8s, azure, gcloud,
#                       opentofu, ...)
#   * Snap             (if installed)                   — needs sudo
#   * Flatpak          (apps + runtimes)                — user
#   * Firmware         (fwupd)                          — needs sudo
#   * uv tools         (gnome-extensions-cli, ...)      — user
#   * rustup           (Rust toolchains)                — user
#   * Go toolchain     (/usr/local/go, no upstream repo) — needs sudo
#   * fnm Node majors  (the n-1 Node, per user)         — user
#   * Claude Code CLI  (self-installed under ~/.local)  — user
#
# Note on the dev stacks: node, gh, docker and git come from UPSTREAM signed
# repos, so "System packages" above already carries them to latest -- there is
# nothing stack-specific to do for them here. Only the two that have no
# upstream repo (the Go toolchain, and fnm's Node majors) need their own
# sections, plus rustup, which manages its own toolchains.
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

# fail <label> : record a failure the same way run() does, for steps that are
# not a single command (multi-step fetch-verify-replace sequences).
fail()    { printf '%s    \xe2\x9c\x97 %s%s\n' "$RED" "$1" "$RESET"; FAILURES+=("$1"); }

have() { command -v "$1" >/dev/null 2>&1; }

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
    have uv       && printf '  - uv tools\n'
    have rustup   && printf '  - rust toolchains\n'
    have cargo-install-update && printf '  - cargo-installed tools\n'
    have go       && printf '  - go-installed tools (gopls, govulncheck)\n'
    have npm      && printf '  - npm global tools + pnpm\n'
    printf '  - static release binaries (kind, argocd, kubeconform, kube-linter, dive, kustomize, k9s, yq, terraform-docs, golangci-lint)\n'
    have claude   && printf '  - Claude Code CLI\n'
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
# --locked, because without it this undoes the flag the role installed each
# tool with: install-update rebuilds against freshly resolved dependencies
# rather than the ones the author published a lockfile for.
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
# pnpm via corepack (it rides Node, but pin it to latest here).
section "npm global tools"
if have npm; then
    run "npm update -g" npm update -g
    have corepack && run "corepack pnpm@latest" corepack prepare pnpm@latest --activate
else
    skip "npm not found"
fi

# --- Go toolchain ----------------------------------------------------------
# Go publishes no apt/dnf repo, so `apt/dnf upgrade` never moves it -- the
# playbook installs a pinned tarball into /usr/local/go and this section is what
# carries it forward. The pin in group_vars is the BOOTSTRAP floor, not the
# running version; same arrangement as rustup, where the pinned rustup-init
# bootstraps and `rustup update` tracks stable after that.
#
# The checksum is taken from the same go.dev index that gives the URL, so it
# guards against a corrupt or truncated download rather than against go.dev
# itself. The install-time pin in group_vars is the one we hold.
section "Go toolchain"
if [[ ! -x /usr/local/go/bin/go ]]; then
    skip "Go toolchain not found in /usr/local/go"
elif [[ -z "$ARCH_DEB" ]]; then
    skip "unsupported architecture $(uname -m)"
else
    go_installed="$(/usr/local/go/bin/go version 2>/dev/null | awk '{print $3}')"
    go_index="$(mktemp)"

    if ! curl -fsSL 'https://go.dev/dl/?mode=json' -o "$go_index" 2>/dev/null; then
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
            elif ! curl -fsSL "https://go.dev/dl/${go_tgz}" -o "$go_tmp/$go_tgz"; then
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

# --- Tier 3: static binaries with no repo/snap/lang-manager ----------------
# These ship only as a GitHub release asset, so nothing above refreshes them --
# re-fetch the latest here. Each downloads to a temp path, is checked for the ELF
# magic, and is only moved into place on success, so a failed or corrupt fetch
# never breaks the working copy. Only tools already installed are touched, and
# k9s is Ubuntu-only (Fedora's k9s is the dnf package -- re-fetching would shadow
# it). Still uncovered: aws-vault and tea -- re-run the playbook to refresh those.
section "Static binaries (GitHub releases)"

gh_latest_tag() {  # <repo> -> newest release tag (empty on failure)
    curl -fsSL "https://api.github.com/repos/$1/releases/latest" 2>/dev/null \
        | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}

is_elf() {  # <file> -> 0 if it begins with the ELF magic (7f 45 4c 46)
    [[ "$(head -c 4 "$1" 2>/dev/null | od -An -tx1 | tr -d ' \n')" == "7f454c46" ]]
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
    if curl -fsSL "$url" -o "$tmp" && [[ -s "$tmp" ]] && is_elf "$tmp"; then
        sudo install -m 0755 "$tmp" "/usr/local/bin/$name" && ok "$name -> $tag" \
            || FAILURES+=("$name (install)")
    else
        FAILURES+=("$name (download)")
    fi
    rm -f "$tmp"
}

# refetch_targz <name> <repo> <asset-template> <member>  -- extract <member>
# from a .tar.gz release asset. Template may use {TAG}, {VER} (tag minus a
# leading v) and {ARCH}.
refetch_targz() {
    local name="$1" repo="$2" tmpl="$3" member="$4" tag ver asset url tmp dir
    have "$name" || { skip "$name not installed"; return; }
    tag="$(gh_latest_tag "$repo")"
    [[ -n "$tag" ]] || { FAILURES+=("$name (no release tag)"); return; }
    ver="${tag#v}"
    asset="${tmpl//\{TAG\}/$tag}"; asset="${asset//\{VER\}/$ver}"; asset="${asset//\{ARCH\}/$ARCH_DEB}"
    url="https://github.com/$repo/releases/download/$tag/$asset"
    tmp="$(mktemp)"; dir="$(mktemp -d)"
    if curl -fsSL "$url" -o "$tmp" && tar -xzf "$tmp" -C "$dir" "$member" 2>/dev/null \
        && [[ -s "$dir/$member" ]] && is_elf "$dir/$member"; then
        sudo install -m 0755 "$dir/$member" "/usr/local/bin/$name" && ok "$name -> $tag" \
            || FAILURES+=("$name (install)")
    else
        FAILURES+=("$name (download)")
    fi
    rm -rf "$tmp" "$dir"
}

# refetch_targz_nested <name> <repo> <asset-template>  -- as refetch_targz, but
# the binary sits one directory deep in the tarball.
refetch_targz_nested() {
    local name="$1" repo="$2" tmpl="$3" tag ver asset url tmp dir
    have "$name" || { skip "$name not installed"; return; }
    tag="$(gh_latest_tag "$repo")"
    [[ -n "$tag" ]] || { FAILURES+=("$name (no release tag)"); return; }
    ver="${tag#v}"
    asset="${tmpl//\{TAG\}/$tag}"; asset="${asset//\{VER\}/$ver}"; asset="${asset//\{ARCH\}/$ARCH_DEB}"
    url="https://github.com/$repo/releases/download/$tag/$asset"
    tmp="$(mktemp)"; dir="$(mktemp -d)"
    if curl -fsSL "$url" -o "$tmp" \
        && tar -xzf "$tmp" -C "$dir" --strip-components=1 --wildcards "*/$name" 2>/dev/null \
        && [[ -s "$dir/$name" ]] && is_elf "$dir/$name"; then
        sudo install -m 0755 "$dir/$name" "/usr/local/bin/$name" && ok "$name -> $tag" \
            || FAILURES+=("$name (install)")
    else
        FAILURES+=("$name (download)")
    fi
    rm -rf "$tmp" "$dir"
}

# kustomize is a monorepo: /releases/latest can point at a non-CLI component, so
# pull the newest kustomize CLI asset URL straight from the releases list.
refetch_kustomize() {
    have kustomize || { skip "kustomize not installed"; return; }
    local url tmp dir
    url="$(curl -fsSL "https://api.github.com/repos/kubernetes-sigs/kustomize/releases" 2>/dev/null \
        | grep -oE "https://[^\"]*/kustomize_v[0-9.]+_linux_${ARCH_DEB}\.tar\.gz" | head -1)"
    [[ -n "$url" ]] || { FAILURES+=("kustomize (no asset)"); return; }
    tmp="$(mktemp)"; dir="$(mktemp -d)"
    if curl -fsSL "$url" -o "$tmp" && tar -xzf "$tmp" -C "$dir" kustomize 2>/dev/null \
        && [[ -s "$dir/kustomize" ]] && is_elf "$dir/kustomize"; then
        sudo install -m 0755 "$dir/kustomize" /usr/local/bin/kustomize && ok "kustomize (latest)" \
            || FAILURES+=("kustomize (install)")
    else
        FAILURES+=("kustomize (download)")
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
    refetch_targz dive        wagoodman/dive        "dive_{VER}_linux_{ARCH}.tar.gz" dive
    refetch_targz terraform-docs terraform-docs/terraform-docs \
        "terraform-docs-{TAG}-linux-{ARCH}.tar.gz" terraform-docs
    refetch_targz_nested golangci-lint golangci/golangci-lint \
        "golangci-lint-{VER}-linux-{ARCH}.tar.gz"
    # k9s, kustomize and yq: Fedora installs these from dnf (/usr/bin); only
    # Ubuntu carries the /usr/local/bin binary, so only re-fetch there or we
    # shadow the dnf copy.
    if [[ "$PKG_MGR" == apt ]]; then
        refetch_targz k9s derailed/k9s "k9s_Linux_{ARCH}.tar.gz" k9s
        refetch_kustomize
        refetch_raw   yq  mikefarah/yq  "yq_linux_{ARCH}"
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
