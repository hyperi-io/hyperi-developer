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
| `remediation` | docker | **runnable** | the same, reproducibly, without a real machine |
| `matrix` | docker | **runnable** | a clean install works on each supported release |

`matrix` covers all four declared releases -- Fedora 44 and 43, Ubuntu 26.04 and
24.04 -- and is where Fedora coverage lives, since a fresh Fedora box must come
up correctly even though none have been deployed to drift.

It converges the CLI base only (`repository,utilities,git`). `repository` is not
optional in that set: it installs python3-debian, which every
`deb822_repository` task needs and a minimal image has no other source for.
Docker, snap and the GNOME paths want a daemon or a session a container has not
got, so widening the set means privileged or systemd containers first.

`sd` and `lazygit` are reported, not asserted. They come from GitHub releases on
at least one distro, and four containers sharing one unauthenticated GitHub API
quota get rate-limited -- a hard assertion would fail on GitHub's limiter rather
than on the playbook. The rescue path turns those into `deploy_warnings`, which
is the designed behaviour.

`../vars.yml` remains the SSoT for WHICH releases are supported. molecule.yml
cannot include another YAML file, so its platform list duplicates it and must be
bumped alongside.

`remediation` needs the docker driver, which molecule no longer bundles:

    uv tool install --with molecule-plugins[docker] --with docker molecule
    ansible-galaxy collection install -r ansible/requirements.yml
    molecule test -s remediation

It converges `--tags removals` only, so it removes and installs NOTHING. That
scopes what it can assert: the tombstones fired, and the things that are not
ours survived. Whether a REPLACEMENT arrived needs a full converge, which is
`existing-host`'s job. The same limit is why the unguarded `~/.bashrc` PATH
lines are not part of its fixture -- the tasks that clear those sit in the
install path, not under the `removals` tag.

Ubuntu only, deliberately. Remediation targets hosts that have been in the field
long enough to drift, and there are no deployed Fedora clients to drift. Fedora
coverage belongs to initial-deploy testing -- `matrix`, still unwritten.

The tag reaches every playbook molecule runs, so `prepare.yml` and `verify.yml`
carry `tags: always`. Without it the fixture is never planted and nothing is
ever asserted -- and the scenario passes, vacuously.

### matrix

Clean install across the supported set — n and n-1 per distro, because both n-1
slots roll within a year:

- Ubuntu LTS 26.04 (n), 24.04 (n-1)
- Fedora 44 (n), 43 (n-1)

We do NOT test n-2. Ubuntu LTS would allow it (22.04 lives to 2027-04), but
Fedora only ever supports two releases, so Fedora's n-2 is always EOL and its
mirrors are archived — the test would fail for reasons unrelated to us.
n and n-1 gives one rule for both distros, and the declared minimum IS n-1.

### remediation

`prepare` manufactures the drift, `converge` runs the real removals path over
it, `verify` asserts both directions.

The dangerous class is **shadowing**, where the host looks fine but isn't: a
stale `/usr/local/bin/uv` shadows the packaged uv on PATH, so `uv` runs, reports
a plausible version, and no system update ever touches it again. Every channel
move — a binary superseded by a package, a snap or flatpak superseded by a repo
— creates one, because `/usr/local/bin` and `/snap/bin` both precede `/usr/bin`.

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
