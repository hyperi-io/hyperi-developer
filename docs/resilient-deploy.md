# Resilient deploy: warn and carry on, never silently

This deployment is **best-effort, not all-or-nothing**.

It is not routinely maintained, and it depends on a long tail of upstreams that
rename their release assets, move their repos, change their GPG keys, or simply
go away. A single dead upstream must not abort the whole run and leave a
developer with half a machine and a stack trace.

So optional things that fail are recorded and skipped, and the run continues.

## The other half of the bargain

"Carry on and warn" is only acceptable if the warning is **unmissable**.

Without that, this is just a silent half-install -- which is *worse* than
failing, because the box looks finished. Someone reaches for a tool three weeks
later and it is not there, and nothing anywhere says why.

So every optional failure lands in a loud summary at the end of the run
(`playbooks/main.yml`, post_tasks). If you add an optional install, it must
report through that summary. A `failed_when: false` on its own is not the
pattern -- it hides the reason.

## Tiers: what fails the run, and what does not

**CRITICAL -- still fails fast.** A box without these is not a developer box,
and continuing would produce something broken that pretends to work:

- unsupported OS or version (the gate in `developer/tasks/init.yml`)
- the package manager itself being broken or permanently locked
- git
- the docker engine

**OPTIONAL -- warn and continue.** Individually useful, collectively not worth
aborting for:

- individual CLI tools and GUI apps
- third-party repos, PPAs, COPRs
- Flathub / snap
- binaries fetched from GitHub releases (the most fragile class by far --
  upstream renames assets without warning)

## The pattern

```yaml
- name: Install <thing>
  block:
    - name: Fetch <thing>
      ansible.builtin.get_url:
        url: "..."
        dest: /tmp/thing
        mode: '0755'

    - name: Install <thing>
      ansible.builtin.copy:
        src: /tmp/thing
        dest: /usr/local/bin/thing
        remote_src: true
        mode: '0755'

  rescue:
    # Record it, so the summary can report it. Keep the reason: a warning that
    # does not say WHY is barely better than silence.
    - name: Record that <thing> did not install
      ansible.builtin.set_fact:
        deploy_warnings: >-
          {{ deploy_warnings | default([])
             + ['<thing>: ' ~ (ansible_failed_result.msg | default('unknown error'))] }}

  when: <the usual platform guards>
```

### Why `block`/`rescue` and not `ignore_errors: true`

`ignore_errors` swallows the reason. You get a red line in the output, the run
carries on, and nothing is recorded -- so the summary cannot mention it and
nobody finds out. ansible-lint flags it (`ignore-errors`) for the same reason.

`rescue` catches the failure AND gives you `ansible_failed_result`, so the
summary can say what broke and why.

### Why not `failed_when: false`

Same problem, plus it marks the task green. A task that failed and reports `ok`
is a lie in the output.

There are two legitimate uses of `failed_when: false` in this repo, both for
*probes* rather than installs: asking whether something exists (`dpkg-query`,
`stat`, `command -v`) where "no" is a normal answer, not a failure. That is
fine. Using it to paper over an install is not.

## Testing it

`molecule -s matrix` exercises a clean install per distro. To prove the
warn-and-continue path itself, point an optional install at a URL that 404s and
confirm:

1. the run completes
2. the summary names the thing that failed, and why
3. everything after it still installed

A resilient deploy that has never been tested against a dead upstream is a
hypothesis.
