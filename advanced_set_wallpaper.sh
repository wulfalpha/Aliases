#!/usr/bin/env bash

# Show usage information
usage() {
    echo "Usage: $0 [OPTIONS] [/path/to/image1.jpg] [/path/to/image2.jpg] ..."
    echo "Options:"
    echo "  -t, --transition TYPE   Set transition type (simple, wipe, wave, grow, outer, any)"
    echo "  -d, --duration SECONDS  Set transition duration in seconds"
    echo "  -f, --filter FILTER     Apply filter (none, blur, pixel, greyscale, saturate)"
    echo "  -p, --position X,Y      Set transition position (0.0,0.0 is top left, 1.0,1.0 is bottom right)"
    echo "  -a, --angle DEGREES     Set transition angle in degrees"
    echo "  -r, --resize METHOD     Set resize method (crop, fit, none)"
    echo "  -c, --color HEX         Set fill color (hex format without #, e.g., '000000')"
    echo "  -R, --random            Select a random wallpaper from $HOME/wallpapers"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "Multi-monitor support:"
    echo "  - Pass multiple images to set different wallpapers per monitor"
    echo "  - Images are assigned to monitors in order (left to right)"
    exit 1
}

# Default values
TRANSITION_TYPE="wave"
TRANSITION_DURATION=2
FILTER="Bilinear"
POSITION="0.5,0.5"
ANGLE=30
RESIZE="fit"
FILL_COLOR="000000"
RANDOM_WALLPAPER=false
IMAGE_PATHS=()

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--transition)
            TRANSITION_TYPE="$2"
            shift 2
            ;;
        -d|--duration)
            TRANSITION_DURATION="$2"
            shift 2
            ;;
        -f|--filter)
            FILTER="$2"
            shift 2
            ;;
        -p|--position)
            POSITION="$2"
            shift 2
            ;;
        -a|--angle)
            ANGLE="$2"
            shift 2
            ;;
        -r|--resize)
            RESIZE="$2"
            shift 2
            ;;
        -c|--color)
            FILL_COLOR="$2"
            shift 2
            ;;
        -R|--random)
            RANDOM_WALLPAPER=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        -*)
            echo "Unknown option: $1"
            usage
            ;;
        *)
            IMAGE_PATHS+=("$1")
            shift
            ;;
    esac
done

