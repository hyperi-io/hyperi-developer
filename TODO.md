# TODO - DFE Developer Environment

## Completed This Session

- [x] Add `app-notifications = no-clipboard-copy` to Ghostty Linux config
  - Disables the copy notification popup
  - Syncs project config with actual machine config

## Immediate Tasks

- [x] **desktop-mode script for maclike/winlike swap**
  - Single script: `desktop-mode --winlike` / `desktop-mode --maclike`
  - Auto-detects DBUS from running GNOME session
  - Falls back to saved preference + autostart when GNOME not running
  - Supports `--user <name>` for cross-user switching (requires root)
  - Deployed to `/usr/local/sbin/desktop-mode` via Ansible

- [ ] **maclike toast/notification bug**
  - Ghostty numeric toasts never seem to clear in maclike taskbar
  - Notifications stack up and persist instead of dismissing
  - Investigate whether this is Dash to Dock or GNOME Shell issue

- [ ] **Role refactor + trim defaults + macOS modern bash**
  - Plan: [`docs/plans/2026-05-01-role-refactor-and-trim-defaults.md`](docs/plans/2026-05-01-role-refactor-and-trim-defaults.md)
  - Branch: `feat/ghostty-update-and-trim-defaults` (Ghostty theme fix already in)
  - Pending decisions before implementation: name for `developer_core` rename
    (recommend `work` or `hyperi`), default group set, whether `bash-modern` is
    opt-in on macOS, rename for `--core` shortcut, dedup `wallpaper.yml`
  - End-state validation: rebuild VMID 9043 (Ubuntu 26.04 resolute) via the
    hyperi-infra workflow with this branch, confirm trimmed default install +
    opt-in groups + Ghostty theme work

## Platform Support

## Testing

## Documentation

## Future Enhancements

## Code Quality

## Security

---

**Note:** Completed tasks are documented in STATE.md and CHANGELOG.md
