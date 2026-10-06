# packer

HashiCorp Packer, from HashiCorp's own package repositories. **Opt-in** -- not in the default install, not in any persona, not in `contributor` or `soe`.

    ./install.sh --tags packer

## Why its own role

Packer is the one HashiCorp tool we install. HashiCorp moved its tools to BUSL in 2023; terraform and vault have open-source forks (OpenTofu, OpenBao) and the `infrastructure` role installs those instead. Packer has no fork, so it ships only to boxes that ask for it -- image builds in hyperi-infra are the usual reason.

## What it touches

| Platform | Repository | Key | Package |
|---|---|---|---|
| Ubuntu | `/etc/apt/sources.list.d/hashicorp.sources`, suite = the host's codename | `/usr/share/keyrings/hashicorp-archive-keyring.asc` | `packer` |
| Fedora | `/etc/yum.repos.d/hashicorp.repo` | `/etc/pki/rpm-gpg/RPM-GPG-KEY-hashicorp` | `packer` |
| macOS | `hashicorp/tap` | - | `hashicorp/tap/packer` |

On Ubuntu it also removes `/etc/apt/sources.list.d/hashicorp.list`. Older tooling (hyperi-infra included) wrote the repo that way, and apt refuses every operation while one URI is configured twice with different `Signed-By` keys.

The Ubuntu key path is the one hyperi-infra uses, so a host it set up converges onto the same trusted file.

## Key pinning

The signing key is downloaded to `<key>.unverified` and only copied to the trusted path when it holds exactly one primary key and that key's fingerprint is `packer_hashicorp_key_fingerprint`. The default is the Linux repository key HashiCorp publishes at https://www.hashicorp.com/en/trust/security:

    D55C 0D1A C78A 8D81 26CB  631C FC9C A96A CA02 6560

It replaced `798A EC65 4E5C 1542 8C8E  42EE AA16 FCBC A621 E701`, which expired on 2026-09-10. A host still trusting the old key gets the new one on the next run.

A mismatch fails closed: the run removes the HashiCorp repo it would have used, leaves the previously trusted key alone, records a warning in the end-of-run report and carries on. Update the pin after checking the new fingerprint against HashiCorp's page.

## Removals

`--tags removals` takes terraform and vault away and leaves the HashiCorp repo, its keys and the tap in place, since this role installs from them.

## Verifying

    packer version