# Handle random wallpaper selection
if [ "$RANDOM_WALLPAPER" = true ]; then
    WALLPAPER_DIR="$HOME/wallpapers"

    # Check if wallpaper directory exists
    if [ ! -d "$WALLPAPER_DIR" ]; then
        echo "Error: Wallpaper directory does not exist: $WALLPAPER_DIR"
        exit 1
    fi

    # Get list of image files
    IMAGE_FILES=($(find "$WALLPAPER_DIR" -type f \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" -o -name "*.gif" -o -name "*.webp" \) | sort))

    # Check if any images were found
    if [ ${#IMAGE_FILES[@]} -eq 0 ]; then
        echo "Error: No image files found in $WALLPAPER_DIR"
        exit 1
    fi

    # Pick a random image
    RANDOM_INDEX=$((RANDOM % ${#IMAGE_FILES[@]}))
    IMAGE_PATHS=("${IMAGE_FILES[$RANDOM_INDEX]}")

    echo "Randomly selected: ${IMAGE_PATHS[0]}"
fi

# Check if an image path was provided or selected
if [ ${#IMAGE_PATHS[@]} -eq 0 ]; then
    echo "Error: Please provide the path to an image or use --random flag."
    usage
fi

# Verify that all files exist
for img in "${IMAGE_PATHS[@]}"; do
    if [ ! -f "$img" ]; then
        echo "Error: The file '$img' does not exist."
        exit 1
    fi
done

# Detect display server (Wayland or X11)
if [ -n "$WAYLAND_DISPLAY" ]; then
    DISPLAY_SERVER="wayland"
elif [ -n "$DISPLAY" ]; then
    DISPLAY_SERVER="x11"
else
    echo "Error: Could not detect display server (neither Wayland nor X11)"
    exit 1
fi

# Set wallpaper based on display server
if [ "$DISPLAY_SERVER" = "wayland" ]; then
    # Initialize swww-daemon if not already running
    if ! pgrep -x swww-daemon >/dev/null; then
        swww-daemon
        sleep 0.5  # Give daemon time to start
    fi

    # Get list of outputs (monitors)
    OUTPUTS=($(swww query | cut -d: -f2 | xargs))
    NUM_OUTPUTS=${#OUTPUTS[@]}
    NUM_IMAGES=${#IMAGE_PATHS[@]}

    if [ $NUM_IMAGES -eq 1 ]; then
        # Single image: apply to all monitors
        swww img "${IMAGE_PATHS[0]}" \
            --transition-type "$TRANSITION_TYPE" \
            --transition-pos "$POSITION" \
            --transition-duration "$TRANSITION_DURATION" \
            --transition-angle "$ANGLE" \
            --filter "$FILTER" \
            --resize "$RESIZE" \
            --fill-color "$FILL_COLOR"

        echo "Wallpaper set to: ${IMAGE_PATHS[0]}"
        echo "Applied to all monitors"
    elif [ $NUM_OUTPUTS -eq 1 ]; then
        # Multiple images but only one monitor: use the first image
        swww img "${IMAGE_PATHS[0]}" \
            --transition-type "$TRANSITION_TYPE" \
            --transition-pos "$POSITION" \
            --transition-duration "$TRANSITION_DURATION" \
            --transition-angle "$ANGLE" \
            --filter "$FILTER" \
            --resize "$RESIZE" \
            --fill-color "$FILL_COLOR"

        echo "Wallpaper set to: ${IMAGE_PATHS[0]}"
        echo "Note: Multiple images provided but only one monitor detected"
    else
        # Multiple images and multiple monitors: assign one per monitor
        for i in "${!OUTPUTS[@]}"; do
            if [ $i -lt $NUM_IMAGES ]; then
                # Use corresponding image for this monitor
                IMG="${IMAGE_PATHS[$i]}"
            else
                # If we run out of images, use the last one
                IMG="${IMAGE_PATHS[-1]}"
            fi

            swww img "$IMG" \
                --outputs "${OUTPUTS[$i]}" \
                --transition-type "$TRANSITION_TYPE" \
                --transition-pos "$POSITION" \
                --transition-duration "$TRANSITION_DURATION" \
                --transition-angle "$ANGLE" \
                --filter "$FILTER" \
                --resize "$RESIZE" \
                --fill-color "$FILL_COLOR"

            echo "Monitor ${OUTPUTS[$i]}: $IMG"
        done

        echo "Wallpapers set for $NUM_OUTPUTS monitor(s)"
    fi

    echo "Effects applied: "
    echo "  - Transition: $TRANSITION_TYPE"
    echo "  - Duration: $TRANSITION_DURATION seconds"
    echo "  - Filter: $FILTER"
    echo "  - Position: $POSITION"
    echo "  - Angle: $ANGLE degrees"
    echo "  - Resize: $RESIZE"
    echo "  - Fill color: $FILL_COLOR"

elif [ "$DISPLAY_SERVER" = "x11" ]; then
    # Check if feh is installed
    if ! command -v feh &> /dev/null; then
        echo "Error: feh is not installed. Please install it to set wallpapers on X11."
        exit 1
    fi

    # Warn about unsupported features on X11
    if [ "$TRANSITION_TYPE" != "wave" ] || [ "$TRANSITION_DURATION" != "2" ] || \
       [ "$FILTER" != "Bilinear" ] || [ "$POSITION" != "0.5,0.5" ] || \
       [ "$ANGLE" != "30" ] || [ "$FILL_COLOR" != "000000" ]; then
        echo "Warning: Transitions and advanced effects are not supported on X11." >&2
        echo "         Using feh with basic settings only." >&2
    fi

    # Map resize method to feh's mode
    case "$RESIZE" in
        crop)
            FEH_MODE="--bg-fill"
            ;;
        fit)
            FEH_MODE="--bg-scale"
            ;;
        none)
            FEH_MODE="--bg-center"
            ;;
        *)
            FEH_MODE="--bg-scale"
            ;;
    esac

    NUM_IMAGES=${#IMAGE_PATHS[@]}

    if [ $NUM_IMAGES -eq 1 ]; then
        # Single image: apply to all monitors
        feh "$FEH_MODE" "${IMAGE_PATHS[0]}"
        echo "Wallpaper set to: ${IMAGE_PATHS[0]}"
        echo "Applied to all monitors"
    else
        # Multiple images: feh automatically assigns them to monitors in order
        # when you pass multiple images, feh uses Xinerama to distribute them
        feh "$FEH_MODE" "${IMAGE_PATHS[@]}"

        echo "Wallpapers set for multi-monitor setup:"
        for i in "${!IMAGE_PATHS[@]}"; do
            echo "  Monitor $((i+1)): ${IMAGE_PATHS[$i]}"
        done
    fi

    echo "Using feh on X11 (resize mode: $RESIZE)"
    echo "Note: Configuration saved to ~/.fehbg"
fi
