#!/usr/bin/env bash

# Configuration
HISTORY_FILE="$HOME/.cache/wallpaper_history"
FAVORITES_FILE="$HOME/.cache/wallpaper_favorites"
MAX_HISTORY_SIZE=50

# Show usage information
usage() {
    echo "Usage: $0 [OPTIONS] [/path/to/image1.jpg] [/path/to/image2.jpg] ..."
    echo "Options:"
    echo "  -t, --transition TYPE   Set transition type (simple, wipe, wave, grow, outer, any)"
    echo "  -d, --duration SECONDS  Set transition duration in seconds"
    echo "  -f, --filter FILTER     Apply swww filter (Lanczos3, Mitchell, CatmullRom, Nearest, Triangle)"
    echo "  -p, --position X,Y      Set transition position (0.0,0.0 is top left, 1.0,1.0 is bottom right)"
    echo "  -a, --angle DEGREES     Set transition angle in degrees"
    echo "  -r, --resize METHOD     Set resize method (crop, fit, no)"
    echo "  -c, --color HEX         Set fill color (hex format e.g., '000000')"
    echo "  -R, --random            Select a random wallpaper from $HOME/wallpapers"
    echo "  -I, --history           Show wallpaper history (most recent first)"
    echo "  -s, --select INDEX      Select wallpaper from history by index (1 = most recent)"
    echo "  -S, --search PATTERN    Search and select from history matching pattern"
    echo "  -C, --clear-history     Clear wallpaper history"
    echo "  -u, --undo              Restore the previous wallpaper from history"
    echo "  --current               Show current wallpaper path"
    echo "  --favorite              Mark current wallpaper as favorite"
    echo "  --favorites             Show list of favorite wallpapers"
    echo "  --random-favorite       Set a random wallpaper from favorites"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "Multiple Images:"
    echo "  - Single image: Applied to all monitors"
    echo "  - Multiple images: Each image applied to a different monitor in order"
    echo ""
    echo "Examples:"
    echo "  $0 wallpaper.jpg                    # Set same wallpaper on all monitors"
    echo "  $0 wall1.jpg wall2.jpg              # Set wall1 on first monitor, wall2 on second"
    echo "  $0 -R -t wave                       # Random wallpaper with wave transition"
    exit 1
}

# Initialize history file if it doesn't exist
init_history() {
    if [ ! -f "$HISTORY_FILE" ]; then
        mkdir -p "$(dirname "$HISTORY_FILE")"
        touch "$HISTORY_FILE"
    fi
}

# Add wallpaper to history
add_to_history() {
    local wallpaper_path="$1"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Initialize history file
    init_history

    # Create temporary file for new history
    local temp_file="${HISTORY_FILE}.tmp"

    # Add new entry at the beginning
    echo "${timestamp}|${wallpaper_path}" > "$temp_file"

    # Append existing history (excluding duplicates of the same path)
    # Use grep -F for literal string matching to avoid regex issues with special characters
    if [ -f "$HISTORY_FILE" ]; then
        grep -vF "|${wallpaper_path}" "$HISTORY_FILE" | head -n $((MAX_HISTORY_SIZE - 1)) >> "$temp_file"
    fi

    # Replace old history with new
    mv "$temp_file" "$HISTORY_FILE"
}

# Show wallpaper history
show_history() {
    init_history

    if [ ! -s "$HISTORY_FILE" ]; then
        echo "No wallpaper history found."
        return 1
    fi

    echo "Wallpaper History (most recent first):"
    echo "======================================="

    local index=1
    while IFS='|' read -r timestamp wallpaper_path; do
        # Check if file still exists
        if [ -f "$wallpaper_path" ]; then
            local basename
            local dirname
            basename=$(basename "$wallpaper_path")
            dirname=$(dirname "$wallpaper_path")
            printf "%3d. [%s] %s\n" "$index" "$timestamp" "$basename"
            printf "     Path: %s\n" "$dirname"
        else
            printf "%3d. [%s] %s (FILE NOT FOUND)\n" "$index" "$timestamp" "$wallpaper_path"
        fi
        echo ""
        ((index++))
    done < "$HISTORY_FILE"
}

