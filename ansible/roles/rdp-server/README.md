# GNOME Remote Login (RDP) server

Configures and tunes inbound RDP on port 3389, including automatic window
resizing and performance work for software-encoded sessions.

## Remote Login is not Desktop Sharing

The `gnome-remote-desktop` package provides two separate features, and GNOME
Settings puts them on separate tabs. **This role configures Remote Login only**
and never touches Desktop Sharing.

| | Remote Login | Desktop Sharing |
|---|---|---|
| Scope | System-wide, serves the GDM greeter | One user's already-running session |
| systemd unit | `gnome-remote-desktop.service` (system) | the same unit, per-user |
| Managed with | `grdctl --system` | `grdctl` (no `--system`) |
| Credentials in | `/var/lib/gnome-remote-desktop/.../credentials.ini` | that user's keyring |
| Settings tab | System > Remote Login | System > Desktop Sharing |

Confusing the two costs hours: the credentials you set on one are invisible to
the other, and the tab that looks configured is not the one serving port 3389.
`grdctl --system status` is the authority for what this role manages.

## What It Does

1. **Enables Remote Login (RDP)** on port 3389, via `grdctl --system`
2. **Sets credentials** -- but only when Remote Login holds none (see below)
3. **Configures Auto-Resize** - Desktop resizes to match the RDP client window (which is also what strands windows off-screen on reconnect -- see [Window placement across resolution changes](#window-placement-across-resolution-changes))
4. **Performance Tuning** - TCP optimizations for RDP traffic
5. **Certificates** - Auto-generates a self-signed TLS certificate

## Platform Support

- **Fedora 42+** with GNOME Desktop
- **Ubuntu 24.04+** with GNOME Desktop
- **Not applicable** to macOS (uses different remote access methods)

## Usage

```bash
# Via install.sh
./install.sh --tags rdp-server

# Via Ansible directly
cd ansible
ansible-playbook -i inventories/localhost/inventory.yml playbooks/main.yml --tags rdp-server
```

## RDP credentials

The role handles these. There is nothing to set by hand.

The RDP credential is **separate from your user account password**: compromising
one does not give up the other, and the RDP one is what you type into a client.

Three sources, in precedence order:

1. `rdp_password` supplied by the operator -- used as-is, never written to disk
2. a password this role generated on an earlier run -- reused from
   `/etc/hyperi/rdp-credentials` (root-only, `0600`)
3. neither, **and** Remote Login currently holds no credentials -- generate 24
   alphanumerics, record them, and print them once

**Existing credentials always win.** If `grdctl --system status` reports a
username set, the role leaves both the username and the password alone. A host
provisioned before this role existed already holds working credentials nobody
recorded, and overwriting them locks out whoever is using them.

To rotate deliberately: delete `/etc/hyperi/rdp-credentials` and re-run, or set
them yourself with

```bash
sudo grdctl --system rdp set-credentials <user> <pass>
```

Username defaults to `rdp_username` (`hyperi`), which is **not** your Linux
login name unless you make it so.

## Technical Details

### What Gets Configured

**Service Configuration:**
- `gnome-remote-desktop.service` (the SYSTEM unit) - enabled and started
- Remote Login (RDP) - explicitly enabled via `grdctl --system rdp enable`

**Certificates:**
- Self-signed TLS pair auto-generated in `/var/lib/gnome-remote-desktop/`
  (`rdp-tls.crt` `0644`, `rdp-tls.key` `0600`)
- Registered with `grdctl --system rdp set-tls-cert` / `set-tls-key`

**TCP Optimizations:**
- Window scaling enabled
- Congestion control: BBR (low-latency)
- MTU optimization for RDP traffic
- Reduced TCP memory footprint for VMs

**Desktop Configuration (dconf):**
- Window resize behavior optimized
- Performance settings for remote sessions

## Testing

Connect from RDP client:
```bash
# From Windows
mstsc /v:your-vm-hostname:3389

# From macOS
# Use Microsoft Remote Desktop app

# From Linux
remmina
```

Login with:
- Username: `rdp_username` (`hyperi` by default), NOT your Linux login name
- Password: the RDP password (NOT your user account password) -- see
  `/etc/hyperi/rdp-credentials` if the role generated it

## Troubleshooting

### "Connection failed" or "Authentication failed"

1. `sudo grdctl --system status` -- `Status: enabled` and a `Username: (hidden)`
   line mean Remote Login is configured. Checking the Desktop Sharing tab
   instead is the classic wrong turn here
2. Use the RDP username and password, not your user account credentials
3. Check firewall: `sudo firewall-cmd --list-all` (port 3389 should be open)

### "Desktop doesn't resize"

- TCP optimizations applied - requires reboot
- Check `/etc/sysctl.d/98-rdp-tcp.conf` exists
- Run: `sudo sysctl -p /etc/sysctl.d/98-rdp-tcp.conf`

### "Certificates error"

- Certificates auto-generated during installation
- Check: `sudo ls -la /var/lib/gnome-remote-desktop/`
- Should see: rdp-tls.crt, rdp-tls.key owned by the gnome-remote-desktop user

## Known limitations

### The screencast framerate cannot be capped (waiting on upstream)

GRD hardcodes the PipeWire screencast stream at 60fps. On a virtio-gpu VM with
no VA-API H.264 encoder, every one of those frames is encoded in software, and
halving the rate roughly halves that load. There is no supported way to change
it: `gsettings list-keys org.gnome.desktop.remote-desktop.rdp` on GRD 50.0 has
no framerate key, and nothing has landed upstream.

We do not ship a workaround. A patched GRD build with a `max-framerate`
gsettings key was written and tested, and is not adopted here: it meant
carrying a prebuilt amd64-only `.deb` in the repo, pinned at apt priority 1001,
which would freeze a network-facing daemon out of security updates
indefinitely. Trading CVE patches for framerate is the wrong side of that deal.

**Adopt this the moment a `max-framerate` key exists upstream.** When it does,
the whole change is one line in `files/dconf-rdp-performance`:

```
[org/gnome/desktop/remote-desktop/rdp]
max-framerate=uint32 30
```

Until then the software-encode path leans on the `Nice=-10` priority boost
(see below) and `enable-animations=false`, which are what we do ship.

### What we do about software encode instead

`rdp_hw_encode_expected` drives this. When no hardware encoder is expected, the
role deploys a `Nice=-10` systemd drop-in to both the GRD system service and
the user handover service, and removes it again when hardware encode is
available. The user-service half needs `RLIMIT_NICE` headroom to take effect --
an unprivileged systemd user manager cannot lower niceness on its own and
systemd does not warn when it silently fails to. That is what
`/etc/security/limits.d/50-rdp-nice.conf` is for.

### Do not restart GRD on a live session

`systemctl restart gnome-remote-desktop.service` kills the GNOME session it is
serving. This role restarts the service at the end of a run, so **applying it
over RDP will drop your own connection mid-run**. Apply over SSH, from a local
console, or accept the reconnect.

## Window placement across resolution changes

Reconnect at a smaller geometry than the last session and windows end up jammed
against the right and bottom edges, showing a sliver of themselves. `rdp_window_fit_enabled`
puts them back; the rest of this section is what it is fixing and why nothing
simpler works.

The cause is the gap between sessions, not the resize. On disconnect GRD
destroys its virtual monitor and the session is left with **no logical monitor
at all** -- measured on Ubuntu 26.04 / GNOME 50, GNOME Shell reports
`monitors: 0, primary: -1`, and the 640x480 in the logs is the leftover stage
size rather than a small monitor. Mutter rescales window positions only when the
old and the new logical monitor both exist: `meta_window_update_for_monitors_changed`
reaches `meta_window_move_between_rects` only in that case (mutter 50,
`src/core/window.c`). Disconnect gives it no new monitor and reconnect gives it
no old one, so both transitions skip the rescale.

What survives is mutter's constraint pass, which clamps a window just far enough
to keep a strip on screen but never resizes it. A 700px-wide window sitting at
x=1450 on a 1710-wide session comes back at x=1205 on a 1280-wide one: 75px of
it visible, technically grabbable, useless. Reconnecting at the SAME geometry is
harmless, because the old coordinates are still valid.

None of it can be pinned on the server. `grdctl` has no monitor or geometry
subcommand; the system daemon hard-codes `rdp-screen-share-mode` to `EXTEND` in
`grd_settings_system_new`, so mirror-primary is unreachable; and its `grd.conf`
accepts only `enabled`, `tls-cert`, `tls-key` and `port`. Remote Login takes
the geometry from the client on every connect, full stop. Pinning the CLIENT to
a fixed resolution does avoid the whole thing, at the cost of the auto-resize
this role advertises above.

Since nothing outside the compositor can move a window on Wayland, the fix is a
GNOME Shell extension: `files/rdp-window-fit`, installed into the desktop user's
home and enabled through `enabled-extensions`. It takes effect at the next
login, because the shell only scans for extensions at startup. On the same
1710x1107 -> 1280x800 reconnect it returns that window fully on screen, and a
1600x1000 window is resized to the 1280x752 work area instead of being left
hanging off two edges.

Verified on GNOME Shell 50 (Ubuntu 26.04). `metadata.json` also declares 48 and
49, which are not tested -- if it turns out to break on one, that is where to
narrow it. A failing extension is logged and disabled by the shell rather than
taking the session down, which is the point of the two rules below.

It is deliberately not the Window State Manager approach that was retired in
hyperi-io/hyperi-developer#39. It is stateless -- it saves no geometry, so it can
never restore a window onto a screen that no longer exists -- and it returns
immediately while no monitor exists, which is the state that made WSM trip
mutter's `meta_window_get_work_area_for_logical_monitor` assertion and abort
gnome-shell, taking every application in the session with it.

To rescue a window by hand, hold Super and drag it from anywhere in its surface
-- the title bar does not have to be visible. Alt+F7 then arrow keys does the
same from the keyboard.

We used to ship the Window State Manager GNOME extension for this. It saved and
restored window state across screen changes, and on the disconnect transition it
repositioned windows onto the monitor that had just been destroyed, tripping
`meta_window_get_work_area_for_logical_monitor: assertion failed:
(logical_monitor)`. That aborts gnome-shell, which takes gnome-session and every
application in it. It is gone (hyperi-io/hyperi-developer#39, #40), and any
replacement has to survive a state where no monitor exists at all.

## Recovering from a failed handover

Logging in over RDP while another session is already open for the same user
offers to force-stop it. Taking that offer makes gdm tear down the old session
**and the in-flight RDP login with it**, logged as:

    Gdm: GdmDisplay: Session never registered, failing

The login screen itself is not the problem - it appears, and the password is
accepted. The new session is collateral damage from reaping the old one.

What makes it feel permanent is the state it leaves behind: the system daemon
keeps accepting TCP on 3389 and services nothing. Every later connection gets a
blank screen, and the daemon does not log so much as an incoming connection.
Restarting `gdm` does **not** clear it - only restarting
`gnome-remote-desktop.service` does. On a headless host with no ssh, there is
no way back in at all.

`rdp-handover-watchdog.service` watches gdm's journal for that message and
restarts the daemon, with a 60s cooldown so one failure cannot become a restart
loop. Disable with `rdp_handover_watchdog_enabled: false`.

It matches the log rather than probing the port because telling a wedged daemon
from a healthy one over the wire needs a real RDP connection, and an aborted
one makes the daemon build and tear down a session - the same path that wedges
it. A periodic probe would risk causing the fault it watches for.

Deployed only where `/usr/lib/systemd/user/gnome-remote-desktop-handover.service`
exists. That unit is the two-stage handover this fault lives in, so gating on it
tests the mechanism rather than a version number.

### Testing it

**The real path needs a LOCAL session**, not a second RDP one. Remote sessions
are kept alive and resumed, so RDP-into-RDP never offers to force-stop anything
and never reaches the fault. On a headless VM with no console user there is
nothing to force-stop either.

At the machine's own keyboard:

1. Log in locally and leave the session open.
2. RDP in from elsewhere as the same user.
3. Accept the offer to force-stop the other session.
4. That login dies either way - the bug is upstream. Reconnect: without the
   watchdog every attempt is a blank screen forever; with it the reconnect
   reaches a login screen.

    journalctl -u rdp-handover-watchdog -u gnome-remote-desktop --since -5m

**Without the fault**, drive the watchdog off a synthetic unit -- the two
environment variables exist for this, and neither touches the real daemon or
any live session:

    sudo systemd-run --unit=wd-selftest \
        --setenv=RDP_WATCHDOG_SOURCE_UNIT=wd-selftest-source.service \
        --setenv=RDP_WATCHDOG_UNIT=wd-selftest-target.service \
        /usr/local/sbin/rdp-handover-watchdog

    sudo systemd-run --unit=wd-selftest-source \
        /usr/bin/echo "Gdm: GdmDisplay: Session never registered, failing"

    journalctl -u wd-selftest --no-pager
    sudo systemctl stop wd-selftest

Expect `failed handover detected -- restarting wd-selftest-target.service`. The
target does not exist, so the restart fails and says so; that is the point --
it proves detection without touching RDP.

### What it does not cover

Only the gdm marker. A daemon wedged some other way is not detected, and the
force-stop still costs you that one login attempt - fixing that is upstream
gdm's problem, not this role's.

## Files Modified

- `/etc/gnome-remote-desktop/` - System certificates
- `/usr/local/sbin/rdp-handover-watchdog` + `/etc/systemd/system/rdp-handover-watchdog.service` - failed-handover recovery
- `/etc/sysctl.d/98-rdp-tcp.conf` - TCP optimizations
- `/etc/sysctl.d/98-rdp-mtu.conf` - MTU settings
- `/etc/security/limits.d/50-rdp-nice.conf` - RLIMIT_NICE headroom for the handover daemon
- `~/.local/share/gnome-shell/extensions/rdp-window-fit@hyperi.io/` - window refit extension (desktop user's home)
- `/etc/systemd/system/gnome-remote-desktop.service.d/priority.conf` - Nice=-10 (software-encode path only)
- `/etc/systemd/user/gnome-remote-desktop-handover.service.d/priority.conf` - as above, user service
- System dconf settings - Window resize behavior, animations off

## Verification

After installation and password configuration:
```bash
# Check service status
sudo systemctl status gnome-remote-desktop.service

# Check RDP enabled
grdctl --system status

# Check TCP settings
sudo sysctl net.ipv4.tcp_window_scaling
sudo sysctl net.ipv4.tcp_congestion_control
```

All should show proper values as configured by the optimizer.

## Security Notes

- RDP runs on port 3389 (ensure firewall configured appropriately)
- Uses TLS encryption (certificates auto-generated)
- Separate password provides security isolation
- Desktop Sharing explicitly disabled to prevent conflicts

## Related Documentation

- [Main README](../../../README.md) - Overall project documentation
- [CONTRIBUTING.md](../../../CONTRIBUTING.md) - Development guidelines
- `./install.sh --list-apps` - the full role and tag list
