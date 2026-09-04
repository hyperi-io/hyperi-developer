# Bounding concurrent Rust builds

`hyperi-rust-govern` is installed by the `developer-rust` role as
`~/.local/bin/cargo`, ahead of the real cargo on PATH, so a developer or an
agent who knows none of this runs `cargo build` and is governed. It holds one of
N build slots for the build's lifetime, and on Linux with a live user manager it
also places the build in `rust-build.slice`.

## How N is chosen

**N is a memory semaphore, not a queue length.** Memory is spent per *crate*,
not per job: one enormous crate compiles as a single `rustc` however high `-j`
goes, so what is worth bounding is how many builds are resident at once.

    N    = min(MemoryHigh / per-build allowance, cores-minus-reserve / 2)
    jobs = cores-minus-reserve / N          (floored at 2)

Both are computed by the shim at run time, from the cgroup memory limit where
one is set and `/proc/meminfo` otherwise, reproducing the arithmetic systemd
does for `MemoryHigh=<pct>%` against the same total. The slot count and the
memory ceiling therefore cannot drift, and a resized VM needs no re-converge.

| host RAM | MemoryHigh (50%) | N | jobs each (32 cores) |
|---|---|---|---|
| 256 GB | 128G | 8 | 3 |
| 128 GB | 64G | 4 | 7 |
| 64 GB | 32G | 2 | 15 |
| 32 GB | 16G | 1 | 30 |

The 32 GB row is a global mutex -- what this was before it was a semaphore --
and is the check that the model reproduces behaviour known to work.
`rust_governor_slots: 1` pins that everywhere.

The per-build allowance (`rust_governor_build_allowance_gb`, 14 GB) is the
largest single `rustc` observed plus headroom, taken from one workspace. A
codebase whose memory scales with the job count rather than with one huge crate
wants a different number.

The CPU reserve comes off the top *before* the remainder is divided, so the
desktop keeps its share at every slot count. No CPU quota is set anywhere: a
quota wastes cores whenever a session idles, while `CPUWeight` gives
proportional share under contention and the whole box when nothing competes.

## At saturation

**A build degrades, it is not released.** A build that cannot get a slot within
`rust_governor_lock_wait_seconds` proceeds at the floor job count -- and on
Linux with a live user manager, inside the slice under its own `MemoryMax` of
one allowance. Waiting the full timeout
and then building unbounded would drop the limit at exactly the moment
contention is highest.

**On Linux a slot is released by the kernel, not by cleanup.** It is an
`flock` on an open file description, so a killed or OOM-killed build frees its
slot with no reaper and no stale-lock detection. The fd is closed for the build
itself (`9>&-`), so a daemon the build starts cannot inherit the slot. macOS
ships no `flock(1)`, so there a slot is a directory held by an exit trap with a
liveness check on the recorded pid: a SIGKILLed holder is reclaimed by the next
arrival rather than by the kernel.

A build that starts alone keeps the crowded job count: `CARGO_BUILD_JOBS` is
fixed when the process starts. For a known-solo run, pass `CARGO_BUILD_JOBS`
yourself -- the shim respects a caller's value over its own.

## What it needs

**Swap.** `MemoryHigh` throttles by reclaim, and on a swapless host the only
reclaimable memory is page cache -- so a build past the line stalls rather than
slows. The `zram_swap` role is the other half, and a converge onto a swapless
host says so in its warnings.

**Incremental compilation left alone, by default.** sccache refuses to cache
any `rustc` call carrying `-C incremental`, so `rust_governor_no_incremental`
can turn incremental off to make builds cacheable -- but the win is narrower
than it looks. Cargo never builds *dependencies* incrementally, so those were
always cacheable; what this buys is caching of *workspace* crates, and it pays
by losing incremental on those same crates. Edit a large single-`rustc` crate
and sccache misses on the changed source with nothing to fall back on.

Turn it on for a build box, a CI runner, or a workstation running many sessions
against the same workspaces, where builds start from clean trees and there is no
incremental state to lose. `HYPERI_RUST_GOVERN_NO_INCREMENTAL=1` turns it on for
one invocation where the role left it off, and `=0` opts out where the role
turned it on. Neither is `CARGO_INCREMENTAL=1`, which makes sccache refuse the
build outright.
