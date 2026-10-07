#!/usr/bin/env bash
#
# Docker test for hyperi-update across the supported Linux matrix.
#
# WHY THIS EXISTS: hyperi-update was Ubuntu-only for months and nobody noticed,
# because "it installed fine" -- the ansible task simply skipped Fedora. The
# whole auto-update strategy rests on this script, so it gets a real test on a
# real distro, not a syntax check.
#
# WHAT IT PROVES, per distro:
#   1. the script parses under that distro's bash
#   2. --help works and exits 0
#   3. an unknown option is rejected with exit 2
#   4. the confirmation pause EXISTS and declining does nothing (exit 0)
#   5. --yes SKIPS the confirmation and actually reaches the package manager
#   6. it picks the RIGHT package manager for the distro
#   7. the reboot check runs and reports (the Fedora path was silently broken:
#      /run/reboot-required never exists there, so it always said "no reboot")
#   8. a bad release age is refused from the flag and falls back from config
#   9. /etc/default/hyperi-update is read, and with no GitHub release old
#      enough a release binary is kept as it was
#
# WHAT IT CANNOT PROVE: containers share the host kernel, so "reboot required"
# cannot be forced. We assert the check RUNS and reports, not its verdict.
#
# Usage:  ansible/tests/update/test-hyperi-update.sh [image ...]
#         defaults to the n/n-1 matrix.

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"
TARGET="$REPO_ROOT/ansible/roles/developer/files/update/hyperi-update-linux.sh"

# n and n-1. ansible/molecule/vars.yml is the SSoT; tools/check_release_matrix.py
# fails the test run when this list drifts from it.
DEFAULT_IMAGES=(
    "ubuntu:26.04"
    "ubuntu:24.04"
    "fedora:44"
    "fedora:43"
)

IMAGES=("$@")
[[ ${#IMAGES[@]} -eq 0 ]] && IMAGES=("${DEFAULT_IMAGES[@]}")

[[ -f "$TARGET" ]] || { echo "ERROR: $TARGET not found" >&2; exit 1; }

PASS=0
FAIL=0
FAILED_CASES=()

report() {
    local status="$1" image="$2" name="$3"
    if [[ "$status" == "pass" ]]; then
        printf '    ok   %s\n' "$name"
        PASS=$((PASS + 1))
    else
        printf '    FAIL %s\n' "$name"
        FAIL=$((FAIL + 1))
        FAILED_CASES+=("$image: $name")
    fi
}

# The container has no sudo and no tty, but we are already root. Stub sudo so
# the script's calls work.
#
# A naive `exec "$@"` stub is NOT enough and fails confusingly: `sudo -v`
# becomes `exec -v` ("invalid option", rc=2), the script reads that as failed
# authentication and aborts -- which looks exactly like a broken script. The
# stub has to consume sudo's own flags first:
#   -v  validate/refresh the timestamp -> success, run nothing
#   -n  non-interactive (used by the keepalive loop) -> just drop the flag
# shellcheck disable=SC2016  # single quotes are deliberate: this is a literal
# script for the CONTAINER, so $#/$1 must reach it unexpanded, not be
# substituted by the host shell here.
IN_CONTAINER_PRELUDE='
set -e
cat > /usr/local/bin/sudo <<"SUDO_STUB_EOF"
#!/bin/sh
while [ $# -gt 0 ]; do
  case "$1" in
    -v) exit 0 ;;
    -n|-E|-H) shift ;;
    --) shift; break ;;
    -*) shift ;;
    *)  break ;;
  esac
