#!/usr/bin/env bash
# Script to display connected human interface devices (mice and keyboards) via notify-send

# Parse command line arguments
VERBOSE=false
if [[ "$1" == "-v" ]] || [[ "$1" == "--verbose" ]]; then
    VERBOSE=true
fi

# Dependencies check
if ! command -v notify-send &> /dev/null; then
    echo "Error: notify-send could not be found"
    exit 1
fi

if ! command -v libinput &> /dev/null; then
    echo "Error: libinput could not be found"
    exit 1
fi

# Parse libinput list-devices output
# The output is structured with "Device:" lines followed by properties
# We need to find devices with "keyboard" or "pointer" in their Capabilities line

output=""
current_device=""
current_kernel=""
current_capabilities=""

while IFS= read -r line; do
    # Check if this is a new device entry
    if [[ $line =~ ^Device:[[:space:]]+(.+)$ ]]; then
        # Process previous device if it was a keyboard or mouse
        if [[ -n "$current_device" ]] && [[ "$current_capabilities" =~ (keyboard|pointer) ]]; then
            device_type=""
            if [[ "$current_capabilities" =~ keyboard ]] && [[ "$current_capabilities" =~ pointer ]]; then
                device_type="[Keyboard + Pointer]"
            elif [[ "$current_capabilities" =~ keyboard ]]; then
                device_type="[Keyboard]"
            elif [[ "$current_capabilities" =~ pointer ]]; then
                device_type="[Mouse/Pointer]"
            fi

            output+="$device_type $current_device\n"
            output+="  Path: $current_kernel\n\n"
        fi

        # Start tracking new device
        current_device="${BASH_REMATCH[1]}"
        current_kernel=""
        current_capabilities=""

    elif [[ $line =~ ^Kernel:[[:space:]]+(.+)$ ]]; then
        current_kernel="${BASH_REMATCH[1]}"

    elif [[ $line =~ ^Capabilities:[[:space:]]+(.+)$ ]]; then
        current_capabilities="${BASH_REMATCH[1]}"
    fi
done < <(libinput list-devices 2>/dev/null)

# Process the last device
if [[ -n "$current_device" ]] && [[ "$current_capabilities" =~ (keyboard|pointer) ]]; then
    device_type=""
    if [[ "$current_capabilities" =~ keyboard ]] && [[ "$current_capabilities" =~ pointer ]]; then
        device_type="[Keyboard + Pointer]"
    elif [[ "$current_capabilities" =~ keyboard ]]; then
        device_type="[Keyboard]"
    elif [[ "$current_capabilities" =~ pointer ]]; then
        device_type="[Mouse/Pointer]"
    fi

    output+="$device_type $current_device\n"
    output+="  Path: $current_kernel\n"
fi

# Display the results
if [[ -n "$output" ]]; then
    # Print to stdout if verbose mode is enabled
    if [[ "$VERBOSE" == true ]]; then
        echo "Connected Input Devices:"
        echo -e "$output"
    fi

    # Send notification
    echo -e "$output" | notify-send "Connected Input Devices" "$(cat)"
else
    if [[ "$VERBOSE" == true ]]; then
        echo "No keyboards or mice detected"
    fi
    notify-send "Connected Input Devices" "No keyboards or mice detected"
fi

exit 0