# Get wallpaper from history by index
get_from_history() {
    local index="$1"

    init_history

    if [ ! -s "$HISTORY_FILE" ]; then
        echo "Error: No wallpaper history found."
        return 1
    fi

    # Validate index
    if ! [[ "$index" =~ ^[0-9]+$ ]] || [ "$index" -lt 1 ]; then
        echo "Error: Invalid index. Please provide a positive number."
        return 1
    fi

    # Get the wallpaper path at the specified index
    local wallpaper_entry
    wallpaper_entry=$(sed -n "${index}p" "$HISTORY_FILE")

    if [ -z "$wallpaper_entry" ]; then
        echo "Error: No wallpaper found at index $index"
        return 1
    fi

    # Extract the path from the entry
    local wallpaper_path="${wallpaper_entry#*|}"

    if [ ! -f "$wallpaper_path" ]; then
        echo "Error: Wallpaper file no longer exists: $wallpaper_path"
        return 1
    fi

    echo "$wallpaper_path"
    return 0
}

# Search wallpaper history
search_history() {
    local pattern="$1"

    init_history

    if [ ! -s "$HISTORY_FILE" ]; then
        echo "No wallpaper history found."
        return 1
    fi

    echo "Search results for '$pattern':"
    echo "=============================="

    local index=1
    local found=false
    while IFS='|' read -r timestamp wallpaper_path; do
        if [[ "$wallpaper_path" =~ $pattern ]]; then
            found=true
            if [ -f "$wallpaper_path" ]; then
                local basename
                basename=$(basename "$wallpaper_path")
                printf "%3d. [%s] %s\n" "$index" "$timestamp" "$basename"
                printf "     Path: %s\n" "$wallpaper_path"
            else
                printf "%3d. [%s] %s (FILE NOT FOUND)\n" "$index" "$timestamp" "$wallpaper_path"
            fi
            echo ""
        fi
        ((index++))
    done < "$HISTORY_FILE"

    if [ "$found" = false ]; then
        echo "No wallpapers found matching '$pattern'"
        return 1
    fi
}

# Clear wallpaper history
clear_history() {
    if [ -f "$HISTORY_FILE" ]; then
        true > "$HISTORY_FILE"
        echo "Wallpaper history cleared."
    else
        echo "No history file to clear."
    fi
}

# Get current wallpaper (if possible)
get_current_wallpaper() {
    # Try to get from swww query
    if command -v swww >/dev/null 2>&1; then
        local swww_output
        swww_output=$(swww query 2>/dev/null)
        if [ -n "$swww_output" ]; then
            # Extract image path from swww query output
            # swww query outputs: "eDP-1: image: /path/to/wallpaper.jpg"
            echo "$swww_output" | grep -oP 'image: \K.*' | head -1
        fi
    fi
}

# Show current wallpaper
show_current_wallpaper() {
    local current
    current=$(get_current_wallpaper)
    if [ -n "$current" ]; then
        echo "Current wallpaper: $current"
        if [ -f "$current" ]; then
            echo "File exists: Yes"
            echo "Size: $(du -h "$current" | cut -f1)"
        else
            echo "File exists: No (may have been deleted)"
        fi
    else
        echo "Could not determine current wallpaper"
        return 1
    fi
}

# Safe notify-send wrapper (gracefully handles missing notify-send)
safe_notify() {
    if command -v notify-send >/dev/null 2>&1; then
        notify-send "$@"
    fi
}

# Add wallpaper to favorites
add_to_favorites() {
    local wallpaper_path="$1"

    # Initialize favorites file
    if [ ! -f "$FAVORITES_FILE" ]; then
        mkdir -p "$(dirname "$FAVORITES_FILE")"
        touch "$FAVORITES_FILE"
    fi

    # Check if already in favorites
    if grep -Fxq "$wallpaper_path" "$FAVORITES_FILE"; then
        echo "This wallpaper is already in favorites."
        return 0
    fi

    # Add to favorites
    echo "$wallpaper_path" >> "$FAVORITES_FILE"
    echo "Added to favorites: $wallpaper_path"
    safe_notify "Wallpaper Favorite" "Added $(basename "$wallpaper_path") to favorites"
}

