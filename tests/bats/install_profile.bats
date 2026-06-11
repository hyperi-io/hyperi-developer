#!/usr/bin/env bats
#
# install.sh --profile tests.
#
# Canonical output order (deterministic): developer, core, rust, iac, gui_extras, openvpn.
# Dedup rules: --profile developer,core -> developer,core (not developer,developer,core).
# Implicit rules:
#   - "core" implies "developer"
#   - "openvpn" requires "core" (hard error without it)
#   - "all" expands to rust,iac,gui_extras (no openvpn)

load helpers

@test "--profile developer sets base tier to developer" {
    run profile_parse --profile developer
    [ "$status" -eq 0 ]
    [[ "$output" == *"RESOLVED_TAGS=developer"* ]]
}

@test "--profile core includes developer tier (implicit dependency)" {
    run profile_parse --profile core
    [ "$status" -eq 0 ]
    [[ "$output" == *"RESOLVED_TAGS=developer,core"* ]]
}

@test "--profile core,rust includes developer,core,rust" {
    run profile_parse --profile core,rust
    [ "$status" -eq 0 ]
    [[ "$output" == *"RESOLVED_TAGS=developer,core,rust"* ]]
}

@test "--profile all expands to developer,rust,iac,gui_extras (no openvpn, default developer base)" {
    run profile_parse --profile all
    [ "$status" -eq 0 ]
    [[ "$output" == *"RESOLVED_TAGS=developer,rust,iac,gui_extras"* ]]
}

@test "--profile core,all expands to developer,core,rust,iac,gui_extras" {
    run profile_parse --profile core,all
    [ "$status" -eq 0 ]
    [[ "$output" == *"RESOLVED_TAGS=developer,core,rust,iac,gui_extras"* ]]
}

@test "--profile openvpn alone is a hard error (requires core)" {
    run profile_parse --profile openvpn
    [ "$status" -ne 0 ]
    [[ "$output" == *"--profile openvpn requires --profile core"* ]]
}

@test "--profile core,openvpn is valid" {
    run profile_parse --profile core,openvpn
    [ "$status" -eq 0 ]
    [[ "$output" == *"RESOLVED_TAGS=developer,core,openvpn"* ]]
}

@test "--profile rust alone defaults base to developer" {
    run profile_parse --profile rust
    [ "$status" -eq 0 ]
    [[ "$output" == *"RESOLVED_TAGS=developer,rust"* ]]
}

@test "--profile developer,core dedupes to core" {
    run profile_parse --profile developer,core
    [ "$status" -eq 0 ]
    [[ "$output" == *"RESOLVED_TAGS=developer,core"* ]]
}

@test "unknown profile name is rejected" {
    run profile_parse --profile frobnicate
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown profile: frobnicate"* ]]
}

@test "--core (legacy) warns and aliases to --profile core,rust,iac" {
    run profile_parse --core
    [ "$status" -eq 0 ]
    [[ "$output" == *"[WARN]"* ]]
    [[ "$output" == *"deprecated"* ]]
    [[ "$output" == *"RESOLVED_TAGS=developer,core,rust,iac"* ]]
}

@test "--all (legacy) warns and aliases to --profile core,all" {
    run profile_parse --all
    [ "$status" -eq 0 ]
    [[ "$output" == *"[WARN]"* ]]
    [[ "$output" == *"deprecated"* ]]
    [[ "$output" == *"RESOLVED_TAGS=developer,core,rust,iac,gui_extras"* ]]
}

@test "no --profile defaults to developer only" {
    run profile_parse
    [ "$status" -eq 0 ]
    [[ "$output" == *"RESOLVED_TAGS=developer"* ]]
}
