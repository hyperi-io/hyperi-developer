#!/usr/bin/env zsh
#
# hyperi-update (macOS) — update everything the hyperi-developer installer set
# up on this machine in one command:
#   - macOS system + security updates (softwareupdate)
#   - Homebrew formulae and casks (apps, CLIs, subsystems — incl. aws, gh,
#     az, kubectl, helm, terraform, vault, gcloud-cli, linear, ...)
#   - uv tools, rustup toolchains
#   - Claude Code CLI (self-installed under ~/.local)
#
# Each section is independent and self-guarding: any tool that isn't installed
# is skipped (not an error), and if a step fails the script keeps going and
# reports it in the summary at the end. Safe to run on a machine that has only
# some of these tools. Run with:  hyperi-update
# (prompts once for your password for the macOS system updates).
#
# Run `hyperi-update --install` once to drop a double-clickable
# "Hyperi Update" app into /Applications.

set -u
emulate -L zsh

# Make user-level tools reachable even when launched from the GUI app.
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

# --- pretty output --------------------------------------------------------
autoload -Uz colors && colors
typeset -a FAILED
section() { print -P "\n%F{cyan}==> $1%f"; }
ok()      { print -P "%F{green}   ✓ $1%f"; }
warn()    { print -P "%F{yellow}   ! $1%f"; }
# run "<label>" cmd args...  — runs a step, records failure but never aborts
run() {
  local label=$1; shift
  if "$@"; then ok "$label"; else warn "$label FAILED"; FAILED+=("$label"); fi
}
have() { command -v "$1" >/dev/null 2>&1; }

# --- self-resolve: absolute path to this script (symlinks resolved) -------
SELF=${${(%):-%x}:A}

usage() {
  cat <<EOF
hyperi-update — update Homebrew, uv, rustup, Claude Code and macOS in one go.

Usage:
  hyperi-update            Run all updates now.
  hyperi-update --install  Create a clickable "Hyperi Update" app in /Applications.
  hyperi-update --help     Show this help.
EOF
}

# Build a double-clickable .app that opens Terminal and runs this script.
# Uses osacompile (built into macOS) — no dependencies. The app tells Terminal
# to `exec` this script, so when the run finishes the shell exits and (if your
# Terminal profile is set to "close if the shell exited cleanly") the window
# closes by itself; a failed run leaves it open to read.
install_app() {
  if ! have osacompile; then
    warn "osacompile not found (not macOS?) — cannot build the app"
    return 1
  fi
  local app="/Applications/Hyperi Update.app"
  # Custom icon kept outside the bundle so re-installs never lose it. The
  # installer drops it here; fall back to migrating from any legacy app.
  local icon_store="$HOME/.local/share/hyperi-update/AppIcon.icns"
  local legacy_icon="/Applications/Update Mac.app/Contents/Resources/applet.icns"
  section "Installing clickable app"

  if [[ ! -f "$icon_store" && -f "$legacy_icon" ]]; then
    mkdir -p "${icon_store:h}"
    cp "$legacy_icon" "$icon_store" && ok "kept custom icon at $icon_store"
  fi

  rm -rf "$app"
  local tmp; tmp=$(mktemp -d)
  cat > "$tmp/run.applescript" <<EOF
tell application "Terminal"
	activate
	do script "exec " & quoted form of "$SELF"
end tell
EOF
  if ! osacompile -o "$app" "$tmp/run.applescript"; then
    warn "failed to build the app (no write access to /Applications?)"
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
  print -P "%F{green}   Launch it from Spotlight/Launchpad as 'Hyperi Update', or drag it to the Dock.%f"
  print -P "%F{yellow}   First launch asks permission to control Terminal — allow it once.%f"
}

# --- argument handling ----------------------------------------------------
case "${1:-}" in
  --install)  install_app; exit $? ;;
  -h|--help)  usage; exit 0 ;;
  "")         ;;  # no args: fall through and run all updates
  *)          print -u2 "hyperi-update: unknown option '$1'"; usage; exit 2 ;;
esac

print -P "%F{magenta}╔════════════════════════════════════════╗%f"
print -P "%F{magenta}║   Updating everything on $(scutil --get ComputerName 2>/dev/null || hostname)%f"
print -P "%F{magenta}╚════════════════════════════════════════╝%f"

# --- Homebrew: formulae + casks (the bulk of your apps & subsystems) ------
if have brew; then
  section "Homebrew"
  # Don't quarantine freshly-downloaded casks. Without this, every updated
  # app triggers the macOS Gatekeeper prompt on first launch.
  export HOMEBREW_CASK_OPTS="--no-quarantine"
  # Run unattended: suppress brew's env-var hints so output stays clean.
  export HOMEBREW_NO_ENV_HINTS=1
  run "brew update"       brew update
  run "brew upgrade"      brew upgrade            # formulae + outdated casks
  # Casks that self-update report no version to brew; --greedy catches them too.
  run "brew upgrade --cask --greedy" brew upgrade --cask --greedy
  run "brew autoremove"   brew autoremove         # drop now-unused dependencies
  run "brew cleanup"      brew cleanup --prune=all # delete old downloads/versions
else
  warn "Homebrew not found — skipping"
fi

# --- uv: CLI tools installed via `uv tool install` ------------------------
if have uv; then
  section "uv tools"
  run "uv tool upgrade --all" uv tool upgrade --all
else
  warn "uv not found — skipping"
fi

# --- rustup: Rust toolchains (rustup itself is updated by brew) -----------
if have rustup; then
  section "rustup toolchains"
  run "rustup update" rustup update
else
  warn "rustup not found — skipping"
fi

# --- Claude Code CLI: self-installed under ~/.local, not brew-managed ------
if have claude; then
  section "Claude Code CLI"
  run "claude update" claude update
else
  warn "claude not found — skipping"
fi

# NOTE: gcloud is intentionally NOT updated here. It's installed as the brew
# cask 'gcloud-cli', so `brew upgrade --cask` above already updates it.
# Running `gcloud components update` as well would fork the version brew
# tracks from the one on disk.

# --- macOS: Apple system + security updates (last; may need a restart) ----
if have softwareupdate; then
  section "macOS system updates (Apple)"
  warn "may prompt for your password and could require a restart"
  run "softwareupdate" sudo softwareupdate --install --all --agree-to-license
else
  warn "softwareupdate not found (not macOS?) — skipping"
fi

# --- summary --------------------------------------------------------------
print -P "\n%F{magenta}──────────── summary ────────────%f"
if (( ${#FAILED} == 0 )); then
  print -P "%F{green}All updates completed successfully.%f"
else
  print -P "%F{yellow}Completed with ${#FAILED} issue(s):%f"
  for f in $FAILED; do print -P "%F{yellow}   - $f%f"; done
  exit 1
fi
