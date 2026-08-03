# Molecule scenarios

Automated testing for the playbook, including the **upgrade / remediation
path** for hosts provisioned by older versions of this project.

Molecule is the Ansible project's own test framework. We use it rather than a
bespoke harness because it already gives us the three things we need:
scenarios (the distro matrix), an `idempotence` check (converge twice, fail if
the second run reports changes), and `verify` (assertions against the
converged host).

## Why remediation needs testing at all

Ansible is **convergent, not declarative-with-pruning**. It enforces what you
DECLARE and has no concept of "this used to be declared, so remove it"
(Puppet has `purge`; Ansible has no equivalent, and OpenTofu can only do it
because it keeps state). So every tool we stop installing stays on every
existing host forever unless we explicitly remove it.

The fix is **tombstones**: when we drop a tool we add a `state: absent` task
rather than just deleting the install task. Tombstones are write-only code
that nobody ever proves works — which is exactly why they rot. These scenarios
prove they work.

Note we deliberately do NOT implement a Puppet-style purge (enumerate
installed, remove anything undeclared). `package_facts` could do it on Linux,
but on a developer workstation **undeclared state is the point** — people
install their own tools, and a purge would delete their work. A denylist of
what we removed is correct here; an allowlist of what is permitted is not.

## Scenarios

| scenario | driver | state | what it proves |
|---|---|---|---|
| `existing-host` | delegated (real machine) | **runnable** | an OLD host converges to current, and the old artefacts are GONE |
| `remediation` | containers | fixture only | the same, reproducibly, without a real machine |
| `matrix` | containers | not written | a clean install works on each supported release |

Only `existing-host` runs today. `remediation` carries its `prepare.yml` and
`verify.yml` but no `molecule.yml`, so there is nothing to invoke; `matrix` has
`vars.yml` and no scenario directory. Molecule 25 dropped its built-in drivers,
so finishing either means writing `create.yml` / `destroy.yml` playbooks against
`community.docker`.

### matrix

Clean install across the supported set. Config-driven from `vars.yml` — n and
n-1 per distro, never hardcoded, because both n-1 slots roll within a year:

- Ubuntu LTS 26.04 (n), 24.04 (n-1)
- Fedora 44 (n), 43 (n-1)

We do NOT test n-2. Ubuntu LTS would allow it (22.04 lives to 2027-04), but
Fedora only ever supports two releases, so Fedora's n-2 is always EOL and its
mirrors are archived — the test would fail for reasons unrelated to us.
n and n-1 gives one rule for both distros, and the declared minimum IS n-1.

### remediation

The upgrade path:

1. `prepare` — provision the container using an OLD tag of this project
2. `converge` — run the CURRENT playbook over the top
3. `verify` — assert the old artefacts are gone, not merely that the new ones
   arrived

Step 3 is the point. The dangerous class is **shadowing**, where the host
looks fine but isn't: a stale `~/.cargo/bin/uv` shadows the repo uv on PATH,
so `uv` runs, reports a plausible version, and no system update ever touches
it again.

### existing-host

Delegated against a real machine you already have. Point it at one with:

    export MOLECULE_TARGET_HOST=my-dev-box.example.internal
    export MOLECULE_TARGET_USER=me

No host is named in the repo — this one is public, and an internal hostname in
a public repo is topology anyone can read. There is no default either: an empty
value fails immediately and says why, where a wrong default would quietly point
the run at nothing.

**`create` and `destroy` are deliberately absent from this scenario's
`test_sequence`** — a real workstation must never be created or destroyed by a
test run. Snapshot the machine before running it; `converge` genuinely changes
it.

## Running

    cd ansible

    # against a real machine (snapshot first!)
    export MOLECULE_TARGET_HOST=my-dev-box.example.internal
    export MOLECULE_TARGET_USER=me
    molecule converge -s existing-host -- --tags soe
    molecule verify   -s existing-host

**When the connection user is not the desktop user**, name the desktop one --
a fleet machine is reached as a service account whose home holds none of the
artefacts under test:

    export MOLECULE_TARGET_USER=ubuntu           # who we ssh as
    export MOLECULE_TARGET_DESKTOP_USER=hyperi   # whose machine it is
    molecule converge -s existing-host -- --tags soe -e hyperi_target_user=hyperi
    molecule verify   -s existing-host

Without it every user-scoped check passes against the service account's empty
home while the real user keeps the artefact -- a green run over a host that was
never fixed. `converge` takes it as `-e hyperi_target_user`; `verify` takes no
extra arguments, so it reads the environment.

`--tags soe` (or `--tags removals`) is not optional for a remediation run: the
tombstones gate on `ansible_run_tags`, so a plain converge installs the new
tools and removes nothing.

The scenario runs from `ansible/`, and `molecule.yml` pins `roles_path` to
`${MOLECULE_PROJECT_DIRECTORY}/roles` because molecule writes its own
`ansible.cfg` and never reads this repo's. The target host comes from
`inventory.yml`, linked in as molecule's `hosts` file -- molecule generates its
inventory from `platforms`, and this scenario has none, so without that link the
run converges the machine you launched it from.

Preview destructive tombstones before applying them — this is the Puppet
`noop` habit, and tombstones are the destructive part of the playbook:

    molecule converge -s existing-host -- --check --diff

## Container coverage limits

Containers cannot test everything, and that is accepted:

- **No GUI.** Anything gated on `has_gnome` is skipped.
- **systemd.** Tasks that start services need a systemd-enabled, privileged
  image; without one they are skipped rather than failed.
- **Docker daemon.** Installing docker-ce in a container works; *starting* it
  needs privileged + cgroups.

What containers DO cover, and what VMs were too slow to ever cover in
practice: package installs, repo configuration, file deployment, version
gating, and — critically — the tombstones.