# Show favorite wallpapers
show_favorites() {
    if [ ! -f "$FAVORITES_FILE" ] || [ ! -s "$FAVORITES_FILE" ]; then
        echo "No favorite wallpapers found."
        return 1
    fi

    echo "Favorite Wallpapers:"
    echo "==================="
    echo ""

    local index=1
    while IFS= read -r wallpaper_path; do
        if [ -f "$wallpaper_path" ]; then
            local basename
            basename=$(basename "$wallpaper_path")
            printf "%3d. %s\n" "$index" "$basename"
            printf "     Path: %s\n" "$wallpaper_path"
        else
            printf "%3d. %s (FILE NOT FOUND)\n" "$index" "$wallpaper_path"
        fi
        echo ""
        ((index++))
    done < "$FAVORITES_FILE"
}

# Get random favorite
get_random_favorite() {
    if [ ! -f "$FAVORITES_FILE" ] || [ ! -s "$FAVORITES_FILE" ]; then
        echo "Error: No favorite wallpapers found."
        return 1
    fi

    # Read favorites into array, filtering out missing files
    local favorites=()
    while IFS= read -r wallpaper_path; do
        if [ -f "$wallpaper_path" ]; then
            favorites+=("$wallpaper_path")
        fi
    done < "$FAVORITES_FILE"

    if [ ${#favorites[@]} -eq 0 ]; then
        echo "Error: No valid favorite wallpapers found."
        return 1
    fi

    # Pick random favorite
    local random_index=$((RANDOM % ${#favorites[@]}))
    echo "${favorites[$random_index]}"
}

# Detect session type
detect_session_type() {
    if [ -n "$WAYLAND_DISPLAY" ]; then
        echo "wayland"
    elif [ -n "$DISPLAY" ]; then
        echo "x11"
    else
        echo "unknown"
    fi
}

# Default values
TRANSITION_TYPE="wave"
TRANSITION_DURATION=2
FILTER="Lanczos3"
POSITION="0.5,0.5"
ANGLE=30
RESIZE="crop"
FILL_COLOR="000000"
RANDOM_WALLPAPER=false
SHOW_HISTORY=false
SELECT_INDEX=""
SEARCH_PATTERN=""
CLEAR_HISTORY=false
SHOW_CURRENT=false
UNDO_WALLPAPER=false
MARK_FAVORITE=false
SHOW_FAVORITES=false
RANDOM_FAVORITE=false
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
        -I|--history)
            SHOW_HISTORY=true
            shift
            ;;
        -s|--select)
            SELECT_INDEX="$2"
            shift 2
            ;;
        -S|--search)
            SEARCH_PATTERN="$2"
            shift 2
            ;;
        -C|--clear-history)
            CLEAR_HISTORY=true
            shift
            ;;
        -u|--undo)
            UNDO_WALLPAPER=true
            shift
            ;;
        --current)
            SHOW_CURRENT=true
            shift
            ;;
        --favorite)
            MARK_FAVORITE=true
            shift
            ;;
        --favorites)
            SHOW_FAVORITES=true
            shift
            ;;
        --random-favorite)
            RANDOM_FAVORITE=true
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

# Handle special actions first
if [ "$CLEAR_HISTORY" = true ]; then
    clear_history
    exit 0
fi

if [ "$SHOW_HISTORY" = true ]; then
    show_history
    exit 0
fi

if [ "$SHOW_CURRENT" = true ]; then
    show_current_wallpaper
    exit 0
fi

if [ "$SHOW_FAVORITES" = true ]; then
    show_favorites
    exit 0
fi

if [ "$MARK_FAVORITE" = true ]; then
    # Get current wallpaper and mark as favorite
    current=$(get_current_wallpaper)
    if [ -z "$current" ]; then
        echo "Error: Could not determine current wallpaper to mark as favorite."
        exit 1
    fi
    add_to_favorites "$current"
    exit 0
fi

if [ -n "$SEARCH_PATTERN" ]; then
    search_history "$SEARCH_PATTERN"
    exit 0
fi

