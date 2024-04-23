#!/usr/bin/env bash

# Pick a color using yad's color selection dialog
color=$(yad --color --init-color="#FFFFFF" --title="Pick a Color" --button=OK:0 --button=Cancel:1)
status=$?  # Capture the exit status immediately

# Check if OK was pressed
if [ "$status" -eq 0 ]; then
    # Extract the hex code of the color
    hex_color=$(echo "$color" | awk '{print $1}')

    # Copy the hex code to the clipboard using xclip
    echo -n "$hex_color" | xclip -selection clipboard
fi

