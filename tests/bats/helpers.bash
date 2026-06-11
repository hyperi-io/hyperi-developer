#!/usr/bin/env bash
INSTALL_SH="${BATS_TEST_DIRNAME}/../../install.sh"
profile_parse() {
    DFE_PROFILE_TEST=1 bash "$INSTALL_SH" "$@" 2>&1
}
