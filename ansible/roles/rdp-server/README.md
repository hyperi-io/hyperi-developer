# GNOME Remote Desktop (RDP) Optimizer

Optimizes GNOME Remote Desktop for use over RDP connections, including automatic window resizing and performance tuning.

## What It Does

1. **Disables Desktop Sharing** - Conflicts with Remote Login
2. **Enables Remote Login (RDP)** - For remote desktop connections
3. **Configures Auto-Resize** - Desktop automatically resizes to match RDP client window (which is also what strands windows off-screen on reconnect -- see [Window placement across resolution changes](#window-placement-across-resolution-changes))
4. **Performance Tuning** - TCP optimizations for RDP traffic
5. **Certificates** - Auto-generates system certificates for secure connections

## Platform Support

- **Fedora 42+** with GNOME Desktop
- **Ubuntu 24.04+** with GNOME Desktop
- **Not applicable** to macOS (uses different remote desktop methods)

## Usage

```bash
# Via install.sh
./install.sh --tags rdp-server

# Via Ansible directly
cd ansible
ansible-playbook -i inventories/localhost/inventory.yml playbooks/main.yml --tags rdp-server
```

## Important: RDP Password Configuration

**You MUST manually configure the RDP password after installation.**

The RDP password is **separate from your user account password** for security reasons. It's stored encrypted and only used for remote desktop authentication.

### Step-by-Step Password Configuration

1. **Open GNOME Settings**

2. **Go to Sharing**

3. **Click on Desktop Sharing or Remote Login**

You will see one of these screens:

#### Desktop Sharing Screen (Disable This)
![Desktop Sharing - Should be OFF](docs/desktop-sharing-off.png)

**Action:** Ensure "Desktop Sharing" toggle is **OFF** (conflicts with Remote Login)

#### Remote Login Screen (Configure This)
![Remote Login - Enable and Set Password](docs/remote-login-on.png)

**Action:**
- Ensure "Remote Login" toggle is **ON**
- Click "Set Password" button
- Create an RDP-specific password (different from your user password)
- Remember this password - you'll use it when connecting from RDP clients

### Why Two Different Passwords?

- **User Password:** For local login and sudo operations
- **RDP Password:** For remote desktop connections only
- Separation provides better security (compromise of one doesn't affect the other)
- RDP password is stored encrypted in GNOME Keyring

## Technical Details

### What Gets Configured

**Service Configuration:**
- `gnome-remote-desktop.service` - Enabled and started
- Desktop Sharing - Explicitly disabled (conflicts)
- Remote Login (RDP) - Explicitly enabled

**Certificates:**
- System certificates auto-generated in `/etc/gnome-remote-desktop/`
- Proper permissions (gnome-remote-desktop user ownership)
- Configured via `grdctl` for Remote Login mode

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
- Username: Your Linux username
- Password: The RDP password you configured (NOT your user password)

## Troubleshooting

### "Connection failed" or "Authentication failed"

1. Verify Remote Login is enabled (not Desktop Sharing)
2. Verify you set the RDP password in Settings → Sharing → Remote Login
3. Use the RDP password, not your user account password
4. Check firewall: `sudo firewall-cmd --list-all` (port 3389 should be open)

### "Desktop doesn't resize"

- TCP optimizations applied - requires reboot
- Check `/etc/sysctl.d/98-rdp-tcp.conf` exists
- Run: `sudo sysctl -p /etc/sysctl.d/98-rdp-tcp.conf`

### "Certificates error"

- Certificates auto-generated during installation
- Check: `sudo ls -la /etc/gnome-remote-desktop/`
- Should see: rdp-tls.crt, rdp-tls.key with proper ownership

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

### Windows land off-screen when you reconnect at a different size

Unfixable from this role, and it can strand a window where the mouse cannot
reach it. Mechanism and workarounds:
[Window placement across resolution changes](#window-placement-across-resolution-changes).

### Do not restart GRD on a live session

`systemctl restart gnome-remote-desktop.service` kills the GNOME session it is
serving. This role restarts the service at the end of a run, so **applying it
over RDP will drop your own connection mid-run**. Apply over SSH, from a local
console, or accept the reconnect.

## Window placement across resolution changes

Reconnect at a smaller geometry than the last session and some windows are
partly or wholly outside the new screen. A window whose title bar is off-screen
cannot be dragged back with the mouse, so it is effectively lost.

The cause is the gap between sessions, not the resize. On disconnect GRD
destroys its virtual monitor and the session is left with **no logical monitor
at all** -- the 640x480 you see in the logs is the default stage size that
remains. Mutter only rescales window positions when the old and the new logical
monitor both exist: `meta_window_update_for_monitors_changed` reaches
`meta_window_move_between_rects` only in that case (mutter 50,
`src/core/window.c`). Disconnect gives it no new monitor and reconnect gives it
no old one, so both transitions skip the rescale and every window keeps the
absolute coordinates it had. A window at x=1400 on a 1710-wide session is
outside a 1280-wide one, and nothing ever pulls it back.

The corollary is the useful half: **reconnecting at the SAME geometry is
harmless**, because the old coordinates are still valid. So the fix available
today is to stop the geometry varying -- set your client to a fixed resolution
and turn off dynamic resolution update, rather than letting it match the client
window. That trades away the auto-resize this role advertises above, and it is
the only thing that removes the fault outright.

None of it can be pinned on the server. `grdctl` has no monitor or geometry
subcommand; the system daemon hard-codes `rdp-screen-share-mode` to `EXTEND` in
`grd_settings_system_new`, so mirror-primary is unreachable; and its `grd.conf`
accepts only `enabled`, `tls-cert`, `tls-key` and `port`. Remote Login takes
the geometry from the client on every connect, full stop.

To rescue a window that is already stranded, hold Super and drag it from
anywhere in its surface -- the title bar does not have to be visible. Alt+F7
then arrow keys does the same from the keyboard.

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
