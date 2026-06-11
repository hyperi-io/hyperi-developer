# URL + Version Audit — Findings

**Date:** 2026-04-18
**Source:** `tests/audit/urls_and_pins.py` run against `feat/role-structure-refactor`
**Total CSV hits:** 175 (data rows; 176 including header) from `wc -l /tmp/audit.csv`

## Methodology

For each hit: evaluated (a) is the URL still reachable, (b) is any version pin
justified, (c) has the upstream drifted? Bucketed per the spec's tri-state
findings model (fix-now / Track-2 / defer).

Roughly 60 % of hits are not external URLs at all — they are `dconf` `key:`
paths, `src:` file references inside roles, and GPG `gpgkey: |` multiline
markers. The Python regex `(url|baseurl|gpgkey|key|src):` matches the YAML
key name rather than a URL, so those lines are noise and were skipped.
Real external endpoints total roughly 55; of those, ~26 were spot-checked
with `curl -sSL --max-time 3` (or `curl -I` plus a GET fallback on repo
listings, which legitimately 404 on HEAD but serve `/repodata/repomd.xml`
correctly).

Known intentional pins (not flagged):
- `grd_patched_version: 49.0-0ubuntu1.1hyperi1` — we own the GRD patch
- `freerdp_pin_version: 3.16.0+dfsg-2ubuntu0.4` — pinning past known-broken
  `ubuntu0.3` per the role's inline comment
- HashiCorp Ubuntu release fallback `>24.04 → noble` in `iac/tasks/hashicorp.yml`
  — deliberate (HashiCorp only publishes LTS codenames)
- `min_fedora_version: 42`, `min_ubuntu_version: "24.04"`,
  `min_ansible_version: "2.20"` — gate checks surfaced in `init.yml`, not pins
- `default('8.1')` fallback for `confluent_version` in `data_tools.yml` — last
  resort only; the primary path scrapes the live directory index

Reachability summary (live URLs, HEAD or GET with redirect follow):

| URL | Status |
| --- | --- |
| api.github.com (act, aws-vault, bitwarden, chmln/sd, dive, gitleaks, ghostty-ubuntu, helm, k9s, kubectx, argocd, lazygit, linear-cli, uv, yq) | 200 |
| awscli.amazonaws.com | 200 |
| apt.releases.hashicorp.com/gpg, rpm.releases.hashicorp.com/gpg | 200 |
| dl.google.com/linux/linux_signing_key.pub | 200 |
| packages.cloud.google.com/apt/doc/apt-key.gpg | 200 |
| packages.microsoft.com (keys, yumrepos/azure-cli, yumrepos/vscode, repos/code) | 200 / 301 |
| packages.openvpn.net/packages-repo.gpg | 200 |
| packages.clickhouse.com/rpm/stable/ | 200 |
| packages.confluent.io/rpm/, /deb/ | 200 |
| download.onlyoffice.com/GPG-KEY-ONLYOFFICE | 200 |
| dbeaver.io/debs/dbeaver.gpg.key | 200 |
| dl.k8s.io/release/stable.txt | 200 |
| releases.jfrog.io/artifactory/jfrog-rpms | 302 (redirect, OK) |
| desktop.docker.com/linux/main/amd64/docker-desktop-amd64.deb | 200 |
| storage.googleapis.com/claude-code-dist-.../latest | 200 |
| brave-browser-rpm-release.s3.brave.com/x86_64/ | 404 on listing, 200 on `repodata/repomd.xml` (expected) |
| dl.google.com/linux/chrome/rpm/stable/x86_64 | 404 on listing, 200 on `repodata/repomd.xml` (expected) |
| packages.cloud.google.com/yum/repos/cloud-sdk-el9-x86_64 | 404 on listing, 200 on `repodata/repomd.xml` (expected) |
| yum.vector.dev/stable/vector-0/ | 404 on listing, 200 on `x86_64/repodata/repomd.xml` (expected) |
| **www.usebruno.com/gpg-key.asc** | **404 — GPG key URL is dead** |
| **usebruno.jfrog.io/artifactory/bruno-apt** | **302 → "reactivate server" page — JFrog repo is decommissioned** |

(Launchpad — `ppa:grzegorz-gutowski/openvpn3-indicator` and `ppa:git-core/ppa` —
was unreachable from this host due to network egress, not verified rot. Both
PPAs are standard and are expected to work in a normal environment.)

## Fix-now (applied in this chunk)

None so far. Bruno's dead endpoints are real rot but the fix is not trivial:
the project appears to have retired its self-hosted APT repo entirely and
moved to a different distribution channel, so correctly replacing the GPG
URL + repo URL requires upstream research. Listed in "Defer" below.

## Flag for Track 2 (Ubuntu 26.04 + DRAGONFLY follow-up)

- `iac/tasks/hashicorp.yml:21-23` — the `>24.04 → noble` fallback will need a
  `plucky`/`oracular` branch once HashiCorp ships 26.04 repos. Track alongside
  the rest of the 26.04 migration.
- `iac/tasks/hashicorp.yml:44` — `baseurl: https://rpm.releases.hashicorp.com/fedora/$releasever/$basearch/stable`
  will need verification when Fedora 43/44 ships and DNF populates `$releasever`
  accordingly.
- `iac/meta/main.yml` — `platforms.Ubuntu: versions: ['noble']` currently
  excludes 26.04; flip when the refactor targets 26.04.
- `developer/tasks/gcloud.yml:15` — `baseurl: cloud-sdk-el9-x86_64` is pinned
  to EL9. When Fedora's derived `$releasever` stops mapping cleanly (e.g.
  Fedora 43+ vs RHEL 10), reassess the mapping.
- `developer/tasks/data_tools.yml:14` — `baseurl: yum.vector.dev/stable/vector-0/$basearch/`
  hits the same concern; verify on Fedora 43.

## Defer (needs real investigation)

- `gui_extras/tasks/bruno.yml:8,14` — the Bruno GPG key at
  `https://www.usebruno.com/gpg-key.asc` returns 404 and
  `https://usebruno.jfrog.io/artifactory/bruno-apt` redirects to
  `landing.jfrog.com/reactivate-server/usebruno` (the JFrog tenant is
  decommissioned). Upstream has migrated off self-hosted APT; need to confirm
  the supported install channel (likely AppImage, Snap, or Flatpak mirror)
  before rewriting this task. Not a Chunk-4a fix. Track in TODO.md.
- Launchpad PPAs (`ppa:grzegorz-gutowski/openvpn3-indicator`,
  `ppa:git-core/ppa`) — reachability not verified from this audit host (network
  egress blocked). Re-check during VM smoke tests (Task 4b).
- `developer/tasks/claude.yml:17` — hardcoded GCS bucket
  `claude-code-dist-86c565f3-...`. Currently 200, but if Anthropic rotates
  the bucket, this breaks silently. Consider Track 2 work to switch to a
  release-metadata indirection (e.g. npm registry) rather than baking in a
  GCS bucket ID.
- `developer/tasks/claude.yml:169,178` — `src: managed-settings.json` and
  duplicate — confirm there is no stale second path during VM smoke tests.

## VM smoke test results

**Deferred — user parked the VM run.** Track 4b status in TODO.md;
smoke-test script is at `tests/assertions/oss_safe.sh` (see Task 4a-3).

Re-enable checklist when ready:
- [ ] clone Ubuntu 24.04 template VM (devex or equivalent)
- [ ] run `./ansible/test.sh --profile developer` against the clone
- [ ] run `tests/assertions/oss_safe.sh` on the VM — expect PASS
- [ ] roll back, run `./ansible/test.sh --profile core,all`
- [ ] record results here
