#!/bin/bash

# System Info Screenshot Tool
# Usage: sysinf [filename] [--no-prompt] [--select-area]

# Configuration
OUTPUT_DIR="${HOME}/Pictures/sysinfo"
SCREENSHOT_DELAY=0.5

# Parse arguments
CUSTOM_FILENAME=""
NO_PROMPT=false
SELECT_AREA=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --no-prompt)
            NO_PROMPT=true
            shift
            ;;
        --select-area)
            SELECT_AREA=true
            shift
            ;;
        --help|-h)
            echo "Usage: sysinf [filename] [--no-prompt] [--select-area]"
            echo "  filename      Custom filename (optional)"
            echo "  --no-prompt   Skip 'press any key' prompt"
            echo "  --select-area Select area to screenshot (Wayland only)"
            exit 0
            ;;
        *)
            CUSTOM_FILENAME="$1"
            shift
            ;;
    esac
done

# Check for required dependencies
command -v fastfetch >/dev/null || { echo "Error: fastfetch not installed"; exit 1; }

# Detect display server
IS_WAYLAND=false
IS_X11=false

if [ -n "$WAYLAND_DISPLAY" ]; then
    IS_WAYLAND=true
    command -v grim >/dev/null || { echo "Error: grim not installed (required for Wayland)"; exit 1; }
    if [ "$SELECT_AREA" = true ]; then
        command -v slurp >/dev/null || { echo "Error: slurp not installed (required for area selection)"; exit 1; }
    fi
elif [ -n "$DISPLAY" ]; then
    IS_X11=true
    command -v scrot >/dev/null || { echo "Error: scrot not installed (required for X11)"; exit 1; }
else
    echo "Error: Could not detect display server (neither Wayland nor X11)"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR" || { echo "Error: Could not create directory $OUTPUT_DIR"; exit 1; }

# Generate filename
if [ -n "$CUSTOM_FILENAME" ]; then
    # Add .png extension if not present
    if [[ "$CUSTOM_FILENAME" != *.png ]]; then
        CUSTOM_FILENAME="${CUSTOM_FILENAME}.png"
    fi
    Fetch="$OUTPUT_DIR/$CUSTOM_FILENAME"
else
    Fetch="$OUTPUT_DIR/$(date +%Y-%m-%d_%H-%M-%S)_sysinfo.png"
fi

clear

echo "               System Info                 $(date)   "
fastfetch

# Add delay before screenshot
sleep "$SCREENSHOT_DELAY"

# Take screenshot based on display server
if [ "$IS_WAYLAND" = true ]; then
    echo "Wayland detected, using grim..."
    if [ "$SELECT_AREA" = true ]; then
        grim -g "$(slurp)" "$Fetch" 2>/dev/null || { echo "Error: grim failed"; exit 1; }
    else
        grim "$Fetch" 2>/dev/null || { echo "Error: grim failed"; exit 1; }
    fi
    # Copy to clipboard on Wayland
    if command -v wl-copy >/dev/null; then
        wl-copy < "$Fetch" && echo "Screenshot copied to clipboard"
    fi
elif [ "$IS_X11" = true ]; then
    echo "X11 detected, using scrot..."
    scrot "$Fetch" 2>/dev/null || { echo "Error: scrot failed"; exit 1; }
    # Copy to clipboard on X11
    if command -v xclip >/dev/null; then
        xclip -selection clipboard -t image/png -i "$Fetch" && echo "Screenshot copied to clipboard"
    fi
fi

# Verify screenshot was created
if [ -f "$Fetch" ]; then
    echo "Screenshot saved: $Fetch"
else
    echo "Error: Screenshot was not created"
    exit 1
fi

# Prompt user unless --no-prompt is set
if [ "$NO_PROMPT" = false ]; then
    read -n1 -r -p "Press any key to continue..."
fi
