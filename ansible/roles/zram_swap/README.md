# zram_swap

A small zram-backed swap device, so cgroup memory limits throttle instead of
stalling. **Opt-in** -- not in the default install, not in `contributor`, not in
`soe`.

    ./install.sh --tags zram

## Why this is not "add some swap"

`MemoryHigh` on a cgroup is implemented as **reclaim**, not as a hard block. It
does not refuse an allocation; it pushes the cgroup into reclaim and lets it
carry on, which is what makes it a soft limit worth setting.

On a host with no swap the only reclaimable memory is page cache. So once a
process group's **anonymous** memory passes `MemoryHigh` there is nothing left
to reclaim, and the throttle stops behaving like a slowdown and starts behaving
like a stall.

zram fixes that by making anonymous pages reclaimable: they are compressed in
place rather than written anywhere. It adds no capacity and is not a swap tier.
It is somewhere for the throttle to push, which is why a few GB is the right
size and a disk-backed swap file is not a substitute.

This matters most on a host running `developer-rust`'s build governor, whose
`rustbuild.slice` sets `MemoryHigh` and `MemorySwapMax` as percentages of RAM.
Without swap, those limits do not degrade a build -- they wedge it.

## What it touches

- `/etc/systemd/zram-generator.conf` -- the device definition. This **replaces**
  the distro default rather than merging with it, deliberately: Fedora's
  `zram-generator-defaults` ships a `host-memory-limit`, and a host with more
  RAM than that limit silently gets no device at all.
- `/etc/sysctl.d/zzz-50-hyperi-zram.conf` -- `vm.swappiness`, defaulting to 180
  rather than the stock 60. Swappiness balances reclaiming page cache against
  reclaiming anonymous memory, and 60 was tuned for swap that costs a disk seek.
  zram costs a compress, so anonymous memory is the cheaper thing to reclaim.
  Set `zram_swap_swappiness: ""` to leave the host alone -- which is what you
  want if the box also has disk swap, since 180 would then push pages to a disk.
- `systemd-zram-setup@zram0.service` -- started. Generator-created units
  cannot be enabled; the generator wires it into `swap.target` itself.

## Sizing

| variable | default | on 246 GB | on 32 GB | on 8 GB |
|---|---|---|---|---|
| `zram_swap_size` | `min(ram / 8, 8192)` | 8 GiB | 4 GiB | 1 GiB |

Capped at 8 GiB because the device is a reclaim target, not capacity.

## Re-running with a changed size

The role never restarts a running zram device. Applying a new size means
`swapoff`, which pages every byte held in the device back into RAM -- on a host
under memory pressure that is precisely the wrong moment, and it is how applying
a config change OOMs a build box. A changed size is written to the config and
takes effect at the next reboot.

## Verifying

    swapon --show
    zramctl
    sysctl vm.swappiness
