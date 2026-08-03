# power-profile

Sleep, idle and lid policy for machines that must stay reachable. **Opt-in** --
it is not in the default install, not in `contributor` and not in `soe`, because
the right answer differs per machine and the wrong one cooks a laptop in a bag.

    ./install.sh --tags power-profile                          # always-on
    ./install.sh --tags power-profile -e power_profile=vm      # RDP guest

## Profiles

| profile | for | behaviour |
|---|---|---|
| `always-on` (default) | a repurposed laptop doing build work, a desktop that has to answer ssh | never sleeps on mains power, lid shut included; stock behaviour on battery; the screen may still blank |
| `vm` | an always-on virtual desktop reached over RDP | never sleeps or suspends at all; the sleep targets are masked |

## Adding a profile

A profile is data, not tasks. Drop a file in `vars/profiles/<name>.yml` and add
a row above -- there is no dispatch to edit, and an unknown name fails with the
list of what does exist.

```yaml
power_profile_summary: >-
  one line, printed at the end of the run
power_profile_logind:            # keys go verbatim into the [Login] drop-in
  HandleLidSwitch: suspend
power_profile_gnome:             # org.gnome.settings-daemon.plugins.power
  sleep-inactive-ac-type: nothing
power_profile_mask_sleep_targets: false
power_profile_macos_ac_sleep: 0  # pmset -c sleep
```

## What it touches

- `/etc/systemd/logind.conf.d/10-hyperi-power-profile.conf` -- a drop-in, so a
  package upgrade replacing `logind.conf` does not undo it. Applied with a
  reload, never a restart: restarting `systemd-logind` tears down the running
  graphical session.
- `org.gnome.settings-daemon.plugins.power` via dconf, per-user. GNOME runs its
  own idle timer on top of logind, so logind alone does not settle it.
- `systemctl mask` on the sleep targets, where the profile asks for it.
- macOS: `pmset -c sleep`. Lid close there is a separate path that pmset cannot
  scope to a power source, so `power_profile_macos_disable_sleep` is opt-in --
  it stops battery sleep too.

## Verifying

    loginctl show-manager | grep HandleLidSwitch
    gsettings get org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type
    systemctl status sleep.target
