# Snapshot-reset testing against Proxmox VMs

Run hyperi-developer against a real VM from a known clean state, as many times
as needed, by hand. Not CI: it needs a Proxmox endpoint and credentials.

Configuration is the `TEST VMS` block in `tests/.env` (copy
`tests/.env.sample`). Authentication is the same Proxmox API token
hyperi-infra's tools use -- `PROXMOX_TOKEN_ID` and `PROXMOX_TOKEN_SECRET`,
never a root password. Login to the VM itself is by key: cloud-init installs
the `.pub` of `PROXMOX_TEST_SSH_KEY` for the test user, because cloud images
ship sshd with password login off. Everything here runs from `ansible/`.

The modules need `proxmoxer` on the machine running the playbook, for the
Python that Ansible uses: `sudo apt install python3-proxmoxer` on Debian and
Ubuntu, or pip inside whatever venv runs Ansible. Then
`ansible-galaxy collection install -r requirements.yml` for `community.proxmox`.

## Make a clean VM once

    ansible-playbook tests/proxmox/create.yml -e vm_name=ubuntu-test.example.com \
        -e vmid=8101 -e ip=192.0.2.51/24

Clones the base template, sizes it from `.env` (cores, memory, disk,
storage), gives it a static address or DHCP, boots it once to bring every
package current, **stops it**, and snapshots it as `clean`. hyperi-developer
never runs here: the snapshot is the state every test starts from.

The VM name is what Proxmox and the lab DNS see, so name a static VM by its
FQDN. Leave off `-e vmid` for the lowest free id in the range and `-e ip` for
DHCP, where the lab DNS names the VM `<vm_name>.<domain>`.

The base template, not the desktop one: the desktop template bakes
hyperi-developer in, which is the thing under test.

## Test

    ansible-playbook tests/proxmox/reset.yml -e vmid=8101
    ansible-playbook -i tests/proxmox/inventory_proxmox.yml playbooks/main.yml --tags developer-rust
    ansible-playbook tests/proxmox/reset.yml -e vmid=8101 -e start=false

`reset.yml` stops the VM, rolls it back to `clean`, starts it, waits for sshd,
and writes `inventory_proxmox.yml` for it. The last line is the resting state:
a test VM is off except while a test runs, so finish by rolling it back again
and leaving it stopped.

A VM made some other way -- the Fedora box, say -- passes its own snapshot
name and login: `-e snapshot=initial_build -e test_user=dfe -e test_password=dfe`.

## Remove

    ansible-playbook tests/proxmox/delete.yml -e vmid=8102

## Safety

All three playbooks refuse a vmid outside `PROXMOX_TEST_VMID_MIN..MAX`. A
rollback or delete discards everything on the machine, so that range is the
only place it can happen.

`provision.yml` and `test_all.yml` predate this and target a fixed
Fedora+Ubuntu pair; `test_all.yml` also installs from a branch that no longer
exists. Prefer the playbooks above.