done
[ $# -eq 0 ] && exit 0
exec "$@"
SUDO_STUB_EOF
chmod +x /usr/local/bin/sudo
set +e
'

# run_case <image> <name> <script> <expect_rc> [expect_grep] [expect_absent]
#
# expect_absent is a plain ERE that must NOT appear. Kept as a separate
# parameter rather than a clever negative pattern: grep -E has no negative
# lookahead, and `(?!...)` silently degrades to something that matches
# everything -- i.e. a test that always passes. Ask grep the positive question
# and invert the answer here.
run_case() {
    local image="$1" name="$2" script="$3" expect_rc="$4"
    local expect_grep="${5:-}" expect_absent="${6:-}"
    local out rc
    out=$(docker run --rm -i "$image" bash -s <<EOF 2>&1
$IN_CONTAINER_PRELUDE
cat > /tmp/hyperi-update <<'HYPERI_UPDATE_EOF'
$(cat "$TARGET")
HYPERI_UPDATE_EOF
chmod +x /tmp/hyperi-update
$script
EOF
)
    rc=$?

    if [[ "$rc" != "$expect_rc" ]]; then
        report fail "$image" "$name (rc=$rc, wanted $expect_rc)"
        return
    fi
    if [[ -n "$expect_grep" ]] && ! grep -qE "$expect_grep" <<<"$out"; then
        report fail "$image" "$name (output missing /$expect_grep/)"
        return
    fi
    if [[ -n "$expect_absent" ]] && grep -qE "$expect_absent" <<<"$out"; then
        report fail "$image" "$name (output unexpectedly contains /$expect_absent/)"
        return
    fi
    report pass "$image" "$name"
}

for image in "${IMAGES[@]}"; do
    printf '\n==> %s\n' "$image"

    case "$image" in
        fedora:*) want_mgr="DNF" ; other_mgr="APT" ;;
        *)        want_mgr="APT" ; other_mgr="DNF" ;;
    esac

    # 1. parses under this distro's bash
    run_case "$image" "parses" 'bash -n /tmp/hyperi-update' 0

    # 2. --help
    run_case "$image" "--help exits 0" '/tmp/hyperi-update --help' 0 'hyperi-update'

    # 3. unknown option rejected
    run_case "$image" "unknown option exits 2" '/tmp/hyperi-update --bogus' 2

    # 3a. a --min-age that is not a whole number of days is refused before
    #     anything runs, while a bad configured age only warns and falls back,
    #     so it cannot stop the weekly timer
    run_case "$image" "--min-age without a value exits 2" '/tmp/hyperi-update --min-age' 2
    run_case "$image" "--min-age with a non-number exits 2" '/tmp/hyperi-update --min-age soon' 2
    run_case "$image" "a non-number release age in the env falls back to 7" \
        'printf "n\n" | HYPERI_RELEASE_MIN_AGE_DAYS=-1 /tmp/hyperi-update' 0 'falling back to 7'

    # 4. the confirmation exists, and declining does nothing.
    #    "n" on stdin must stop it BEFORE sudo/packages.
    run_case "$image" "confirm: declining does nothing" \
        'printf "n\n" | /tmp/hyperi-update' 0 'Nothing done'

    # 5. the confirmation names the right package manager
    run_case "$image" "confirm names $want_mgr" \
        'printf "n\n" | /tmp/hyperi-update' 0 "$(tr '[:upper:]' '[:lower:]' <<<"$want_mgr")"

    # 6. --yes skips the confirmation and reaches the package manager section.
    #    This is the real test: on Fedora the old script had no dnf path at all.
    run_case "$image" "--yes reaches the $want_mgr section" \
        '/tmp/hyperi-update --yes' 0 "==> $want_mgr"

    # 7. and does NOT run the other distro's manager. This is the one that
    #    would have caught the old bug from the other side: a Fedora box must
    #    never reach the APT branch.
    run_case "$image" "--yes does not run $other_mgr" \
        '/tmp/hyperi-update --yes' 0 "" "==> $other_mgr"

    # 8. the reboot check runs and reports one way or the other
    run_case "$image" "reboot check reports" \
        '/tmp/hyperi-update --yes' 0 'reboot (is )?required|No reboot required|cannot tell'

    # 9. summary always printed
    run_case "$image" "summary printed" \
        '/tmp/hyperi-update --yes' 0 '==> Summary'

    # 10. the age the roles write to /etc/default/hyperi-update reaches a run
    #     with no flag, and with no release old enough a release binary is left
    #     exactly as it was, the summary says so, and the run still succeeds.
    #     One GitHub API call per image: kind is the only release binary
    #     planted. The base images lack curl or python3, which the lookup needs
    #     and every provisioned host has. The installs read /dev/null, because
    #     this script arrives on stdin and apt would otherwise consume the rest.
    # shellcheck disable=SC2016  # $rc is the container shell's, not this one's
    run_case "$image" "too-young releases keep the installed copy" \
        '{ command -v curl && command -v python3; } >/dev/null ||
           { { apt-get update -qq && apt-get install -y -qq curl python3; } || dnf install -y -q curl python3; } </dev/null >/dev/null 2>&1
         cp /bin/true /usr/local/bin/kind
         printf "HYPERI_RELEASE_MIN_AGE_DAYS=100000\n" > /etc/default/hyperi-update
         /tmp/hyperi-update --yes; rc=$?
         [ "$(sha256sum </bin/true)" = "$(sha256sum </usr/local/bin/kind)" ] || { echo "kind was replaced"; exit 9; }
         exit $rc' 0 'kind: no release is at least 100000 days old, kept the installed copy' 'kind was replaced'
done

printf '\n========================================\n'
printf 'passed: %d   failed: %d\n' "$PASS" "$FAIL"
if [[ $FAIL -gt 0 ]]; then
    printf '\nfailures:\n'
    for c in "${FAILED_CASES[@]}"; do printf '  - %s\n' "$c"; done
    exit 1
fi
printf 'all good\n'
