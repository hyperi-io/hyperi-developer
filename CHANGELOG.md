# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased] — Role Structure Refactor

### Added
- Two-tier base split: `developer` (OSS-safe) and `core` (Hyperi internal, implies `developer`).
- Profile-based installation via `./install.sh --profile`: `rust`, `iac`, `gui_extras`, `openvpn` add-on profiles, plus `--profile` validation in `install.sh`.
- Opt-out variables centralised in `ansible/inventories/localhost/group_vars/all.yml`
  (`install_bitwarden`, `install_onlyoffice`, `install_brave`, `install_slack`, `install_linear`).
- New tools in the `developer` base: `wl-clipboard`, `kcat`.
- New `gui_extras` profile: Freelens, Bruno, Podman Desktop, DBeaver Community, lazygit.
- WireGuard as the default Hyperi VPN (now in `core`).
- Per-tool rationale document at `docs/TOOLS.md`.
- Bats tests for `install.sh --profile` validation (`tests/bats/install_profile.bats`).
- URL/pin audit script (`tests/audit/urls_and_pins.py`).
- OSS-safe post-install assertion script (`tests/assertions/oss_safe.sh`).

### Changed
- `developer_core` role dissolved — contents redistributed into `developer`, `core`, `rust`, `iac`, `openvpn`.
- `playbooks/main.yml` restructured around the new tiered role layout.
- Default install (`./install.sh` with no args) now runs `--profile developer` — a behaviour change for users expecting "install everything".

### Deprecated
- `--core` flag → use `--profile core,rust,iac`. Alias emits a deprecation warning; removed in next release.
- `--all` flag → use `--profile core,all`. Alias emits a deprecation warning; removed in next release.

### Removed
- NetBird CLI (removed in earlier PR; reaffirmed here — no longer part of `core`).
- `developer_core` role directory.
- Mailspring desktop email client (no longer used).

## [2.23.14](https://github.com/hyperi-io/dfe-developer/compare/v2.23.13...v2.23.14) (2026-02-20)


### Bug Fixes