# Handle undo (restore previous wallpaper from history)
if [ "$UNDO_WALLPAPER" = true ]; then
    init_history

    if [ ! -s "$HISTORY_FILE" ]; then
        echo "Error: No wallpaper history found. Cannot undo."
        exit 1
    fi

    # Get the second entry in history (index 2)
    # Index 1 is current, index 2 is previous
    if ! PREVIOUS_PATH=$(get_from_history 2); then
        echo "Error: No previous wallpaper in history to restore."
        exit 1
    fi

    IMAGE_PATHS=("$PREVIOUS_PATH")
    echo "Restoring previous wallpaper: $PREVIOUS_PATH"
fi

# Handle selecting from history
if [ -n "$SELECT_INDEX" ]; then
    if ! SELECTED_PATH=$(get_from_history "$SELECT_INDEX"); then
        exit 1
    fi
    IMAGE_PATHS=("$SELECTED_PATH")
    echo "Selected from history: $SELECTED_PATH"
fi

# Handle random favorite wallpaper selection
if [ "$RANDOM_FAVORITE" = true ] && [ ${#IMAGE_PATHS[@]} -eq 0 ]; then
    if ! FAVORITE_PATH=$(get_random_favorite); then
        exit 1
    fi
    IMAGE_PATHS=("$FAVORITE_PATH")
    echo "Randomly selected from favorites: $FAVORITE_PATH"
fi

# Handle random wallpaper selection
if [ "$RANDOM_WALLPAPER" = true ] && [ ${#IMAGE_PATHS[@]} -eq 0 ]; then
    WALLPAPER_DIR="$HOME/wallpapers"

    # Check if wallpaper directory exists
    if [ ! -d "$WALLPAPER_DIR" ]; then
        echo "Error: Wallpaper directory does not exist: $WALLPAPER_DIR"
        exit 1
    fi

    # Get list of image files (properly handling filenames with spaces)
    mapfile -t IMAGE_FILES < <(find "$WALLPAPER_DIR" -type f \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" -o -name "*.gif" -o -name "*.webp" \))

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
    echo "Error: Please provide the path to an image, use --random flag, or select from history."
    usage
fi

# Verify that all files exist and are valid images
for img in "${IMAGE_PATHS[@]}"; do
    if [ ! -f "$img" ]; then
        echo "Error: The file '$img' does not exist."
        exit 1
    fi

    # Check if file is actually an image
    if command -v file >/dev/null 2>&1; then
        if ! file --mime-type "$img" | grep -q 'image/'; then
            echo "Error: The file '$img' is not a valid image file."
            echo "File type: $(file --mime-type -b "$img")"
            exit 1
        fi
    fi
done

# Detect session type
SESSION_TYPE=$(detect_session_type)

if [ "$SESSION_TYPE" = "wayland" ]; then
    # Wayland session - use swww
    if ! command -v swww >/dev/null 2>&1; then
        echo "Error: swww is not installed. Please install it first."
        echo "Visit: https://github.com/LGFae/swww"
        exit 1
    fi

    # Initialize swww-daemon if not already running
    if ! pgrep -x swww-daemon >/dev/null; then
        echo "Starting swww daemon..."
        swww-daemon &

        # Wait for daemon to initialize properly
        daemon_ready=false
        for i in {1..20}; do
            if swww query >/dev/null 2>&1; then
                daemon_ready=true
                break
            fi
            sleep 0.1
        done

        if [ "$daemon_ready" = false ]; then
            echo "Error: swww daemon failed to start properly"
            exit 1
        fi

        echo "swww daemon started successfully"
    fi

    # Get list of monitors
    mapfile -t MONITORS < <(swww query 2>/dev/null | awk -F': ' '{print $2}' | sort)

    if [ ${#MONITORS[@]} -eq 0 ]; then
        echo "Error: No monitors detected by swww"
        exit 1
    fi

    echo "Detected ${#MONITORS[@]} monitor(s): ${MONITORS[*]}"

    # Determine how to apply wallpapers
    if [ ${#IMAGE_PATHS[@]} -eq 1 ]; then
        # Single image - apply to all monitors
        echo "Setting single wallpaper on all monitors..."
        if swww img "${IMAGE_PATHS[0]}" \
            --transition-type "$TRANSITION_TYPE" \
            --transition-pos "$POSITION" \
            --transition-duration "$TRANSITION_DURATION" \
            --transition-angle "$ANGLE" \
            --filter "$FILTER" \
            --resize "$RESIZE" \
            --fill-color "$FILL_COLOR"; then
            add_to_history "${IMAGE_PATHS[0]}"
            safe_notify -i "${IMAGE_PATHS[0]}" "Wallpaper Set (Wayland)" "Applied $(basename "${IMAGE_PATHS[0]}") to all monitors"
            echo "✓ Wallpaper set to: ${IMAGE_PATHS[0]}"
        else
            safe_notify -u critical "Wallpaper Error" "Failed to set wallpaper on Wayland"
            echo "Error: Failed to set wallpaper"
            exit 1
        fi
    else
        # Multiple images - apply one per monitor
        echo "Setting different wallpaper on each monitor..."
        SUCCESS=true
        for i in "${!MONITORS[@]}"; do
            if [ "$i" -lt ${#IMAGE_PATHS[@]} ]; then
                IMG="${IMAGE_PATHS[$i]}"
                MON="${MONITORS[$i]}"
                echo "  Monitor $MON: $(basename "$IMG")"

                if swww img "$IMG" \
                    --outputs "$MON" \
                    --transition-type "$TRANSITION_TYPE" \
                    --transition-pos "$POSITION" \
                    --transition-duration "$TRANSITION_DURATION" \
                    --transition-angle "$ANGLE" \
                    --filter "$FILTER" \
                    --resize "$RESIZE" \
                    --fill-color "$FILL_COLOR"; then
                    add_to_history "$IMG"
                else
                    SUCCESS=false
                fi
            else
                echo "  Monitor ${MONITORS[$i]}: No image provided, keeping current wallpaper"
            fi
        done

        if [ "$SUCCESS" = true ]; then
            safe_notify "Wallpaper Set (Wayland)" "Applied ${#IMAGE_PATHS[@]} wallpaper(s) to ${#MONITORS[@]} monitor(s)"
            echo "✓ Wallpapers set successfully"
        else
            safe_notify -u critical "Wallpaper Error" "Some wallpapers failed to set on Wayland"
            echo "Error: Some wallpapers failed to set"
            exit 1
        fi
    fi

    echo "Effects applied:"
    echo "  - Transition: $TRANSITION_TYPE"
    echo "  - Duration: $TRANSITION_DURATION seconds"
    echo "  - Filter: $FILTER"
    echo "  - Position: $POSITION"
    echo "  - Angle: $ANGLE degrees"
    echo "  - Resize: $RESIZE"
    echo "  - Fill color: $FILL_COLOR"

elif [ "$SESSION_TYPE" = "x11" ]; then
    # X11 session - use feh
    if ! command -v feh >/dev/null 2>&1; then
        echo "Error: feh is not installed. Please install it first."
        exit 1
    fi

    echo "Setting wallpaper with feh (X11)..."

    # feh can handle multiple images automatically
    if feh --bg-scale "${IMAGE_PATHS[@]}"; then
        # Add all images to history
        for img in "${IMAGE_PATHS[@]}"; do
            add_to_history "$img"
        done

        if [ ${#IMAGE_PATHS[@]} -eq 1 ]; then
            safe_notify -i "${IMAGE_PATHS[0]}" "Wallpaper Set (X11)" "Applied $(basename "${IMAGE_PATHS[0]}")"
            echo "✓ Wallpaper set to: ${IMAGE_PATHS[0]}"
        else
            safe_notify "Wallpaper Set (X11)" "Applied ${#IMAGE_PATHS[@]} wallpaper(s)"
            echo "✓ Wallpapers set successfully"
            for img in "${IMAGE_PATHS[@]}"; do
                echo "  - $(basename "$img")"
            done
        fi
    else
        safe_notify -u critical "Wallpaper Error" "Failed to set wallpaper on X11"
        echo "Error: Failed to set wallpaper"
        exit 1
    fi

else
    echo "Error: Could not detect session type (neither Wayland nor X11)"
    safe_notify -u critical "Wallpaper Error" "Unknown session type"
    exit 1
fi
