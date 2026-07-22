# GNOME Remote Desktop (RDP) Optimizer

Optimizes GNOME Remote Desktop for use over RDP connections, including automatic window resizing and performance tuning.

## What It Does

1. **Disables Desktop Sharing** - Conflicts with Remote Login
2. **Enables Remote Login (RDP)** - For remote desktop connections
3. **Configures Auto-Resize** - Desktop automatically resizes to match RDP client window
4. **Performance Tuning** - TCP optimizations for RDP traffic
5. **Certificates** - Auto-generates system certificates for secure connections

## Platform Support

- **Fedora 42+** with GNOME Desktop
- **Ubuntu 24.04+** with GNOME Desktop
- **Not applicable** to macOS (uses different remote desktop methods)

## Usage

```bash
# Via install.sh
./install.sh --rdp

# Via Ansible directly
cd ansible
ansible-playbook -i inventories/localhost/inventory.yml playbooks/main.yml --tags rdp
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

### Do not restart GRD on a live session

`systemctl restart gnome-remote-desktop.service` kills the GNOME session it is
serving. This role restarts the service at the end of a run, so **applying it
over RDP will drop your own connection mid-run**. Apply over SSH, from a local
console, or accept the reconnect.

## Files Modified

- `/etc/gnome-remote-desktop/` - System certificates
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