* replace PAM GPU group approach with udev world-readable rule ([fff2cc2](https://github.com/hyperi-io/dfe-developer/commit/fff2cc275ad2eff4c885d406320de9850690cc81))

## [2.23.13](https://github.com/hyperi-io/dfe-developer/compare/v2.23.12...v2.23.13) (2026-02-17)


### Bug Fixes

* use system dconf profile for RDP animation disable ([cc097c0](https://github.com/hyperi-io/dfe-developer/commit/cc097c0447655e76e15e1bbad430cf505db29dcf))

## [2.23.12](https://github.com/hyperi-io/dfe-developer/compare/v2.23.11...v2.23.12) (2026-02-17)


### Bug Fixes

* remove duplicate mesa-va-drivers from vm_tools (already in rdp role) ([9e445df](https://github.com/hyperi-io/dfe-developer/commit/9e445dfb047097a81eb530b285da142d09390951))

## [2.23.11](https://github.com/hyperi-io/dfe-developer/compare/v2.23.10...v2.23.11) (2026-02-17)


### Bug Fixes

* tune RDP software encoding for virtio-gpu VMs without VA-API H.264 ([5fbd6ca](https://github.com/hyperi-io/dfe-developer/commit/5fbd6cab09a763c90fccced6a067ac39c1599bab))

## [2.23.10](https://github.com/hyperi-io/dfe-developer/compare/v2.23.9...v2.23.10) (2026-02-17)


### Bug Fixes

* add mesa-va-drivers for VA-API video acceleration in VMs ([29c4fdb](https://github.com/hyperi-io/dfe-developer/commit/29c4fdb0d7a0849bdcf6f9bb8038fd9eeebb43bf))

## [2.23.9](https://github.com/hyperi-io/dfe-developer/compare/v2.23.8...v2.23.9) (2026-02-16)


### Bug Fixes

* add desktop-mode script for winlike/maclike switching ([2373c42](https://github.com/hyperi-io/dfe-developer/commit/2373c42b8d69ef7fd76e7ddcc1ae577fc53d9071))

## [2.23.8](https://github.com/hyperi-io/dfe-developer/compare/v2.23.7...v2.23.8) (2026-02-16)


### Bug Fixes

* rewrite broken symlinks after home directory rename ([0d14135](https://github.com/hyperi-io/dfe-developer/commit/0d14135d1b360defccbbbde81e636d7a1a4c8756))

## [2.23.7](https://github.com/hyperi-io/dfe-developer/compare/v2.23.6...v2.23.7) (2026-02-16)


### Bug Fixes

* change default --all UI mode from maclike to winlike ([99afa79](https://github.com/hyperi-io/dfe-developer/commit/99afa7997795586d9da18e53dcbda98752a47b38))

## [2.23.6](https://github.com/hyperi-io/dfe-developer/compare/v2.23.5...v2.23.6) (2026-02-16)


### Bug Fixes

* rename-user heredoc expansion bug and keyring reset ([ef73811](https://github.com/hyperi-io/dfe-developer/commit/ef73811b55e0f44a10d84aabe6cbfde662cda9b7))

## [2.23.5](https://github.com/hyperi-io/dfe-developer/compare/v2.23.4...v2.23.5) (2026-02-16)


### Bug Fixes

* add LTS codename fallback for OpenVPN3 repo on Ubuntu interim releases ([2427e01](https://github.com/hyperi-io/dfe-developer/commit/2427e0194101f3732786c8f5496d8e25cb781a3c))

## [2.23.4](https://github.com/hyperi-io/dfe-developer/compare/v2.23.3...v2.23.4) (2026-02-16)


### Bug Fixes

* add LTS codename fallback for HashiCorp, Docker, and git-core repos ([21608fb](https://github.com/hyperi-io/dfe-developer/commit/21608fb4788691d32fb1e2567281f15f76c453d2))

## [2.23.3](https://github.com/hyperi-io/dfe-developer/compare/v2.23.2...v2.23.3) (2026-02-15)


### Bug Fixes

* add regional locale support and rename-user script ([3f07a98](https://github.com/hyperi-io/dfe-developer/commit/3f07a98acc44282a5dc88d848ec9b9fd48e4a5de))
* azure CLI and vector apt repos for plucky (Ubuntu 25.04) ([839c5a1](https://github.com/hyperi-io/dfe-developer/commit/839c5a1f7186a413ab23ed07a7bf84ae6abeee45))

## [2.23.2](https://github.com/hyperi-io/dfe-developer/compare/v2.23.1...v2.23.2) (2026-02-13)


### Bug Fixes

* replace deprecated apt-key with signed-by keyring for OnlyOffice ([c704bd0](https://github.com/hyperi-io/dfe-developer/commit/c704bd0bf56744c021067bfdb53ada6b64f2af7b))
* use HTTP export for git-core PPA GPG keys ([8aed3fa](https://github.com/hyperi-io/dfe-developer/commit/8aed3fa53b7112c74b2902262ef0e5e121b63b5b))

## [2.23.1](https://github.com/hypersec-io/dfe-developer/compare/v2.23.0...v2.23.1) (2026-02-09)


### Bug Fixes

* use isolated GNUPGHOME for git-core PPA GPG key import ([7a67dd7](https://github.com/hypersec-io/dfe-developer/commit/7a67dd7541655767b2db8b1614de078a86295433))

# [2.23.0](https://github.com/hypersec-io/dfe-developer/compare/v2.22.2...v2.23.0) (2026-02-09)


### Features

* dual GPG key for git-core PPA, Claude Code updates ([659a367](https://github.com/hypersec-io/dfe-developer/commit/659a36726c979a6aff98f1caa2c799648a0bc9e8))

## [2.22.2](https://github.com/hypersec-io/dfe-developer/compare/v2.22.1...v2.22.2) (2026-02-09)


### Bug Fixes

* skip git-core PPA on non-LTS Ubuntu (Plucky 25.04+) ([72d1f03](https://github.com/hypersec-io/dfe-developer/commit/72d1f03a31896459223d5d015f341efc51817c80))

## [2.22.1](https://github.com/hypersec-io/dfe-developer/compare/v2.22.0...v2.22.1) (2026-02-09)


### Bug Fixes

* quote awk command in gpu_groups.yml to fix YAML parsing ([bdba2ec](https://github.com/hypersec-io/dfe-developer/commit/bdba2ec04c1aebbf92f0c90b2ccc98c092099a0c))

# [2.22.0](https://github.com/hypersec-io/dfe-developer/compare/v2.21.3...v2.22.0) (2026-02-09)


### Features

* rebrand from HyperSec to HyperI ([9ea5514](https://github.com/hypersec-io/dfe-developer/commit/9ea551460387778b5eb21fe842759ed47f270bde))

## [2.21.3](https://github.com/hypersec-io/dfe-developer/compare/v2.21.2...v2.21.3) (2026-02-09)


### Bug Fixes

* add RUSTUP_HOME env to Rust verification task ([7147bf9](https://github.com/hypersec-io/dfe-developer/commit/7147bf918b9a35ddbf9d3e7a96e433fc7f49463f))

## [2.21.2](https://github.com/hypersec-io/dfe-developer/compare/v2.21.1...v2.21.2) (2026-02-08)


### Bug Fixes

* use full path for rustc verification after rustup migration ([bab38cc](https://github.com/hypersec-io/dfe-developer/commit/bab38ccaa69c602d8d7c095fadfc3f6d61d4267f))

## [2.21.1](https://github.com/hypersec-io/dfe-developer/compare/v2.21.0...v2.21.1) (2026-02-08)


### Bug Fixes

* add libssl-dev build dependency for cargo tools ([a9368fe](https://github.com/hypersec-io/dfe-developer/commit/a9368fe4e72672046e663b17e5b9184a8dbddfdc))

# [2.21.0](https://github.com/hypersec-io/dfe-developer/compare/v2.20.7...v2.21.0) (2026-02-06)


### Features

* add cargo-update for keeping cargo tools current ([f591c2c](https://github.com/hypersec-io/dfe-developer/commit/f591c2cbc1bb26d95c5f395c93f02a71b656de7c))

## [2.20.7](https://github.com/hypersec-io/dfe-developer/compare/v2.20.6...v2.20.7) (2026-02-06)


### Bug Fixes

* use rustup instead of distro packages for Rust toolchain ([37b7845](https://github.com/hypersec-io/dfe-developer/commit/37b78456a9213a6d45f2826901b8ba22c525c95b))

## [2.20.6](https://github.com/hypersec-io/dfe-developer/compare/v2.20.5...v2.20.6) (2026-02-06)


### Bug Fixes

* dearmor Google Cloud GPG key for apt repository ([00f5769](https://github.com/hypersec-io/dfe-developer/commit/00f5769d0b0d45c649934232ea182286330e403c))

## [2.20.5](https://github.com/hypersec-io/dfe-developer/compare/v2.20.4...v2.20.5) (2026-02-06)


### Bug Fixes

* add Google Cloud CLI to developer_core role ([f1a1de6](https://github.com/hypersec-io/dfe-developer/commit/f1a1de655932ad276043aec5b88e6dd4c77f36a8))

## [2.20.4](https://github.com/hypersec-io/dfe-developer/compare/v2.20.3...v2.20.4) (2026-02-03)


### Bug Fixes

* add Rust toolchain and cargo tools to developer_core role ([914a873](https://github.com/hypersec-io/dfe-developer/commit/914a8736707febef1859e0ba98db7253c14a4447))

## [2.20.3](https://github.com/hypersec-io/dfe-developer/compare/v2.20.2...v2.20.3) (2026-02-01)


### Bug Fixes

* disable Ghostty copy notification popup ([de4d5d6](https://github.com/hypersec-io/dfe-developer/commit/de4d5d681c85694af19fea2e6576fd701727e864))

## [2.20.2](https://github.com/hypersec-io/dfe-developer/compare/v2.20.1...v2.20.2) (2026-01-21)


### Bug Fixes

* GPU groups and duplicate app icons ([d67b632](https://github.com/hypersec-io/dfe-developer/commit/d67b6328a9d32b2f56212f706a3490a58066585a))

## [2.20.1](https://github.com/hypersec-io/dfe-developer/compare/v2.20.0...v2.20.1) (2026-01-20)


### Bug Fixes

* desktop template improvements ([8bc62c9](https://github.com/hypersec-io/dfe-developer/commit/8bc62c9a54950798afd3e2fe2b5340a793c8b830))

# [2.20.0](https://github.com/hypersec-io/dfe-developer/compare/v2.19.1...v2.20.0) (2026-01-20)


### Features

* Replace LibreOffice with OnlyOffice as default office suite ([e65493a](https://github.com/hypersec-io/dfe-developer/commit/e65493addf76e39978e6cbdf36f85fbe50f72357))

## [2.19.1](https://github.com/hypersec-io/dfe-developer/compare/v2.19.0...v2.19.1) (2026-01-20)


### Bug Fixes

* Re-detect GNOME after desktop.yml installs it ([eb3457d](https://github.com/hypersec-io/dfe-developer/commit/eb3457d399b3c6ccffbfe9bd0055b5d77f5cd83e))

# [2.19.0](https://github.com/hypersec-io/dfe-developer/compare/v2.18.3...v2.19.0) (2026-01-17)


### Features

* make maclike (macOS-style) the default GNOME config for --all ([5ddbbe7](https://github.com/hypersec-io/dfe-developer/commit/5ddbbe77fbe868918cdc4b143aef60a8d2c3790c))

## [2.18.3](https://github.com/hypersec-io/dfe-developer/compare/v2.18.2...v2.18.3) (2026-01-16)


### Bug Fixes

* replace Betterbird with OnlyOffice/Mailspring, simplify GNOME detection ([1893754](https://github.com/hypersec-io/dfe-developer/commit/1893754fe6c9be50f69dcbd8874f207747193783)), closes [#2](https://github.com/hypersec-io/dfe-developer/issues/2)

## [2.18.2](https://github.com/hypersec-io/dfe-developer/compare/v2.18.1...v2.18.2) (2026-01-15)


### Bug Fixes

* add flatpak polkit rule for RDP sessions and keep snapd ([1279576](https://github.com/hypersec-io/dfe-developer/commit/12795765d92eabb13b75684ad613dc177f0ef1f8))

## [2.18.1](https://github.com/hypersec-io/dfe-developer/compare/v2.18.0...v2.18.1) (2026-01-15)


### Bug Fixes

* add ai/ to gitignore and fix D-Bus session for ui-mode ([6cf453a](https://github.com/hypersec-io/dfe-developer/commit/6cf453a8ce7e4a8bd0c94ba12cd27fa98fdb0e84)), closes [#1](https://github.com/hypersec-io/dfe-developer/issues/1)


### Reverts

* remove PipeWire frame rate reduction ([634f698](https://github.com/hypersec-io/dfe-developer/commit/634f69814d6e68f90ac0122fb046c2a26ae49d71))

# [2.18.0](https://github.com/hypersec-io/dfe-developer/compare/v2.17.2...v2.18.0) (2026-01-15)


### Features

* **rdp:** add PipeWire frame rate optimization for software encoding ([9fe2c29](https://github.com/hypersec-io/dfe-developer/commit/9fe2c298843dbd345c2a952807c82e5072d5ced6))

## [2.17.2](https://github.com/hypersec-io/dfe-developer/compare/v2.17.1...v2.17.2) (2026-01-15)


### Bug Fixes

* ensure uv installed before gnome-extensions-cli ([38a0561](https://github.com/hypersec-io/dfe-developer/commit/38a0561b559176e1533b2fb130b905123e8a8127))

## [2.17.1](https://github.com/hypersec-io/dfe-developer/compare/v2.17.0...v2.17.1) (2026-01-14)


### Bug Fixes

* keep Firefox installed in desktop builds ([651d36e](https://github.com/hypersec-io/dfe-developer/commit/651d36e2a269af7229337524599da20cd69f0d47))

# [2.17.0](https://github.com/hypersec-io/dfe-developer/compare/v2.16.2...v2.17.0) (2026-01-14)


### Features

* enable LibreOffice by default in desktop builds ([cd62384](https://github.com/hypersec-io/dfe-developer/commit/cd62384794a7b05ce5b6b6f9bbc5bf88c5e9a2d6))

## [2.16.2](https://github.com/hypersec-io/dfe-developer/compare/v2.16.1...v2.16.2) (2026-01-14)


### Bug Fixes

* skip apport disable when package not installed ([fa63e39](https://github.com/hypersec-io/dfe-developer/commit/fa63e3942a76db2adb8b39b7ded356f37c19f666))

## [2.16.1](https://github.com/hypersec-io/dfe-developer/compare/v2.16.0...v2.16.1) (2026-01-14)


### Bug Fixes

* keep install_recommends, remove unwanted packages explicitly ([79b9d24](https://github.com/hypersec-io/dfe-developer/commit/79b9d245f83c78c0ae310383d08007808a077f2f))

# [2.16.0](https://github.com/hypersec-io/dfe-developer/compare/v2.15.1...v2.16.0) (2026-01-14)


### Features

* add Nemo file manager as default (Ubuntu + Fedora) ([ad09b70](https://github.com/hypersec-io/dfe-developer/commit/ad09b7070032181b1688d187c80ac2dac52c12d0))

## [2.15.1](https://github.com/hypersec-io/dfe-developer/compare/v2.15.0...v2.15.1) (2026-01-14)


### Bug Fixes

* prevent LibreOffice install, remove favorite-apps customization ([177f27d](https://github.com/hypersec-io/dfe-developer/commit/177f27d187b22bbdf1c74567017f954f5a000830))

# [2.15.0](https://github.com/hypersec-io/dfe-developer/compare/v2.14.9...v2.15.0) (2026-01-14)


### Features

* configurable branding, browser policies, gnome-initial-setup fix ([1c9dddc](https://github.com/hypersec-io/dfe-developer/commit/1c9dddc96d6d7d8c9d1a01ae03b706c55211a648))

## [2.14.9](https://github.com/hypersec-io/dfe-developer/compare/v2.14.8...v2.14.9) (2026-01-13)


### Bug Fixes

* **gnome:** skip ui-mode when GNOME Shell not running ([5178358](https://github.com/hypersec-io/dfe-developer/commit/51783589d68d8e9216bd9240642a20c882651610))

## [2.14.8](https://github.com/hypersec-io/dfe-developer/compare/v2.14.7...v2.14.8) (2026-01-13)


### Bug Fixes

* **gnome:** use --ignore-installed for pip upgrade on Ubuntu ([fc4bfb2](https://github.com/hypersec-io/dfe-developer/commit/fc4bfb2e0f5349d2db66306f342f8192e9ea9021))

## [2.14.7](https://github.com/hypersec-io/dfe-developer/compare/v2.14.6...v2.14.7) (2026-01-13)


### Bug Fixes

* **gnome:** add --break-system-packages for Ubuntu PEP 668 compliance ([bddab1e](https://github.com/hypersec-io/dfe-developer/commit/bddab1eb57159f1be87fad15b8303f75efb86e38))

## [2.14.6](https://github.com/hypersec-io/dfe-developer/compare/v2.14.5...v2.14.6) (2026-01-13)


### Bug Fixes

* **gnome:** add explicit become: true for system-wide pip upgrades ([8e173c9](https://github.com/hypersec-io/dfe-developer/commit/8e173c97564ed43d95306131c518b62898b53306))
* **gnome:** upgrade pip/pipx in-place instead of removing distro packages ([4f3423b](https://github.com/hypersec-io/dfe-developer/commit/4f3423b5eaabd78c2c9cd66a2fc7dcb8fe796381))

## [2.14.5](https://github.com/hypersec-io/dfe-developer/compare/v2.14.4...v2.14.5) (2026-01-13)


### Bug Fixes

* **gnome:** remove distro pipx and install via pip system-wide ([23c6822](https://github.com/hypersec-io/dfe-developer/commit/23c682289df3201656ceacb7994371f075c9c56d))

## [2.14.4](https://github.com/hypersec-io/dfe-developer/compare/v2.14.3...v2.14.4) (2026-01-13)


### Bug Fixes

* **gnome:** upgrade pip and pipx to latest on all distros ([e41e605](https://github.com/hypersec-io/dfe-developer/commit/e41e6050838f195e0e2ef37f1cf25c82a22dbf3d))
* **gnome:** upgrade pip/pipx system-wide with --break-system-packages ([a8ad318](https://github.com/hypersec-io/dfe-developer/commit/a8ad318a2ff5aa29581f323064eeaca840130b0f))
* **gnome:** use --user for pip/pipx upgrade, not --break-system-packages ([7f3dad4](https://github.com/hypersec-io/dfe-developer/commit/7f3dad4153a174ff4afbb05a177d9a570dbc8e50))

## [2.14.3](https://github.com/hypersec-io/dfe-developer/compare/v2.14.2...v2.14.3) (2026-01-13)


### Bug Fixes

* **gnome:** upgrade pipx on Ubuntu before using pipx module ([9779529](https://github.com/hypersec-io/dfe-developer/commit/977952930f18f10b1a850db9d30080f66a1f31c6))

## [2.14.2](https://github.com/hypersec-io/dfe-developer/compare/v2.14.1...v2.14.2) (2026-01-13)


### Bug Fixes

* **utilities:** add apt fallback for Remmina on Ubuntu ([a1d5d5f](https://github.com/hypersec-io/dfe-developer/commit/a1d5d5f915d1baed31b46f0e02f32f10f3f4cfd8))

## [2.14.1](https://github.com/hypersec-io/dfe-developer/compare/v2.14.0...v2.14.1) (2026-01-13)


### Bug Fixes

* **utilities:** make Remmina Flatpak install non-fatal ([74ea5e4](https://github.com/hypersec-io/dfe-developer/commit/74ea5e40236cd2fec3a8d102a09a5860184732e1))

# [2.14.0](https://github.com/hypersec-io/dfe-developer/compare/v2.13.1...v2.14.0) (2026-01-13)


### Features

* modernize Ansible to ansible_facts syntax, auto-upgrade installer ([02a3944](https://github.com/hypersec-io/dfe-developer/commit/02a39443b5a15b9f7e387646044a8b30ef81cd66))

## [2.13.1](https://github.com/hypersec-io/dfe-developer/compare/v2.13.0...v2.13.1) (2026-01-13)


### Bug Fixes

* use | bool filter for Ansible 2.16+ conditional compatibility ([3526004](https://github.com/hypersec-io/dfe-developer/commit/35260047a61bbcaadbead01c49d3d1c391cdfd87))

# [2.13.0](https://github.com/hypersec-io/dfe-developer/compare/v2.12.0...v2.13.0) (2026-01-13)


### Features

* add --force-gnome flag for headless template builds ([a95e6e7](https://github.com/hypersec-io/dfe-developer/commit/a95e6e7c496e50ea0f22063d515568ea5438e912))

# [2.12.0](https://github.com/hypersec-io/dfe-developer/compare/v2.11.9...v2.12.0) (2026-01-06)


### Bug Fixes

* Ensure /usr/local/sbin exists before deploying scripts ([73dd627](https://github.com/hypersec-io/dfe-developer/commit/73dd6278321244f47c919ddd7b699bdbebc970d8))
* Remove unnecessary Chrome/Slack GPU disables ([b93321f](https://github.com/hypersec-io/dfe-developer/commit/b93321fe76ad54dc6470401d308292a0dea97261))


### Features

* Add VA-API auto-detection service for GNOME Remote Desktop ([fd3b636](https://github.com/hypersec-io/dfe-developer/commit/fd3b636115876deac1aa57f543c9a1574f7a34c5))

## [2.11.9](https://github.com/hypersec-io/dfe-developer/compare/v2.11.8...v2.11.9) (2025-12-31)


### Bug Fixes

* Add NetBird CLI to core developer role ([445d3da](https://github.com/hypersec-io/dfe-developer/commit/445d3dae507bd9b0eb2cbcabc6b2573d4975c28d))

## [2.11.8](https://github.com/hypersec-io/dfe-developer/compare/v2.11.7...v2.11.8) (2025-12-31)


### Bug Fixes

* Add Session Manager Plugin and aws-vault for AWS CLI ([9e164aa](https://github.com/hypersec-io/dfe-developer/commit/9e164aabbab70b80776b9b92900157e5db9e1176))

## [2.11.7](https://github.com/hypersec-io/dfe-developer/compare/v2.11.6...v2.11.7) (2025-12-31)


### Bug Fixes

* Add Bitwarden and change Flatpak apps to system-wide installation ([57c7be2](https://github.com/hypersec-io/dfe-developer/commit/57c7be2d17062542e07df32e3da712fc701ff2ad))

## [2.11.6](https://github.com/hypersec-io/dfe-developer/compare/v2.11.5...v2.11.6) (2025-12-28)


### Bug Fixes

* Replace Linear CLI with schpet/linear-cli ([dbf83e0](https://github.com/hypersec-io/dfe-developer/commit/dbf83e022b97406025ee1470bb125f0764f08a3b))

## [2.11.5](https://github.com/hypersec-io/dfe-developer/compare/v2.11.4...v2.11.5) (2025-12-26)


### Bug Fixes

* Disable GNOME animations for RDP performance ([bd82267](https://github.com/hypersec-io/dfe-developer/commit/bd82267551d54dd6e1c18ce7d59e144480674860))

## [2.11.4](https://github.com/hypersec-io/dfe-developer/compare/v2.11.3...v2.11.4) (2025-12-25)


### Bug Fixes

* Replace system-monitor with Astra Monitor extension ([e3a6ff7](https://github.com/hypersec-io/dfe-developer/commit/e3a6ff79e22f4e6e78aa182e8aae172d010b0ff4))

## [2.11.3](https://github.com/hypersec-io/dfe-developer/compare/v2.11.2...v2.11.3) (2025-12-24)


### Bug Fixes

* Add Betterbird, Brave browser, desktop environment setup, and psutil dependency ([0be8287](https://github.com/hypersec-io/dfe-developer/commit/0be82876ae49f2f9b1342765933ce1e7a697bf64))

## [2.11.2](https://github.com/hypersec-io/dfe-developer/compare/v2.11.1...v2.11.2) (2025-12-20)


### Bug Fixes

* Add python3 and pytest as explicit system packages ([d959a1c](https://github.com/hypersec-io/dfe-developer/commit/d959a1c1010a81b2db76b12dc699c320c5442161))

## [2.11.1](https://github.com/hypersec-io/dfe-developer/compare/v2.11.0...v2.11.1) (2025-12-16)


### Bug Fixes

* Use ask instead of deny for sensitive file permissions in Claude Code ([5768dc8](https://github.com/hypersec-io/dfe-developer/commit/5768dc80eee71aa2945be51914cfca339645007d))

# [2.11.0](https://github.com/hypersec-io/dfe-developer/compare/v2.10.0...v2.11.0) (2025-12-16)


### Features

* Add Adwaita Sans and Martel Sans fonts for consistent UI ([80c934a](https://github.com/hypersec-io/dfe-developer/commit/80c934af78737ca47438bed97ee8ea156b7bc059))

# [2.10.0](https://github.com/hypersec-io/dfe-developer/compare/v2.9.0...v2.10.0) (2025-12-16)


### Features

* Add Nemo file manager and Window State Manager extension ([c276738](https://github.com/hypersec-io/dfe-developer/commit/c276738b5f79b6148dfd610d5d335c09daf86bd2))

# [2.9.0](https://github.com/hypersec-io/dfe-developer/compare/v2.8.7...v2.9.0) (2025-12-11)


### Features

* Add Claude Code managed settings for enterprise deployments ([bafd83a](https://github.com/hypersec-io/dfe-developer/commit/bafd83ab806134b56c2a485faef1d9c4716ded57))

## [2.8.7](https://github.com/hypersec-io/dfe-developer/compare/v2.8.6...v2.8.7) (2025-12-10)

### Fully Tested Release

All platforms tested on fresh VMs with zero failures:

| Platform | Tasks | Result |
|----------|-------|--------|
| Fedora 42 | 319 ok, 0 failed | PASS |
| Ubuntu 24.04 | 346 ok, 0 failed | PASS |
| macOS Sequoia | 120 ok, 0 failed | PASS |

### Bug Fixes

* Ghostty theme names updated to Ghostty 1.2.x format (`Builtin Solarized Light/Dark`)
* Ghostty deprecated `gtk-single-instance` option removed (was causing startup hangs)
* Ghostty global keybind disabled (causes issues on GNOME/RDP)
* Linear CLI now installs to user npm-global directory (not system-wide)
* Dash to Panel transparency enabled by default (60% opacity)

### Features

* GNOME extensions installed via gext (extensions.gnome.org) for GNOME 48 compatibility
* winlike/maclike tag exclusivity enforced (maclike overrides if both specified)
* Added `ansible/test.sh` for easier testing

---

## [2.8.6](https://github.com/hypersec-io/dfe-developer/compare/v2.8.5...v2.8.6) (2025-12-10)


### Bug Fixes

* Linear CLI installation uses user npm-global directory ([28d72a6](https://github.com/hypersec-io/dfe-developer/commit/28d72a6c7ba6622e967e73ed898947cd7ad4a417))

## [2.8.5](https://github.com/hypersec-io/dfe-developer/compare/v2.8.4...v2.8.5) (2025-12-10)


### Bug Fixes

* Linear CLI verify path, add test.sh for ansible testing ([74cceee](https://github.com/hypersec-io/dfe-developer/commit/74cceeee259c25c09400913da13eadabe222547e))

## [2.8.4](https://github.com/hypersec-io/dfe-developer/compare/v2.8.3...v2.8.4) (2025-12-10)


### Bug Fixes

* Enforce winlike/maclike exclusivity with ansible_run_tags check ([f1a2c3a](https://github.com/hypersec-io/dfe-developer/commit/f1a2c3a45b599ba4abd65506326131a3c33dc4ce))

## [2.8.3](https://github.com/hypersec-io/dfe-developer/compare/v2.8.2...v2.8.3) (2025-12-10)


### Bug Fixes

* GNOME extensions use gext for all platforms, maclike overrides winlike ([4dbca44](https://github.com/hypersec-io/dfe-developer/commit/4dbca44bde1864dcf2e0fc5e6d398b42bcc37765))

## [2.8.2](https://github.com/hypersec-io/dfe-developer/compare/v2.8.1...v2.8.2) (2025-12-10)


### Bug Fixes

* PATH config, Chrome repo duplicates, apply:tags for all includes ([4b2832f](https://github.com/hypersec-io/dfe-developer/commit/4b2832fa39f90fa681f69ac44312afda4c07b7cd))

## [2.8.1](https://github.com/hypersec-io/dfe-developer/compare/v2.8.0...v2.8.1) (2025-12-10)


### Bug Fixes

* Keep git-core PPA, add apply:tags to git include ([b093445](https://github.com/hypersec-io/dfe-developer/commit/b09344547176e7b2a10bb9a6bd1a5de87511de68))

# [2.8.0](https://github.com/hypersec-io/dfe-developer/compare/v2.7.0...v2.8.0) (2025-12-10)


### Features

* Disable telemetry and advertising for corporate deployments ([0a0c9ff](https://github.com/hypersec-io/dfe-developer/commit/0a0c9ffb7d6fff6893b02f5209f9cd9784e488d5))

# [2.7.0](https://github.com/hypersec-io/dfe-developer/compare/v2.6.0...v2.7.0) (2025-12-10)


### Features

* Disable Ubuntu Pro/ESM advertising messages ([e65d835](https://github.com/hypersec-io/dfe-developer/commit/e65d8350474e8ec8f81a727c664c376578b34036))

# [2.6.0](https://github.com/hypersec-io/dfe-developer/compare/v2.5.8...v2.6.0) (2025-12-10)


### Features

* Refactor to tag-based options, fix GNOME extensions, update Ghostty config ([a117107](https://github.com/hypersec-io/dfe-developer/commit/a1171079832cd80d608976b9427569801dc39bd5))

## [2.5.8](https://github.com/hypersec-io/dfe-developer/compare/v2.5.7...v2.5.8) (2025-12-08)


### Bug Fixes

* Configure Ubuntu Dock as Windows-like taskbar on Ubuntu 24.04 ([3fb65e6](https://github.com/hypersec-io/dfe-developer/commit/3fb65e6355ceb7423a1f39a3d1e3852c685d9277))

## [2.5.7](https://github.com/hypersec-io/dfe-developer/compare/v2.5.6...v2.5.7) (2025-12-05)


### Bug Fixes

* Fix Dash to Panel extension permissions after extraction ([8ec0f27](https://github.com/hypersec-io/dfe-developer/commit/8ec0f2747cefbb3e7be5107c31a3dca0e11796ae))

## [2.5.6](https://github.com/hypersec-io/dfe-developer/compare/v2.5.5...v2.5.6) (2025-12-05)


### Bug Fixes

* Fix Dash to Panel and wallpaper installation on Ubuntu ([8b3432f](https://github.com/hypersec-io/dfe-developer/commit/8b3432f644aa7fafd631a232b4b60312193a3af6))

## [2.5.5](https://github.com/hypersec-io/dfe-developer/compare/v2.5.4...v2.5.5) (2025-12-05)


### Bug Fixes

* Add RDP role, GNOME defaults, package lock protection, and CI workflow ([38f293a](https://github.com/hypersec-io/dfe-developer/commit/38f293ac99b501f606dfc4e0b76df7d3d0dbc3ea))

## [2.5.4](https://github.com/hypersec-io/dfe-developer/compare/v2.5.3...v2.5.4) (2025-11-26)


### Removed

* **[Windows]** Royal TS remote connection manager from Windows SOE
* **[Ansible]** claude-monitor tool from UV installation

## [2.5.3](https://github.com/hypersec-io/dfe-developer/compare/v2.5.2...v2.5.3) (2025-11-25)


### Removed

* **[Ansible]** MCP Toolbox (GenAI Toolbox) from core role

## [2.5.2](https://github.com/hypersec-io/dfe-developer/compare/v2.5.1...v2.5.2) (2025-11-23)


### Bug Fixes

* Add act (GitHub Actions runner) to core role ([905894e](https://github.com/hypersec-io/dfe-developer/commit/905894e543fb8581e64a6c699c0068d64a1af187))
* Use direct binary download for act on Ubuntu instead of curl-bash ([e523fd6](https://github.com/hypersec-io/dfe-developer/commit/e523fd638b2ef4ced8d0bf33dc7e43a986f2ba8e))

## [2.5.1](https://github.com/hypersec-io/dfe-developer/compare/v2.5.0...v2.5.1) (2025-11-16)


### Bug Fixes

* Add GenAI Toolbox (MCP Toolbox) to core role ([c6cc07b](https://github.com/hypersec-io/dfe-developer/commit/c6cc07b058aa3508bef603b13fd804e3b0a32747))
* Add GNU Parallel to utilities and remove duplicate when condition ([08dc54c](https://github.com/hypersec-io/dfe-developer/commit/08dc54cd3b21ac66ddfbd1da8b19e97a2be1f07e))
* Add tokenx to global npm packages in core role ([0b7fe54](https://github.com/hypersec-io/dfe-developer/commit/0b7fe5442bc0e738e15c85b40564f4b581d35dcd))
* Configure GitHub linguist to detect Ansible as primary language ([c2455f0](https://github.com/hypersec-io/dfe-developer/commit/c2455f09a4752189392e39725feb7ec8c315e91b))
* Correct MCP Toolbox verification command and remove duplicate register ([87fc6b6](https://github.com/hypersec-io/dfe-developer/commit/87fc6b6d583ca384366341d4aa2dfeb3b1705d84))


### Reverts

* Revert "fix: Add tokenx to global npm packages in core role" ([2ac0f60](https://github.com/hypersec-io/dfe-developer/commit/2ac0f6026895dee2c951af77ac7790cf2fb2cd69))

# [2.5.0](https://github.com/hypersec-io/dfe-developer/compare/v2.4.4...v2.5.0) (2025-11-10)


### Features

* Add semantic-release automation for version management ([3bd6478](https://github.com/hypersec-io/dfe-developer/commit/3bd64784ec50901b359c5f3a76ca0a4b197cd6b4))

## [2.4.4] - 2025-11-05

### Added
- **[Core]** Gitleaks v8.29.0 secret detection tool for finding hardcoded credentials

### Removed
- **[Cleanup]** Removed redundant /claude directory (duplicate of tools/git/)

## [2.4.3] - 2025-11-05

### Fixed
- **[Ansible]** Ubuntu Vector GPG keys - Changed from RPM keys to APT keys (DATADOG_APT_KEY_*)
- **[Ansible]** Ubuntu VS Code repository conflicts - Added cleanup of pre-existing repos
- **[Ansible]** Missing verify.yml reference - Removed dead playbook reference
- **[Ansible]** QEMU guest agent verification - Accept 'static' UnitFileState on Ubuntu

### Changed
- **[Testing]** All platforms tested on fresh VMs (Ubuntu 24.04: 275 tasks/0 failed, Fedora 42: 257 tasks/0 failed)
- **[macOS]** Complete macOS Sequoia 15.3.1 support verified (120 tasks, 0 failures)

## [2.4.2] - 2025-10-31

### Fixed
- **[Ansible]** git-subtree not available as separate package on Ubuntu (included in git)
- **[Ansible]** Ghostty uses dynamic Ubuntu version (ansible_distribution_version)
- **[Ansible]** kubectl moved to k8s.yml with dynamic K8s version detection
- **[Ansible]** Added HashiCorp repository for Fedora (Terraform/Vault not in default repos)
- **[Ansible]** Ghostty Ubuntu uses pre-built .deb from mkasberg/ghostty-ubuntu

### Changed
- **[Ansible]** Dynamic Kubernetes version from https://dl.k8s.io/release/stable.txt
- **[Ansible]** Both Ubuntu and Fedora fully working (0 failures on both)

## [2.4.1] - 2025-10-31

### Added
- **[Ansible]** Complete dfe_developer role with Docker, Python (UV), Git, Cloud tools, K8s tools, Utilities
- **[Ansible]** Mirror validation before system modification
- **[Ansible]** GNOME detection in pre_tasks as dfe_has_gnome fact
- **[Ansible]** Repository backups before modification
- **[Ansible]** git-core PPA for latest Git on Ubuntu

### Changed
- **[Ansible]** Simplified Python to UV only (no pyenv/pipx)
- **[Ansible]** Task ordering: repository → utilities → Docker → Python → Git → cloud → k8s
- **[Ansible]** Renamed dfe_use_aarnet_mirrors → dfe_use_mirrors
- **[Ansible]** Consolidated Docker into single task file
- **[Ansible]** Ghostty skipped on Ubuntu (PPA doesn't support noble)
- **[Ansible]** Each task file adds its own vendor repositories

### Fixed
- **[Ansible]** Ubuntu 24.04 fully working (78 tasks, 0 failures, fully tested)
- **[Ansible]** Correct Ubuntu mirror path (/ubuntu/archive/)
- **[Ansible]** Podman removal ignores errors if not installed

## [2.4.0] - 2025-10-31

### Added
- **[Ansible]** Ansible-based deployment system for cross-platform support
- **[Ansible]** install.sh bootstrap script for Ubuntu, Fedora, and macOS
- **[Ansible]** Role-based architecture (4 roles matching bash scripts)
- **[Ansible]** dfe_developer role (Docker installation working on Ubuntu + Fedora)
- **[Ansible]** Task-based organization with distro conditionals inside tasks
- **[Ansible]** Complete role structure for all components (stubs created)
- **[Ansible]** Ansible 12+ compatibility with modern callback plugins
- **[Ansible]** Tested successfully on Ubuntu 24.04 and Fedora 42

### Changed
- **[Project]** Multi-platform support via Ansible (Ubuntu, Fedora, macOS)
- **[Project]** Declarative infrastructure-as-code approach
- **[Project]** Idempotent deployments (safe to re-run)

## [2.3.4] - 2025-10-31

### Fixed
- **[Fedora]** RDP optimizer now auto-generates system certificates for gnome-remote-desktop
- **[Fedora]** Certificates properly configured via grdctl for Remote Login mode
- **[Fedora]** Desktop now auto-resizes to match RDP client window size
- **[Fedora]** Certificate ownership and permissions set correctly for gnome-remote-desktop user

### Added
- **[Fedora]** Interactive password prompt for RDP credentials during installation
- **[Fedora]** --password and --username flags for automated/scripted deployments
- **[Fedora]** Automatic service restart after credential configuration
- **[Fedora]** Ready-to-use RDP setup (no manual credential configuration needed)

## [2.3.2] - 2025-10-30

### Added
- **[Fedora]** RDP optimizer now automatically enables gnome-remote-desktop.service

### Changed
- **[Fedora]** Removed renderer auto-detection from Ghostty config (not needed)
- **[Fedora]** Simplified Ghostty configuration by removing RDP session detection
- **[Fedora]** Cleaner config template with Solarized Dark as default

## [2.3.1] - 2025-10-30

### Changed
- **[Fedora]** Updated Ghostty configuration to Solarized Dark theme
- **[Fedora]** Enabled programming ligatures (calt, liga) instead of disabling them
- **[Fedora]** Reduced font size from 12 to 11 for better high-DPI displays
- **[Fedora]** Added window dimensions (35x140) for practical terminal size
- **[Fedora]** Disabled VSync for better RDP performance
- **[Fedora]** Added useful keybindings (copy/paste, tabs, font sizing)
- **[Fedora]** RDP-optimized settings (software renderer for remote sessions)

## [2.3.0] - 2025-10-30

### Fixed
- **[Fedora]** Fixed all systemctl enable/disable/daemon-reload commands to use sudo
- **[Fedora]** Fixed GRUB configuration operations to use sudo
- **[Fedora]** Fixed /sys/ filesystem writes to use sudo tee
- **[Fedora]** Fixed NetworkManager configuration writes to use sudo
- **[Fedora]** All scripts now run without PolicyKit authentication prompts

### Removed
- **[Fedora]** Removed file logging from VM optimizer (console only, use tee for logs)

## [2.2.9] - 2025-10-30

### Fixed
- **[Fedora]** Added complete verification function library to lib.sh (verify_sysctl_setting, verify_command_exists, etc.)
- **[Fedora]** Fixed VM and RDP optimizer scripts to use sudo properly for system file operations
- **[Fedora]** Fixed apply_system_dconf function to use sudo for /etc/dconf/ operations
- **[Fedora]** All optimizer scripts now work as regular user with passwordless sudo

### Removed
- **[Project]** Removed windows/VERSION file (using root VERSION only for unified versioning)

## [2.2.8] - 2025-10-30

### Fixed
- **[Fedora]** Fixed journald configuration in install-vm-optimizer.sh to use sudo
- **[Fedora]** Added missing verification helper function stubs

## [2.2.7] - 2025-10-30

### Fixed
- **[Fedora]** Minikube installation now idempotent (skips if already installed)
- **[Fedora]** Minikube downloads to /tmp with proper pushd/popd for directory changes
- **[Fedora]** Fixed ShellCheck warnings for directory navigation

## [2.2.6] - 2025-10-30

### Added
- **[Fedora]** Ghostty terminal emulator now installed via scottames/ghostty COPR repository
- **[Fedora]** Ghostty integrated into main install-dfe-developer.sh script
- **[Fedora]** Automatic Ghostty configuration with JetBrains Mono font

### Fixed
- **[Fedora]** Fixed missing BACKUP_DIR and STATE_FILE variables in install-rdp-optimizer.sh
- **[Fedora]** Added missing helper functions: dconf_update_safe, create_sysctl_config, reload_service_safe

### Removed
- **[Fedora]** Removed install-ghostty.sh (now integrated into main installer)
- **[Fedora]** Removed build-from-source option for Ghostty (now uses COPR)

## [2.2.5] - 2025-10-30

### Fixed
- **[Fedora]** Suppressed Flatpak progress bars during installation (Freelens, Slack, Ghostty)
- **[Fedora]** Uses FLATPAK_TTY_PROGRESS=0 and grep filtering to remove multi-line progress output
- **[Fedora]** Cleaner installation output while preserving status messages

## [2.2.4] - 2025-10-30

### Fixed
- **[Fedora]** Added is_gnome() function to lib.sh for reliable GNOME detection
- **[Fedora]** Fixed missing HAS_GNOME initialization in all installer scripts
- **[Fedora]** GNOME detection now uses XDG_CURRENT_DESKTOP, GDMSESSION, and gnome-shell process check
- **[Fedora]** Fixes GUI tools (Firefox, VS Code, extensions) not installing when GNOME is present

## [2.2.3] - 2025-10-30

### Fixed
- **[Fedora]** Removed unnecessary systemd-journald service restarts from install-vm-optimizer.sh
- **[Fedora]** Services no longer restarted during installation (reboot required anyway)

## [2.2.2] - 2025-10-30

### Fixed
- **[Fedora]** Removed automatic call to install-dfe-developer-core.sh from install-dfe-developer.sh
- **[Fedora]** Prevents duplicate installation when using install-all.sh
- **[Fedora]** Scripts now properly modular (use install-all.sh for complete setup)

## [2.2.1] - 2025-10-30

### Fixed
- **[Fedora]** Fixed Claude Code CLI verification to not halt script execution
- **[Fedora]** Removed pyright verification check (no longer installed)
- **[Fedora]** Removed Yeoman (yo) verification check (no longer installed)

## [2.2.0] - 2025-10-30

### Added
- **[Fedora]** Linear.app CLI tool (@digitalstories/linear-cli) to core developer tools
- **[Fedora]** fedora/QUICKSTART.md for fast-start installation guide
- **[Windows]** Windows 11 SOE setup scripts integrated into repository
- **[Windows]** Built-in debloat with comprehensive telemetry and bloatware removal
- **[Windows]** Default Switch automatic scheduled task for new Hyper-V VMs
- **[Windows]** Development workflow documentation (Windows for productivity, Linux VMs for development)
- **[Claude]** Enhanced claude-contrib-fix.sh with optional branch parameter
- **[Claude]** Script now supports cleaning non-default branches without GitHub reindex
- **[Claude]** gh CLI dependency now optional (only required for default branch operations)

### Changed
- **[Windows]** Renamed script: `hypersec-windows-soe.ps1` → `hypersec-windows.ps1`
- **[Windows]** Switched from VMware to Microsoft Hyper-V as primary virtualization platform
- **[Windows]** Security first: Full VBS, Credential Guard, HVCI enabled by default
- **[Windows]** Simplified log files to `%USERPROFILE%\basename.log`
- **[Project]** Unified versioning across Fedora and Windows platforms (single CHANGELOG)
- **[Project]** Removed duplicate LICENSE files from subdirectories (all reference root LICENSE)
- **[Project]** Merged Windows README into root README for centralized documentation

### Deprecated
- **[Windows]** `hypersec-windows-vmware.ps1` retained but no longer maintained (security trade-offs)

### Fixed
- **[Windows]** PowerShell syntax error in scheduled task trigger creation
- **[Windows]** Log file location and naming consistency
- **[Claude]** Improved default branch auto-detection (git symbolic-ref, fallback to gh CLI)

## [2.1.3] - 2025-10-27

### Removed
- **[Fedora]** Removed yo (Yeoman) from npm global installations
- **[Fedora]** Removed pyright from npm global installations

## [2.1.2] - 2025-10-24

### Fixed
- **[Fedora]** Dynamic version detection for Confluent CLI (uses latest from packages.confluent.io)
- **[Fedora]** Dynamic version detection for kubectl (uses latest stable from dl.k8s.io)
- **[Fedora]** Replaced cd with pushd/popd in AWS CLI installation for safer directory changes
- **[Fedora]** Updated unit tests to match ISO timestamp format in print functions
- **[Fedora]** ShellCheck warnings resolved (all tests pass)

### Changed
- **[Fedora]** Character policy updated to ASCII-only (no emojis)
- **[Fedora]** Standardized script headers across all optimizer scripts
- **[Fedora]** All documentation updated to reflect ASCII-only policy

### Added
- **[Fedora]** Comprehensive CONTRIBUTING.md with Apache project standards
- **[Fedora]** Full contribution guidelines including fork/PR workflow
- **[Fedora]** Code standards and testing requirements documentation

## [2.1.1] - 2025-10-24

### Added
- **[Fedora]** Helm Dashboard plugin installation for visual Helm chart management
- **[Fedora]** Freelens Kubernetes IDE via Flatpak for K8s cluster management
- **[Fedora]** Dash-to-panel transparency settings (40% opacity)
- **[Fedora]** K9s and Freelens verification checks in installation output

### Changed
- **[Fedora]** Removed specific version numbers from README.md (centralized in VERSION file)
- **[Fedora]** Updated documentation to reflect new Kubernetes tools

## [2.1.0] - 2025-10-20

### Added
- **[Fedora]** Slack installation via Flatpak in install-dfe-developer-core.sh
- **[Fedora]** Automatic flathub remote configuration for user-level Flatpak installations
- **[Fedora]** Robust error handling for optional Flatpak installations
- **[Windows]** Enhanced Australian English locale configuration
- **[Windows]** Default Switch automatic network assignment for new Hyper-V VMs
- **[Windows]** C:\VM structure with automatic directory creation
- **[Windows]** Scheduled task for automatic Default Switch enforcement

### Fixed
- **[Fedora]** Claude Code CLI command (changed from `claude-code` to `claude`)
- **[Fedora]** Claude Code auto-update configuration now uses correct command
- **[Fedora]** Flatpak installations now use `--user` flag for proper permissions

### Changed
- **[Fedora]** Removed all SUDO_USER references from scripts (~50+ lines of code simplified)
- **[Fedora]** Scripts now use $HOME and $USER directly instead of complex SUDO_USER logic
- **[Fedora]** Simplified UV installation (removed SUDO_USER branching)
- **[Fedora]** Simplified VM optimizer GUI configurations
- **[Fedora]** All user-specific paths now use $HOME instead of /home/$SUDO_USER/
- **[Windows]** Improved Hyper-V configuration with registry and PowerShell module detection
- **[Windows]** Better handling of Hyper-V default paths (Set-VMHost with registry fallback)

### Improved
- **[Fedora]** Code maintainability with single execution path instead of root/user branching
- **[Fedora]** Consistency with "run as user, sudo only when needed" design principle

## [2.0.3] - 2025-09-23

### Changed
- **[Windows]** Updated Chocolatey packages to current versions
- **[Windows]** RoyalTS fixed to use `royalts-v7-x64` for latest v7 installation
- **[Windows]** GitHub Desktop added with `--NoDesktopShortcut` parameter
- **[Windows]** TigerVNC reverted to working `tigervnc` package name
- **[Windows]** Browser configuration updated to Windows 11-compatible manual method only

### Added
- **[Windows]** WinMerge as development tool
- **[Windows]** GitHub Desktop (replaced SourceTree)

### Removed
- **[Windows]** SetUserFTA dependencies and file association automation removed
- **[Windows]** Teams from bloatware cleanup (now properly installed with M365)
- **[Windows]** SourceTree (replaced with GitHub Desktop)

## [2.0.2] - 2025-08-27

### Changed
- **[Windows]** Windows 11 24H2 compatibility improvements
- **[Windows]** Updated package versions for Windows 11 24H2
- **[Windows]** Improved error handling for Windows 11 security restrictions

## [2.0.1] - 2025-07-22

### Added
- **[Windows]** Enhanced privacy hardening with built-in telemetry disabling
- **[Windows]** Improved bloatware removal automation
- **[Windows]** Better service cleanup and startup program management

### Changed
- **[Windows]** Refined Australian English locale configuration
- **[Windows]** Improved power management detection for laptop vs desktop

## [2.0.0] - 2025-10-19

### Ported
- **[Fedora]** Ported from internal HyperSec SOE build
- **[Windows]** Migrated from internal HyperSec repository to public GitHub

### Changed
- **[Fedora]** Complete rewrite
- **[Fedora]** Removed all verify, uninstall, and check functions
- **[Fedora]** Consolidated library functions into single lib.sh file
- **[Fedora]** Simplified all installation scripts by 85%
- **[Fedora]** Removed numbered steps from console output and comments
- **[Windows]** Restructured for public consumption and broader compatibility
- **[Windows]** Improved installation workflow and user experience
- **[Windows]** Better error handling and logging throughout

### Added
- **[Fedora]** BATS testing framework for unit and integration tests
- **[Fedora]** Container tests with Podman/Docker support
- **[Fedora]** developer_sudoers function for passwordless sudo setup
- **[Fedora]** Git pre-push hook for automatic version tagging
- **[Windows]** Complete rewrite with modular architecture
- **[Windows]** VMware Workstation optimization and automation
- **[Windows]** Enhanced privacy hardening with comprehensive telemetry disabling
- **[Windows]** Australian English configuration (locale, timezone, regional settings)
- **[Windows]** System restore point management
- **[Windows]** Automated software installation via Chocolatey
- **[Windows]** Custom wallpaper support
- **[Windows]** Windows Defender ATP onboarding support
- **[Windows]** Comprehensive documentation (README, QUICKSTART, VMWARE guides)

### Fixed
- **[Fedora]** All ShellCheck warnings (SC2155, SC2046, SC2034)
- **[Fedora]** Container test SELinux context issues
- **[Fedora]** Script executable permissions

### Removed
- **[Fedora]** Complex mode selection logic
- **[Fedora]** Verification and uninstallation functions
- **[Fedora]** Over-engineered error handling

### Note
- **[Fedora]** First public release after internal development at HyperSec
- **[Windows]** First public release after internal development at HyperSec
- Previous versions (1.x) were internal-only for both platforms
