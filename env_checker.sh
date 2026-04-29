#!/usr/bin/env bash

# env_checker.sh - Display or look up environment variables
#
# Usage:
#   ./env_checker.sh                        List all environment variables
#   ./env_checker.sh VAR [VAR ...]          Look up one or more variables by exact name
#   ./env_checker.sh -c VAR [VAR ...]       Case-insensitive lookup (returns first match per name)
#   ./env_checker.sh -h|--help              Show this help
#
# Flags:
#   -c, --case    Case-insensitive match; returns the first variable whose name
#                 matches VAR regardless of case. If multiple variables share the
#                 same case-folded name, only the first is shown.
#   -h, --help    Print usage and exit
#
# Exit codes:
#   0   Success
#   1   Unknown flag passed

print_vars() {
    local case_insensitive=0

    while [[ "$1" == -* ]]; do
        case "$1" in
            -c|--case) case_insensitive=1 ;;
            -h|--help) usage; return 0 ;;
            *) echo "Unknown flag: $1"; return 1 ;;
        esac
        shift
    done

    for var in "$@"; do
        if [ "$case_insensitive" -eq 1 ]; then
            # grep -i matches the first env var whose name folds to $var
            match=$(printenv | grep -i "^${var}=" | head -n 1)
            if [ -n "$match" ]; then
                echo "$match"
            else
                echo "$var: not set"
            fi
        else
            if printenv "$var" &>/dev/null; then
                echo "$var=$(printenv "$var")"
            elif [ -z "${!var+x}" ]; then
                echo "$var: not set"
            else
                echo "$var: set but empty"
            fi
        fi
    done
}

usage() {
    sed -n '3,/^$/p' "$0" | sed 's/^# \{0,1\}//'
}

show_all_env_vars() {
    echo "All Environment Variables"
    echo "—————————————"
    printenv
}

if [ "$#" -eq 0 ]; then
    show_all_env_vars
elif [[ "$1" == "-h" || "$1" == "--help" ]]; then
    usage
else
    print_vars "$@"
fi
