# VSCode Wayland Fullscreen Bug

**Research Date:** 2026-01-06
**Status:** UPSTREAM BUG - Cannot be fixed by hyperi-developer installer

## Overview

VSCode (and other Electron apps) exhibit fullscreen window geometry issues on GNOME Wayland. Windows become small, displaced, or render content at the wrong size after alt-tab or focus switching.

## Environment Tested

- **OS:** Fedora 42 (Workstation Edition)
- **Desktop:** GNOME 48
- **Compositor:** Mutter (Wayland)
- **VSCode:** 1.107.1
- **Electron:** 39.2.3
- **Chromium:** 142.0.7444.175
- **Session Type:** Wayland

## Symptoms

- Window goes fullscreen but content renders at smaller/wrong size
- Happens when Alt-Tab or Super+N switching between windows
- Window appears displaced/offset after returning from alt-tab
- Black areas appear where content should be
- Sometimes window borders become corrupted or show visual artifacts

## Root Cause Analysis

This is a **GNOME/Mutter + Wayland compositor interaction bug**, NOT purely an Electron/VSCode bug. Multiple applications (WezTerm, mpv, SDL2 games) exhibit identical behavior on GNOME Wayland.

### Technical Details

1. **Missing geometry state:** When apps enter fullscreen without first being in windowed mode, GNOME/Mutter has no previous geometry to restore when exiting fullscreen or switching focus.

2. **Compositor state tracking:** Mutter's Wayland compositor loses track of window geometry during focus switches, particularly with xdg-toplevel fullscreen state changes.

3. **xdg-toplevel protocol edge cases:** The Wayland xdg-toplevel protocol has edge cases around fullscreen state changes that different compositors handle inconsistently.

4. **Configure event timing:** Race conditions between xdg_toplevel.configure events and surface commits can cause geometry mismatches.

## Related Upstream Issues

### Electron Issues

