#!/usr/bin/env bash
# wulfup-lib.sh - Shared functions for wulfup scripts

WULFUP_LIB_LOADED=1

# Exit codes
readonly WULFUP_EXIT_SUCCESS=0
readonly WULFUP_EXIT_ERROR=1
readonly WULFUP_EXIT_PRECONDITION=2
readonly WULFUP_EXIT_ABORTED=3

# Behavior (overridden by config / CLI)
AUTO_YES="${AUTO_YES:-no}"
CONTINUE_ON_ERROR="${CONTINUE_ON_ERROR:-no}"
PACMAN_NOCONFIRM="${PACMAN_NOCONFIRM:-no}"
SEND_NOTIFICATION="${SEND_NOTIFICATION:-no}"
FAILURES=()

# Color definitions
if [[ -t 1 ]] || [[ -t 2 ]]; then
    RED=$'\e[0;31m'
    GREEN=$'\e[0;32m'
    YELLOW=$'\e[0;33m'
    BLUE=$'\e[0;34m'
    CYAN=$'\e[0;36m'
    BOLD=$'\e[1m'
    RESET=$'\e[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' RESET=''
fi

#==============================================================================
# Output functions
#==============================================================================

info() {
    echo -e "${BLUE}${BOLD}==>${RESET} ${BOLD}$*${RESET}" >&2
}

success() {
    echo -e "${GREEN}${BOLD}==>${RESET} ${GREEN}$*${RESET}" >&2
}

warn() {
    echo -e "${YELLOW}${BOLD}==> WARNING:${RESET} ${YELLOW}$*${RESET}" >&2
}

error() {
    echo -e "${RED}${BOLD}==> ERROR:${RESET} ${RED}$*${RESET}" >&2
}

step() {
    echo -e "${CYAN}${BOLD}::${RESET} $*" >&2
}

die() {
    local code="${1:-$WULFUP_EXIT_ERROR}"
    shift || true
    error "$*"
    exit "$code"
}

#==============================================================================
# Config and confirmation
#==============================================================================

load_config() {
    local config_file
    for config_file in \
        "${XDG_CONFIG_HOME:-$HOME/.config}/wulfup/config" \
        "/etc/wulfup.conf"; do
        if [[ -f "$config_file" ]]; then
            # shellcheck source=/dev/null
            source "$config_file"
            info "Loaded config: $config_file"
            return 0
        fi
    done
}

confirm() {
    local prompt="$1"
    local default_yes="${2:-no}"

    if [[ "$AUTO_YES" == "yes" ]]; then
        return 0
    fi

    if [[ "$default_yes" == "yes" ]]; then
        read -p "$prompt" -n 1 -r < /dev/tty
        echo
        [[ $REPLY =~ ^[Nn]$ ]] && return 1
        return 0
    fi

    read -p "$prompt" -n 1 -r < /dev/tty
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}

record_failure() {
    FAILURES+=("$1")
}

#==============================================================================
# Command execution - shows command before running
#==============================================================================

run_cmd() {
    echo -e "${GREEN}${BOLD}\$${RESET} $*" >&2
    "$@"
}

run_sudo() {
    echo -e "${GREEN}${BOLD}\$ sudo${RESET} $*" >&2
    sudo "$@"
}

pacman_noconfirm_args() {
    if [[ "$PACMAN_NOCONFIRM" == "yes" ]]; then
        echo --noconfirm
    fi
}

handle_failure() {
    local context="$1"
    local code="${2:-$WULFUP_EXIT_ERROR}"

    if [[ "$CONTINUE_ON_ERROR" == "yes" ]]; then
        warn "$context (continuing due to --continue-on-error)"
        record_failure "$context"
        return 0
    fi

    die "$code" "$context"
}

report_failures() {
    if [[ ${#FAILURES[@]} -eq 0 ]]; then
        return 0
    fi

    echo >&2
    error "The following steps failed:"
    local failure
    for failure in "${FAILURES[@]}"; do
        echo "  - $failure" >&2
    done
    return 1
}

#==============================================================================
# Desktop notifications (cross-platform)
#==============================================================================

send_desktop_notification() {
    local title="${1:-System Update Complete}"
    local message="${2:-Update finished}"

    if [[ "$SEND_NOTIFICATION" == "no" ]]; then
        return 0
    fi

    if [[ -z "${DISPLAY:-}" ]] && [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
        return 0
    fi

    if ! command -v notify-send &>/dev/null; then
        return 0
    fi

    run_cmd notify-send "$title" "$message" --icon=software-update-available || true
}