#!/usr/bin/env bash

# Pick a color, convert it to a requested CSS format, and copy it.

set -o pipefail

program_name=${0##*/}

usage() {
    cat <<EOF
Usage: $program_name [hex|rgb|hsl]

Pick a color and copy it to the clipboard in the requested format.
The default format is hex.
EOF
}

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

pick_color_linux() {
    require_command yad
    yad --color --init-color='#FFFFFF' --title='Pick a Color' \
        --button=OK:0 --button=Cancel:1
}

pick_color_macos() {
    require_command osascript
    osascript <<'APPLESCRIPT'
set chosenColor to choose color default color {65535, 65535, 65535}
set {redValue, greenValue, blueValue} to chosenColor
set redValue to redValue div 257
set greenValue to greenValue div 257
set blueValue to blueValue div 257
return "#" & hexByte(redValue) & hexByte(greenValue) & hexByte(blueValue)

on hexByte(value)
    set digits to "0123456789ABCDEF"
    return character (value div 16 + 1) of digits & character (value mod 16 + 1) of digits
end hexByte
APPLESCRIPT
}

pick_color() {
    case $(uname -s) in
        Linux) pick_color_linux ;;
        Darwin) pick_color_macos ;;
        *) die "unsupported operating system: $(uname -s)" ;;
    esac
}

rgb_to_hsl() {
    awk -v r="$1" -v g="$2" -v b="$3" 'BEGIN {
        r /= 255; g /= 255; b /= 255
        max = r; if (g > max) max = g; if (b > max) max = b
        min = r; if (g < min) min = g; if (b < min) min = b
        light = (max + min) / 2

        if (max == min) {
            hue = 0
            saturation = 0
        } else {
            delta = max - min
            saturation = light <= 0.5 ? delta / (max + min) : delta / (2 - max - min)
            if (max == r) {
                hue = (g - b) / delta
                if (hue < 0) hue += 6
            } else if (max == g) {
                hue = 2 + (b - r) / delta
            } else {
                hue = 4 + (r - g) / delta
            }
            hue *= 60
        }

        printf "%d %d %d\n", int(hue + 0.5), int(saturation * 100 + 0.5), int(light * 100 + 0.5)
    }'
}

copy_to_clipboard() {
    clipboard_value=$1

    if [ -n "${WAYLAND_DISPLAY:-}" ] && command -v wl-copy >/dev/null 2>&1; then
        printf '%s' "$clipboard_value" | wl-copy && return 0
    fi
    if [ -n "${DISPLAY:-}" ] && command -v xclip >/dev/null 2>&1; then
        printf '%s' "$clipboard_value" | xclip -selection clipboard && return 0
    fi
    if command -v pbcopy >/dev/null 2>&1; then
        printf '%s' "$clipboard_value" | pbcopy && return 0
    fi

    # Fallbacks for unusual or nested desktop sessions.
    if command -v wl-copy >/dev/null 2>&1; then
        printf '%s' "$clipboard_value" | wl-copy 2>/dev/null && return 0
    fi
    if command -v xclip >/dev/null 2>&1; then
        printf '%s' "$clipboard_value" | xclip -selection clipboard 2>/dev/null && return 0
    fi
    return 1
}

save_history() {
    state_root=${XDG_STATE_HOME:-"$HOME/.local/state"}
    history_dir=$state_root/colorpicker
    history_file=$history_dir/history

    if mkdir -p "$history_dir" 2>/dev/null; then
        printf '%s | %s | rgb(%s,%s,%s) | hsl(%s,%s%%,%s%%)\n' \
            "$(date '+%Y-%m-%d %H:%M:%S')" "$hex_color" \
            "$red" "$green" "$blue" "$hue" "$saturation" "$lightness" \
            >> "$history_file" || printf 'Warning: could not update color history.\n' >&2
    else
        printf 'Warning: could not create color history directory: %s\n' "$history_dir" >&2
    fi
}

notify_user() {
    message=$1
    case $(uname -s) in
        Linux)
            if command -v notify-send >/dev/null 2>&1; then
                notify-send 'Color Picker' "$message" -i color-picker >/dev/null 2>&1 || true
            fi
            ;;
        Darwin)
            if command -v osascript >/dev/null 2>&1; then
                osascript -e 'on run argv' \
                    -e 'display notification (item 1 of argv) with title "Color Picker"' \
                    -e 'end run' -- "$message" >/dev/null 2>&1 || true
            fi
            ;;
    esac
}

case ${1:-} in
    -h|--help)
        usage
        exit 0
        ;;
esac

format=${1:-hex}
case $format in
    hex|rgb|hsl) ;;
    *)
        usage >&2
        printf '\nError: unsupported format: %s\n' "$format" >&2
        exit 2
        ;;
esac

if ! color=$(pick_color); then
    printf 'Color selection canceled or empty.\n' >&2
    exit 1
fi

# YAD may include additional fields; the color is its first field.
hex_color=${color%%[[:space:]]*}
if [[ ! $hex_color =~ ^#[[:xdigit:]]{6}([[:xdigit:]]{2})?$ ]]; then
    printf 'Error: picker returned an invalid color: %q\n' "$hex_color" >&2
    exit 1
fi

red=$((16#${hex_color:1:2}))
green=$((16#${hex_color:3:2}))
blue=$((16#${hex_color:5:2}))

has_alpha=false
if [ ${#hex_color} -eq 9 ]; then
    has_alpha=true
    alpha_decimal=$((16#${hex_color:7:2}))
    alpha=$(awk -v a="$alpha_decimal" 'BEGIN { printf "%.2f", a / 255 }')
fi

read -r hue saturation lightness <<EOF
$(rgb_to_hsl "$red" "$green" "$blue")
EOF

case $format in
    hex)
        output=$hex_color
        format_name=HEX
        ;;
    rgb)
        if $has_alpha; then
            output="rgba($red, $green, $blue, $alpha)"
        else
            output="rgb($red, $green, $blue)"
        fi
        format_name=RGB
        ;;
    hsl)
        if $has_alpha; then
            output="hsla($hue, $saturation%, $lightness%, $alpha)"
        else
            output="hsl($hue, $saturation%, $lightness%)"
        fi
        format_name=HSL
        ;;
esac

save_history

if copy_to_clipboard "$output"; then
    copy_status='copied to clipboard'
else
    copy_status='not copied (no working clipboard tool found)'
    printf 'Warning: could not copy the color to the clipboard.\n' >&2
fi

printf 'Color %s (%s) %s.\n' "$output" "$format_name" "$copy_status"
printf 'HEX: %s\n' "$hex_color"
printf 'RGB: %s,%s,%s\n' "$red" "$green" "$blue"
printf 'HSL: %s,%s%%,%s%%\n' "$hue" "$saturation" "$lightness"

notify_user "Color $output ($format_name) $copy_status"
