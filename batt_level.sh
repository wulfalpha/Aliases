#!/usr/bin/env bash
# battery.sh - show battery level as a colored progress bar.
# Works on Linux, macOS, FreeBSD/OpenBSD, WSL and Git-Bash/Cygwin on Windows.

set -u

BAR_WIDTH=${BAR_WIDTH:-20}
case "$BAR_WIDTH" in ''|*[!0-9]*|0) BAR_WIDTH=20 ;; esac   # reject junk, negatives, zero
FILL_CHAR=${FILL_CHAR:-'#'}
EMPTY_CHAR=${EMPTY_CHAR:-' '}

# ---------- colors (disabled when not a terminal or NO_COLOR is set) ----------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    RED=$'\033[31m'; YELLOW=$'\033[33m'; GREEN=$'\033[32m'
    BOLD=$'\033[1m'; RESET=$'\033[0m'
else
    RED=''; YELLOW=''; GREEN=''; BOLD=''; RESET=''
fi

# ---------- battery readers: each echoes "PERCENT STATUS" or returns 1 -------

read_linux() {
    local bat cap status
    for bat in /sys/class/power_supply/*; do
        [ -r "$bat/type" ] || continue
        [ "$(cat "$bat/type")" = "Battery" ] || continue
        [ -r "$bat/capacity" ] || continue
        cap=$(cat "$bat/capacity")
        status=$(cat "$bat/status" 2>/dev/null || echo Unknown)
        echo "$cap $status"
        return 0
    done
    return 1
}

read_macos() {
    command -v pmset >/dev/null 2>&1 || return 1
    local out cap status
    out=$(pmset -g batt 2>/dev/null) || return 1
    cap=$(printf '%s\n' "$out" | grep -o '[0-9]\{1,3\}%' | head -n1)
    [ -n "$cap" ] || return 1
    cap=${cap%\%}
    if   printf '%s\n' "$out" | grep -qi 'charged';  then status="Full"
    elif printf '%s\n' "$out" | grep -qi 'AC Power'; then status="Charging"
    else                                                  status="Discharging"
    fi
    echo "$cap $status"
}

read_bsd() {
    local cap state
    if command -v sysctl >/dev/null 2>&1; then
        cap=$(sysctl -n hw.acpi.battery.life 2>/dev/null)
        if [ -n "${cap:-}" ] && [ "$cap" -ge 0 ] 2>/dev/null; then
            # ACPI state is a bitmask: 1 = discharging, 2 = charging,
            # 4 = critical, 0 = charge complete / running on AC.
            state=$(sysctl -n hw.acpi.battery.state 2>/dev/null || echo "")
            case "$state" in
                ''|*[!0-9]*)                        echo "$cap Unknown" ;;
                *) if   [ $(( state & 2 )) -ne 0 ]; then echo "$cap Charging"
                   elif [ $(( state & 1 )) -ne 0 ]; then echo "$cap Discharging"
                   else                                  echo "$cap Full"
                   fi ;;
            esac
            return 0
        fi
    fi
    if command -v apm >/dev/null 2>&1; then
        cap=$(apm -l 2>/dev/null)
        case "$cap" in
            ''|*[!0-9]*) return 1 ;;
        esac
        [ "$cap" -gt 100 ] && return 1   # 255 == no battery
        [ "$(apm -a 2>/dev/null)" = "1" ] && echo "$cap Charging" || echo "$cap Discharging"
        return 0
    fi
    return 1
}

read_windows() {
    local ps out cap status
    for ps in powershell.exe powershell pwsh.exe pwsh; do
        command -v "$ps" >/dev/null 2>&1 && break
        ps=""
    done
    [ -n "${ps:-}" ] || return 1
    out=$("$ps" -NoProfile -Command \
        '$b = Get-CimInstance Win32_Battery | Select-Object -First 1;
         if ($b) { "{0} {1}" -f $b.EstimatedChargeRemaining, $b.BatteryStatus }' \
        2>/dev/null | tr -d '\r')
    [ -n "$out" ] || return 1
    cap=${out%% *}
    case "$cap" in ''|*[!0-9]*) return 1 ;; esac
    case "${out##* }" in
        2|6|7|8|9) status="Charging" ;;
        3)         status="Full" ;;
        *)         status="Discharging" ;;
    esac
    echo "$cap $status"
}

get_battery() {
    case "$(uname -s 2>/dev/null)" in
        Linux*)
            read_linux && return 0
            # WSL exposes no /sys battery, fall through to PowerShell
            read_windows && return 0
            ;;
        Darwin*)
            read_macos && return 0 ;;
        *BSD*|DragonFly*)
            read_bsd && return 0 ;;
        CYGWIN*|MINGW*|MSYS*)
            read_windows && return 0 ;;
        *)
            read_linux && return 0
            read_macos && return 0
            read_bsd    && return 0
            read_windows && return 0
            ;;
    esac
    return 1
}

# ---------- rendering --------------------------------------------------------

draw_bar() {
    local pct=$1 color filled empty bar=''
    if   [ "$pct" -le 20 ]; then color=$RED
    elif [ "$pct" -le 50 ]; then color=$YELLOW
    else                         color=$GREEN
    fi

    filled=$(( pct * BAR_WIDTH / 100 ))
    [ "$filled" -gt "$BAR_WIDTH" ] && filled=$BAR_WIDTH
    [ "$filled" -lt 0 ] && filled=0
    empty=$(( BAR_WIDTH - filled ))

    while [ "$filled" -gt 0 ]; do bar="$bar$FILL_CHAR"; filled=$((filled - 1)); done
    while [ "$empty"  -gt 0 ]; do bar="$bar$EMPTY_CHAR"; empty=$((empty - 1)); done

    printf '%s[%s]%s %s%3d%%%s' "$color" "$bar" "$RESET" "$BOLD" "$pct" "$RESET"
}

# ---------- main -------------------------------------------------------------

main() {
    local info pct status
    if ! info=$(get_battery); then
        printf 'Could not find a battery.\n' >&2
        exit 1
    fi

    pct=${info%% *}
    case "$info" in
        *' '*) status=${info#* } ;;   # keep multi-word states like "Not charging"
        *)     status='' ;;
    esac

    case "${pct#-}" in                # tolerate a leading sign, reject anything else
        ''|*[!0-9]*)
            printf 'Battery reported an unreadable level: %s\n' "${info:-<empty>}" >&2
            exit 1 ;;
    esac

    # clamp anything odd a driver might report
    [ "$pct" -gt 100 ] && pct=100
    [ "$pct" -lt 0 ]   && pct=0

    # "full" is a charge state, not a level: a charge-limited battery reports
    # Full below 100%, and 100% while unplugged is still discharging.
    if [ "$status" = "Full" ]; then
        printf '%sBattery is full.%s ' "$GREEN" "$RESET"
        draw_bar "$pct"
        printf '\n'
        exit 0
    fi

    draw_bar "$pct"
    case "$status" in
        Charging) printf ' (charging)' ;;
    esac
    printf '\n'
}

main "$@"
