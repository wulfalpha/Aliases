#!/usr/bin/env bash

# Show usage information
usage() {
    echo "Usage: $0 [OPTIONS] [/path/to/image.jpg]"
    echo "Options:"
    echo "  -t, --transition TYPE   Set transition type (simple, wipe, wave, grow, outer, any)"
    echo "  -d, --duration SECONDS  Set transition duration in seconds"
    echo "  -f, --filter FILTER     Apply filter (none, blur, pixel, greyscale, saturate)"
    echo "  -p, --position X,Y      Set transition position (0.0,0.0 is top left, 1.0,1.0 is bottom right)"
    echo "  -a, --angle DEGREES     Set transition angle in degrees"
    echo "  -r, --resize METHOD     Set resize method (crop, fit, none)"
    echo "  -c, --color HEX         Set fill color (hex format e.g., '#000000')"
    echo "  -R, --random            Select a random wallpaper from $HOME/wallpapers"
    echo "  -h, --help              Show this help message"
    exit 1
}

# Default values
TRANSITION_TYPE="wave"
TRANSITION_DURATION=2
FILTER="Bilinear"
POSITION="0.5,0.5"
ANGLE=30
RESIZE="fit"
FILL_COLOR="#000000"
RANDOM_WALLPAPER=false

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
            IMAGE_PATH="$1"
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
    IMAGE_FILES=($(find "$WALLPAPER_DIR" -type f \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" -o -name "*.gif" \) | sort))
    
    # Check if any images were found
    if [ ${#IMAGE_FILES[@]} -eq 0 ]; then
        echo "Error: No image files found in $WALLPAPER_DIR"
        exit 1
    fi
    
    # Pick a random image
    RANDOM_INDEX=$((RANDOM % ${#IMAGE_FILES[@]}))
    IMAGE_PATH=${IMAGE_FILES[$RANDOM_INDEX]}
    
    echo "Randomly selected: $IMAGE_PATH"
fi

# Check if an image path was provided or selected
if [ -z "$IMAGE_PATH" ]; then
    echo "Error: Please provide the path to an image or use --random flag."
    usage
fi

# Verify that the file exists
if [ ! -f "$IMAGE_PATH" ]; then
    echo "Error: The file '$IMAGE_PATH' does not exist."
    exit 1
fi

# Initialize swww-daemon if not already running
if ! pgrep -x swww-daemon >/dev/null; then
    swww-daemon
fi

# Set the wallpaper with the specified effects
swww img "$IMAGE_PATH" \
    --transition-type "$TRANSITION_TYPE" \
    --transition-pos "$POSITION" \
    --transition-duration "$TRANSITION_DURATION" \
    --transition-angle "$ANGLE" \
    --filter "$FILTER" \
    --resize "$RESIZE" \
    --fill-color "$FILL_COLOR"

echo "Wallpaper set to: $IMAGE_PATH"
echo "Effects applied: "
echo "  - Transition: $TRANSITION_TYPE"
echo "  - Duration: $TRANSITION_DURATION seconds"
echo "  - Filter: $FILTER"
echo "  - Position: $POSITION"
echo "  - Angle: $ANGLE degrees"
echo "  - Resize: $RESIZE"
echo "  - Fill color: $FILL_COLOR"
