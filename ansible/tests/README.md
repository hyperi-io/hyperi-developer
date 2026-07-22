# Test Infrastructure

Automated testing on Proxmox (Fedora/Ubuntu). macOS is tested directly on a
local Mac (run `./install.sh` on the machine itself).

## Setup

1. Copy `.env.sample` to `.env`:
   ```bash
   cp .env.sample .env
   ```

2. Edit `.env` with your Proxmox server details.

3. **NEVER commit `.env`** - it's gitignored and contains secrets!

## Usage

### Proxmox Tests (Fedora + Ubuntu)

```bash
# Reset VMs to clean snapshots and generate inventory
ansible-playbook tests/proxmox/provision.yml

# Run all comprehensive tests (Ansible + install.sh on both VMs)
ansible-playbook tests/proxmox/test_all.yml

# Or run deployment tests directly
ansible-playbook -i tests/proxmox/inventory_proxmox.yml playbooks/main.yml
```

### macOS

Run the playbook on the Mac itself:

```bash
./install.sh              # or a specific tag set, e.g. ./install.sh --soe
```

## Cost Management

- **Proxmox**: Free (local VMs), instant reset via snapshots.

## Security

- `.env` contains sensitive credentials and is gitignored (root and
  `ansible/tests/`).
- Use `.env.sample` as a template only.
- Never hardcode credentials in playbooks or committed inventories - the
  playbooks read every host and secret from the environment via
  `lookup('env', ...)`, so the repo leaks no infra topology.
