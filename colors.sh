#!/usr/bin/env bash

# colorpicker.sh - A color picker that copies the selected color to clipboard
# Usage: ./colorpicker.sh [format]
#   format: hex (default), rgb, hsl

# Help option
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "Usage: $(basename $0) [format]"
    echo "Formats: hex (default), rgb, hsl"
    echo "Picks a color and copies it to clipboard in the specified format"
    exit 0
fi

# Set output format based on argument
format=${1:-"hex"}  # Default to hex

# Check if required commands are available
for cmd in yad; do
    if ! command -v $cmd &> /dev/null; then
        echo "Error: $cmd is not installed. Please install it first."
        exit 1
    fi
done

# Pick a color using yad's color selection dialog
color=$(yad --color --init-color="#FFFFFF" --title="Pick a Color" --button=OK:0 --button=Cancel:1)
status=$?  # Capture the exit status immediately

# Check if OK was pressed and color is not empty
if [ "$status" -eq 0 ] && [ -n "$color" ]; then
    # Extract the hex code of the color
    hex_color=$(echo "$color" | awk '{print $1}')

    # Check for valid hex color format
    if [[ ! "$hex_color" =~ ^#[0-9A-Fa-f]{6,8}$ ]]; then
        echo "Warning: Invalid color format received: $hex_color"
        echo "Attempting to process anyway..."
    fi

    # Handle alpha channel if present
    has_alpha=false
    if [[ ${#hex_color} -gt 7 ]]; then
        has_alpha=true
        alpha_hex="${hex_color:7:2}"
        alpha_dec=$((16#$alpha_hex))
        alpha_percent=$(( (alpha_dec * 100) / 255 ))
        echo "Color with alpha channel detected: $hex_color (${alpha_percent}% opacity)"
    fi

    # Convert hex to RGB
    r=$((16#${hex_color:1:2}))
    g=$((16#${hex_color:3:2}))
    b=$((16#${hex_color:5:2}))

    # Convert RGB to HSL
    # Algorithm adapted from https://en.wikipedia.org/wiki/HSL_and_HSV
    r_norm=$(echo "scale=3; $r/255" | bc)
    g_norm=$(echo "scale=3; $g/255" | bc)
    b_norm=$(echo "scale=3; $b/255" | bc)

    max=$(echo "$r_norm $g_norm $b_norm" | tr ' ' '\n' | sort -nr | head -1)
    min=$(echo "$r_norm $g_norm $b_norm" | tr ' ' '\n' | sort -n | head -1)

    # Calculate lightness
    l=$(echo "scale=3; ($max + $min)/2" | bc)
    l_percent=$(echo "scale=0; $l * 100" | bc)

    # Calculate saturation
    if (( $(echo "$max == $min" | bc -l) )); then
        s=0
    elif (( $(echo "$l <= 0.5" | bc -l) )); then
        s=$(echo "scale=3; ($max - $min)/($max + $min)" | bc)
    else
        s=$(echo "scale=3; ($max - $min)/(2 - $max - $min)" | bc)
    fi
    s_percent=$(echo "scale=0; $s * 100" | bc)

    # Calculate hue
    if (( $(echo "$max == $min" | bc -l) )); then
        h=0
    elif (( $(echo "$r_norm == $max" | bc -l) )); then
        h=$(echo "scale=3; ($g_norm - $b_norm)/($max - $min)" | bc)
        if (( $(echo "$h < 0" | bc -l) )); then
            h=$(echo "scale=3; $h + 6" | bc)
        fi
    elif (( $(echo "$g_norm == $max" | bc -l) )); then
        h=$(echo "scale=3; 2 + ($b_norm - $r_norm)/($max - $min)" | bc)
    else
        h=$(echo "scale=3; 4 + ($r_norm - $g_norm)/($max - $min)" | bc)
    fi
    h=$(echo "scale=0; $h * 60" | bc)

    # Prepare output based on selected format
    case "$format" in
        hex)
            output="$hex_color"
            format_name="HEX"
            ;;
        rgb)
            if $has_alpha; then
                output="rgba($r, $g, $b, $(echo "scale=2; $alpha_dec/255" | bc))"
            else
                output="rgb($r, $g, $b)"
            fi
            format_name="RGB"
            ;;
        hsl)
            if $has_alpha; then
                output="hsla($h, ${s_percent}%, ${l_percent}%, $(echo "scale=2; $alpha_dec/255" | bc))"
            else
                output="hsl($h, ${s_percent}%, ${l_percent}%)"
            fi
            format_name="HSL"
            ;;
        *)
            output="$hex_color"
            format_name="HEX"
            echo "Warning: Unknown format '$format'. Using hex instead."
            ;;
    esac

    # Save to color history
    history_file="$HOME/.color_picker_history"
    echo "$(date +"%Y-%m-%d %H:%M:%S") | $hex_color | rgb($r,$g,$b) | hsl($h,${s_percent}%,${l_percent}%)" >> "$history_file"

    # Copy the color to the clipboard using available clipboard tool
    if command -v xclip &> /dev/null; then
        echo -n "$output" | xclip -selection clipboard
        copy_status="copied to clipboard"
    elif command -v wl-copy &> /dev/null; then
        echo -n "$output" | wl-copy  # For Wayland
        copy_status="copied to clipboard"
    elif command -v pbcopy &> /dev/null; then
        echo -n "$output" | pbcopy  # For macOS
        copy_status="copied to clipboard"
    else
        echo "Warning: Could not find a clipboard tool. Color was not copied."
        copy_status="not copied (no clipboard tool found)"
    fi

    # Display information
    echo "Color $output ($format_name) $copy_status."
    echo "HEX: $hex_color"
    echo "RGB: $r,$g,$b"
    echo "HSL: $h,${s_percent}%,${l_percent}%"

    # Send desktop notification if possible
    if command -v notify-send &> /dev/null; then
        notify-send "Color Picker" "Color $output ($format_name) copied to clipboard" -i color-picker
    fi

    exit 0
else
    echo "Color selection canceled or empty."
    exit 1
fi