| Issue | Description | Status |
| ----- | ----------- | ------ |
| [#46755](https://github.com/electron/electron/issues/46755) | Maximized window corruption GNOME 48 | Closed (GTK theme issue) |
| [#46484](https://github.com/electron/electron/issues/46484) | Broken window border GNOME Wayland | Fixed |
| [#44543](https://github.com/electron/electron/issues/44543) | Resize window doesn't work on Wayland | Fixed |
| [#33161](https://github.com/electron/electron/issues/33161) | Window has borders while maximized in Wayland | Open |

### VSCode Issues

| Issue | Description | Status |
| ----- | ----------- | ------ |
| [#210624](https://github.com/microsoft/vscode/issues/210624) | Unclickable space after resize Ubuntu 24.04 | Open |
| [#188407](https://github.com/microsoft/vscode/issues/188407) | Resize/Fullscreen creates unclickable space | Closed (not planned) |
| [#167183](https://github.com/microsoft/vscode/issues/167183) | Title bar visible in fullscreen with custom style | Patched |
| [#181533](https://github.com/microsoft/vscode/issues/181533) | Segfault on Wayland with titleBarStyle=custom | Patched |

### Other Applications (Same Bug)

| Issue | Application | Description |
| ----- | ----------- | ----------- |
| [WezTerm #6275](https://github.com/wezterm/wezterm/issues/6275) | WezTerm | Fullscreen displacement on focus loss |
| [mpv #16650](https://github.com/mpv-player/mpv/issues/16650) | mpv | Fullscreen restores to tiny window (Fedora 42/GNOME 48) |
| [SFML #2709](https://github.com/SFML/SFML/issues/2709) | SFML | Window content offset by GNOME top bar height |

### GNOME/Mutter Issues

| Issue | Description |
| ----- | ----------- |
| [gnome-shell #1224](https://gitlab.gnome.org/GNOME/gnome-shell/-/issues/1224) | SDL2 fullscreen wrong position after Alt-Tab |
| [mutter #378](https://gitlab.gnome.org/GNOME/mutter/-/issues/378) | Unsetting fullscreen shrinks to 1px if initially fullscreen |
| [mutter #1973](https://gitlab.gnome.org/GNOME/mutter/-/issues/1973) | Window size messed up after returning from fullscreen |
| [mutter #2084](https://gitlab.gnome.org/GNOME/mutter/-/issues/2084) | xdg_toplevel.set_fullscreen doesn't center surface/add padding |
| [Bug 786305](https://bugzilla.gnome.org/show_bug.cgi?id=786305) | Fullscreen XWayland window offset by top bar after Alt+Tab |

## Electron Fixes Applied

These fixes are included in Electron 35.1.0+ and are present in VSCode 1.107.1 (Electron 39.2.3):

| PR | Description | Versions |
| -- | ----------- | -------- |
| [#46155](https://github.com/electron/electron/pull/46155) | Wayland resizing border fix | 33, 34, 35, 36 |
| [#46224](https://github.com/electron/electron/pull/46224) | Backport to 35-x-y | 35.1.0+ |
| [#46624](https://github.com/electron/electron/pull/46624) | Window border GNOME Wayland (inverted conditional fix) | 33, 34, 35, 36 |

**Note:** These fixes improve the situation but do not fully resolve the underlying Mutter/Wayland compositor bug.

## Upstream Fix Status (Updated 2026-01-06)

**The bug is NOT fixed and NOT waiting for merges. It remains an open upstream issue.**

### GNOME/Mutter Status

- [mutter #378](https://gitlab.gnome.org/GNOME/mutter/-/issues/378) - **OPEN** - xdg-shell fullscreen shrinks to 1px
- [gnome-shell #1224](https://gitlab.gnome.org/GNOME/gnome-shell/-/issues/1224) - **OPEN** - SDL2 fullscreen wrong position after Alt-Tab
- [MR !1811](https://gitlab.gnome.org/GNOME/mutter/-/merge_requests/1811) - Addresses min/max constraints but NOT the alt-tab geometry loss

### Electron Status

- [#46755](https://github.com/electron/electron/issues/46755) - Closed as GTK theme issue (underlying problem persists)
- Users report rolling back to **Electron v34.3.2** as only reliable fix

### GNOME 48.7 / 49.1 Status

- Point releases include Wayland fullscreen constraint fixes
- Improved window resizing reliability
- **No fix for alt-tab fullscreen geometry restoration bug**

### Bottom Line

This is a **long-standing Mutter compositor bug** that has not been prioritized for a fix. No merge request exists that addresses the core issue. The bug has persisted across multiple GNOME versions (45, 46, 47, 48) without resolution.

## Workarounds

**Note:** XWayland fallback is NOT acceptable for this project. All workarounds must maintain native Wayland operation.

### 1. Toggle Fullscreen Twice After Alt-Tab (Primary Workaround)

When the bug occurs, press F11 twice to exit and re-enter fullscreen. This forces the compositor to recalculate geometry.

### 2. Use Custom Title Bar Style

Some users report improvement with custom title bar:

```json
{
  "window.titleBarStyle": "custom"
}
```

### 3. Avoid Super+N Window Switching

The bug is more likely to trigger with Super+number shortcuts. Use Alt-Tab or click in Activities Overview instead.

### 4. Force Window Decorations

```bash
code --enable-features=WaylandWindowDecorations
```

### 5. Use Maximized Instead of Fullscreen

Consider using maximized windows instead of true fullscreen (F11). Maximized windows don't trigger the same compositor edge cases.

## Configuration Files

### VSCode Flags File

Location: `~/.config/code-flags.conf`

For native Wayland with decorations (recommended):

```text
--ozone-platform-hint=auto
--enable-features=WaylandWindowDecorations
```

### Electron Flags File (Global)

Location: `~/.config/electron-flags.conf`

Affects all Electron apps:

```text
--ozone-platform-hint=auto
--enable-features=WaylandWindowDecorations
--enable-wayland-ime
```

## Testing Methodology

To reproduce the bug:

1. Launch VSCode on GNOME Wayland session
2. Enter fullscreen mode (F11)
3. Alt-Tab to another application
4. Alt-Tab back to VSCode
5. Observe: window may be displaced, content shrunk, or black areas visible

To verify workaround effectiveness:

1. Apply custom title bar style setting
2. Repeat steps above
3. Note if geometry issues are reduced

## Version History

### VSCode Electron Versions (Recent)

| VSCode | Electron | Notes |
| ------ | -------- | ----- |
| 1.107.x | 39.2.3 | Current stable |
| 1.105-1.106 | 37.x | - |
| 1.103-1.104 | 37.x | - |
| 1.101-1.102 | 35.x | First with Wayland resize fix |
| 1.98-1.100 | 34.x | - |
| 1.95-1.97 | 32.x | - |

### Key Electron Releases

- **Electron 35.0.0:** Default `--ozone-platform` changed to `auto` (native Wayland when available)
- **Electron 35.1.0:** Wayland resize fix ([#46155](https://github.com/electron/electron/pull/46155)) included
- **Electron 38+:** `--ozone-platform-hint` command-line flag no longer works; use environment variable instead

## Recommendations for hyperi-developer

1. **Document the workaround** in user-facing documentation
2. **Do not attempt to fix** - this is an upstream compositor bug
3. **Monitor upstream** - GNOME 49/50 may include Mutter fixes
4. **Track GNOME GitLab** for mutter fullscreen geometry fixes
5. **Consider filing** a consolidated bug report on GNOME GitLab if not already tracked

## GNOME 49/50 Status (Updated 2026-01-06)

### What's Fixed in GNOME 49

- **Direct scanout enhancements** for fullscreen apps (performance improvement)
- **Wayland toplevel tag protocol** (xdg_toplevel_tag_v1 from Wayland Protocols 1.43)
  - Helps compositors restore window positioning/sizes after restart
  - Enables "always on top" behavior and custom compositor rules

### What's NOT Fixed

- **[mutter #378](https://gitlab.gnome.org/GNOME/mutter/-/issues/378)** - Still OPEN
  - Windows starting in fullscreen shrink to 1px when exiting fullscreen
  - Root cause: no previous geometry to restore
- **[MR !1811](https://gitlab.gnome.org/GNOME/mutter/-/merge_requests/1811)** - Still OPEN (since April 2021)
  - Proposed fix for min/max constraints when restoring from fullscreen
  - Not merged after 4+ years

### GNOME 50 Changes

- X11 session support **completely removed** (November 2025)
- Wayland-only desktop environment
- No indication the fullscreen geometry bugs are prioritized

### Conclusion

The core bug (mutter #378) remains unfixed. GNOME 49/50 improvements focus on performance and new protocols, not fixing existing fullscreen geometry state tracking issues.

## Future Work

- [ ] Monitor GNOME 51 for Mutter fixes
- [ ] Test with upcoming Electron versions for improvements
- [ ] Investigate if gnome-shell extensions can mitigate the issue
- [ ] Research if libadwaita-based apps have the same problem

---

## WBS: Fix It Ourselves

Since upstream has not prioritized this bug, here's a work breakdown structure to implement a fix ourselves.

### Phase 1: Research & Analysis

| ID | Task | Dependencies |
| -- | ---- | ------------ |
| 1.1 | Deep-dive Mutter source: `src/wayland/meta-wayland-xdg-shell.c` | - |
| 1.2 | Trace xdg_toplevel.configure event flow during fullscreen/alt-tab | 1.1 |
| 1.3 | Identify where geometry state is lost (window.c, meta-window.c) | 1.2 |
| 1.4 | Review [MR !1811](https://gitlab.gnome.org/GNOME/mutter/-/merge_requests/1811) approach | 1.1 |
| 1.5 | Document findings and potential fix locations | 1.3, 1.4 |

### Phase 2: Prototype Fix

| ID | Task | Dependencies |
| -- | ---- | ------------ |
| 2.1 | Set up Mutter build environment (Fedora 42 toolbox) | - |
| 2.2 | Create test harness to reproduce bug reliably | 2.1 |
| 2.3 | Implement geometry state caching before fullscreen transition | 1.5, 2.2 |
| 2.4 | Implement geometry restoration on focus-return after alt-tab | 2.3 |
| 2.5 | Handle edge case: app launches directly into fullscreen | 2.4 |

### Phase 3: Testing & Validation

| ID | Task | Dependencies |
| -- | ---- | ------------ |
| 3.1 | Test with VSCode (Electron 39.x) | 2.5 |
| 3.2 | Test with WezTerm (Rust/wlroots) | 2.5 |
| 3.3 | Test with mpv (C/libmpv) | 2.5 |
| 3.4 | Test with SDL2 game (different toolkit) | 2.5 |
| 3.5 | Regression test: normal window operations, multi-monitor | 3.1-3.4 |
| 3.6 | Performance profiling (ensure no frame drops) | 3.5 |

### Phase 4: Upstream Contribution

| ID | Task | Dependencies |
| -- | ---- | ------------ |
| 4.1 | Clean up code to GNOME coding standards | 3.6 |
| 4.2 | Write comprehensive commit message with test cases | 4.1 |
| 4.3 | Submit MR to GNOME GitLab | 4.2 |
| 4.4 | Address reviewer feedback (multiple rounds expected) | 4.3 |
| 4.5 | Backport to stable branches if accepted | 4.4 |

### Phase 5: Local Workaround (Parallel Track)

If upstream is slow, deploy local fix:

| ID | Task | Dependencies |
| -- | ---- | ------------ |
| 5.1 | Package patched Mutter as COPR/PPA | 3.6 |
| 5.2 | Add to hyperi-developer installer as optional repo | 5.1 |
| 5.3 | Create auto-update mechanism for patch releases | 5.2 |
| 5.4 | Document removal process when upstream merges | 5.3 |

### Alternative: GNOME Shell Extension Approach

Lower-effort workaround that doesn't require patching Mutter:

| ID | Task | Dependencies |
| -- | ---- | ------------ |
| A.1 | Research gnome-shell extension API for window management | - |
| A.2 | Prototype extension that monitors fullscreen state changes | A.1 |
| A.3 | Implement geometry save/restore on focus events | A.2 |
| A.4 | Test with affected applications | A.3 |
| A.5 | Package and publish to extensions.gnome.org | A.4 |

### Approach Comparison

| Approach | Risk | Maintainability |
| -------- | ---- | --------------- |
| Mutter patch (upstream) | Medium | Best (upstream maintains) |
| Mutter patch (local COPR) | Low | Poor (must maintain fork) |
| GNOME Shell extension | Medium | Good (extension API stable) |

### Recommended Approach

1. **Start with Phase 1** - understand the bug deeply
2. **Parallel track A.1-A.3** - extension as quick win
3. **If extension works**, deploy it while pursuing upstream fix
4. **Submit upstream MR** regardless - even if rejected, documents the issue

### Key Files to Study

```text
mutter/src/wayland/meta-wayland-xdg-shell.c    # xdg-toplevel handling
mutter/src/core/window.c                        # Window state management
mutter/src/core/meta-window.c                   # Geometry tracking
gnome-shell/js/ui/windowManager.js              # Shell window management
gnome-shell/js/ui/altTab.js                     # Alt-Tab implementation
```

### Success Criteria

- [ ] VSCode fullscreen survives 10 consecutive alt-tab cycles
- [ ] WezTerm fullscreen survives 10 consecutive alt-tab cycles
- [ ] mpv fullscreen survives 10 consecutive alt-tab cycles
- [ ] No regression in normal window operations
- [ ] No measurable performance impact

## References

- [Electron Releases](https://releases.electronjs.org/)
- [VSCode Release Notes](https://code.visualstudio.com/updates)
- [GNOME Mutter GitLab](https://gitlab.gnome.org/GNOME/mutter)
- [Wayland Protocols](https://wayland.freedesktop.org/docs/html/)
- [ArchWiki: Wayland](https://wiki.archlinux.org/title/Wayland)
- [Enable VSCode Native Wayland (Gist)](https://gist.github.com/qguv/e592dbeaeebc4ee7791d2ae8cfa7ef14)
