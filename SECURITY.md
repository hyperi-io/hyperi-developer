# Security Policy

## Reporting a vulnerability

Report privately through
[GitHub Security Advisories](https://github.com/hyperi-io/hyperi-developer/security/advisories/new).
Please do not open a public issue for a vulnerability.

Tell us what you can: what the problem is, how to reproduce it, which platform
and version you saw it on, and what an attacker could do with it. A partial
report is still worth sending.

We aim to acknowledge within a few working days. Once there is a fix we will
credit you in the advisory unless you would rather stay anonymous.

## What this project is

An installer. It configures developer workstations, so it runs with elevated
privileges and fetches software from upstream repositories and release pages.
The things worth reporting are therefore:

- A tool fetched over a channel that cannot be verified, or from a source that
  is not the vendor's own.
- A task that widens the machine's exposure more than its purpose requires --
  a service reachable off the loopback interface, a credential written
  world-readable, a permission broader than it needs.
- A world-writable path used for anything a privileged step later reads.
- Anything in the tree that ships a credential, an internal hostname, or a
  private registry URL. This repo is public.

Vulnerabilities in the software this project *installs* belong upstream with
that project. If our installation of it makes the problem worse, that part is
ours -- send it here.

## Supported versions

Fixes land on `main` and ship in the next release. There are no maintained
release branches, so please confirm a problem still exists on `main` before
reporting it.
