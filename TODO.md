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

## Platform Support

## Testing

## Documentation

## Future Enhancements

## Code Quality

## Security

## Next: rename `dfe-developer` → `hyperi-developer`

Queued after the role-structure refactor (PR #5) merges. Scope:

- **Refactor** all internal references from `dfe-developer` / `DFE` to
  `hyperi-developer` / `hyperi`. Grep every `ansible/`, `install.sh`,
  `docs/`, `README.md`, `CHANGELOG.md`, task comments, etc. — no partial
  rename that leaves mixed naming.
- **Rename the upstream GitHub repo** `hyperi-io/dfe-developer` →
  `hyperi-io/hyperi-developer`. Update the tarball URL baked into
  `install.sh` (currently downloads from
  `github.com/hyperi-io/dfe-developer/archive/...`) so fresh installs
  still work after the rename. GitHub keeps a redirect for old repo URLs
  but the clone path in the script should match the new canonical name.
- **Remove the legacy `/fedora` path.** The top-level `fedora/` directory
  pre-dates the Ansible-driven setup — audit what's still referenced
  from it (if anything) and delete.
- **Update `dfe-infra` auto-desktop-build pipelines** to use the new repo
  URL (`hyperi-io/hyperi-developer`) wherever they currently clone or
  tarball-download from `hyperi-io/dfe-developer`. Without this, Packer /
  cloud-init / Proxmox templates continue pulling from the old path
  (which will 404 once GitHub stops serving the redirect, or silently
  diverge if the old repo is archived rather than deleted).

Open a separate spec + plan under `docs/plans/` for this. No rush to
start before the refactor merges; having two large in-flight PRs on
the same surface area will cause painful conflicts.

## Role-structure refactor follow-ups

- **[parked]** VM smoke tests for `feat/role-structure-refactor`. Full
  `--profile developer` and `--profile core,all` runs against an Ubuntu 24.04
  clone, plus `tests/assertions/oss_safe.sh` post-install check. Re-enable
  after user has VM-provisioning time available. Checklist lives at
  `docs/plans/2026-04-18-audit-findings.md` under "VM smoke test results".
- **[parked]** Fedora VM smoke test. Provision a Fedora 42 test template, then
  run the profile matrix against it. Fedora paths currently verified via
  check-mode syntax only.
- Track 2 audit items: see `docs/plans/2026-04-18-audit-findings.md`
  "Flag for Track 2" section.
- Consider de-duplicating `core/vars/macos.yml` and `developer/vars/macos.yml`
  via a top-level `group_vars` entry (reviewer suggestion from Chunk 3).

---

**Note:** Completed tasks are documented in STATE.md and CHANGELOG.md
