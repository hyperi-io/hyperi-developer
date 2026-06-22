#!/usr/bin/env bats
# 02-syntax.bats - Test all scripts have valid bash syntax

setup() {
    # Change to parent directory where scripts are
    cd "$(dirname "$BATS_TEST_DIRNAME")"
}

@test "lib.sh has valid syntax" {
    run bash -n lib.sh
    [ "$status" -eq 0 ]
}

@test "install-hyperi-developer.sh has valid syntax" {
    run bash -n install-hyperi-developer.sh
    [ "$status" -eq 0 ]
}

@test "install-hyperi-developer-core.sh has valid syntax" {
    run bash -n install-hyperi-developer-core.sh
    [ "$status" -eq 0 ]
}

@test "install-ghostty.sh has valid syntax" {
    run bash -n install-ghostty.sh
    [ "$status" -eq 0 ]
}

@test "install-all.sh has valid syntax" {
    run bash -n install-all.sh
    [ "$status" -eq 0 ]
}

@test "install-vm-optimizer.sh exists and has valid syntax" {
    if [[ -f install-vm-optimizer.sh ]]; then
        run bash -n install-vm-optimizer.sh
        [ "$status" -eq 0 ]
    else
        skip "install-vm-optimizer.sh not found"
    fi
}

@test "install-rdp-optimizer.sh exists and has valid syntax" {
    if [[ -f install-rdp-optimizer.sh ]]; then
        run bash -n install-rdp-optimizer.sh
        [ "$status" -eq 0 ]
    else
        skip "install-rdp-optimizer.sh not found"
    fi
}

@test "all scripts start with shebang" {
    for script in *.sh; do
        if [[ -f "$script" ]]; then
            run head -n1 "$script"
            [[ "$output" == "#!/bin/bash"* ]]
        fi
    done
}

@test "all scripts are executable" {
    # Main scripts should be executable
    for script in install-*.sh; do
        if [[ -f "$script" ]]; then
            [[ -x "$script" ]] || {
                echo "$script is not executable"
                return 1
            }
        fi
    done
}