#!/bin/bash
# set_wallpaper.sh - A utility script to set wallpaper using variety
# Usage: set_wallpaper.sh [OPTIONS] /path/to/image.jpg

# Log file location
LOG_FILE="/tmp/set_wallpaper.log"

# Function to display help
show_help() {
  echo "Usage: $(basename "$0") [OPTIONS] IMAGE_PATH [IMAGE_PATH2 ...]"
  echo "Set desktop wallpaper using variety."
  echo
  echo "Options:"
  echo "  -h, --help              Show this help message and exit"
  echo "  -q, --quiet             Suppress log output"
  echo "  -r, --random            Pick a random image from provided files"
  echo "  -f, --favorite          Copy current wallpaper to Favorites"
  echo "  -m, --move-favorite     Move current wallpaper to Favorites"
  echo "  -p, --profile PROFILE   Use specific variety profile"
  echo "  -e, --effects           Toggle effects for the current image"
  echo "  -s, --set-option OPT    Set variety configuration option (can be used multiple times)"
  echo "  -v, --verbose           Show verbose output"
  echo
  echo "Examples:"
  echo "  $(basename "$0") ~/Pictures/wallpaper.jpg"
  echo "  $(basename "$0") -r ~/Pictures/*.jpg"
  echo "  $(basename "$0") -f -s icon=Dark -s clock_enabled=True ~/Pictures/wallpaper.jpg"
}

# Process options
QUIET=false
RANDOM_MODE=false
FAVORITE=false
MOVE_FAVORITE=false
TOGGLE_EFFECTS=false
PROFILE=""
SET_OPTIONS=()
VERBOSE=""
IMAGES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      show_help
      exit 0
      ;;
    -q|--quiet)
      QUIET=true
      shift
      ;;
    -r|--random)
      RANDOM_MODE=true
      shift
      ;;
    -f|--favorite)
      FAVORITE=true
      shift
      ;;
    -m|--move-favorite)
      MOVE_FAVORITE=true
      shift
      ;;
    -p|--profile)
      PROFILE="$2"
      shift 2
      ;;
    -e|--effects)
      TOGGLE_EFFECTS=true
      shift
      ;;
    -s|--set-option)
      SET_OPTIONS+=("$2")
      shift 2
      ;;
    -v|--verbose)
      VERBOSE="-v"
      shift
      ;;
    -*)
      echo "Unknown option: $1"
      show_help
      exit 1
      ;;
    *)
      IMAGES+=("$1")
      shift
      ;;
  esac
done

# Log function
log() {
  if [ "$QUIET" = false ]; then
    echo "$1" >> "$LOG_FILE"
  fi
}

# Check if variety is installed
if ! command -v variety &> /dev/null; then
  log "Error: variety is not installed"
  echo "Error: variety is not installed. Please install variety first."
  exit 1
fi

# Build base variety command with common options
VARIETY_CMD=(variety)

if [ -n "$PROFILE" ]; then
  VARIETY_CMD+=(--profile "$PROFILE")
fi

if [ -n "$VERBOSE" ]; then
  VARIETY_CMD+=($VERBOSE)
fi

# Apply any set-options first (these change the configuration)
for opt in "${SET_OPTIONS[@]}"; do
  key="${opt%%=*}"
  value="${opt#*=}"

  log "Setting variety option: $key = $value"
  "${VARIETY_CMD[@]}" --set-option "$key $value" >> "$LOG_FILE" 2>&1

  # Check if the command succeeded
  if [ $? -ne 0 ]; then
    log "Failed to set option: $key = $value"
    echo "Failed to set option: $key = $value"
  fi
done

# Handle multiple images with random selection
if [ ${#IMAGES[@]} -gt 0 ]; then
  # Filter out non-existent files
  VALID_IMAGES=()
  for img in "${IMAGES[@]}"; do
    if [ -f "$img" ]; then
      VALID_IMAGES+=("$img")
    else
      log "Warning: File does not exist: $img"
      echo "Warning: File does not exist: $img"
    fi
  done

  if [ ${#VALID_IMAGES[@]} -eq 0 ]; then
    log "Error: No valid image files found"
    echo "Error: No valid image files found"
    exit 1
  fi

  # Select random image if requested
  if [ "$RANDOM_MODE" = true ] && [ ${#VALID_IMAGES[@]} -gt 1 ]; then
    # Get a random index
    RANDOM_INDEX=$((RANDOM % ${#VALID_IMAGES[@]}))
    SELECTED_IMAGE="${VALID_IMAGES[$RANDOM_INDEX]}"
    log "Randomly selected image: $SELECTED_IMAGE"
  else
    # Just use the first image
    SELECTED_IMAGE="${VALID_IMAGES[0]}"

    # Provide information if multiple images were supplied without random flag
    if [ ${#VALID_IMAGES[@]} -gt 1 ]; then
      log "Multiple images provided but not using random mode. Using first image: $SELECTED_IMAGE"
      echo "Multiple images provided. Using only the first one. Add -r to pick randomly."

      # Add the other images to variety's queue (optional feature)
      for img in "${VALID_IMAGES[@]:1}"; do
        log "Adding to variety queue: $img"
        "${VARIETY_CMD[@]}" "$img" >> "$LOG_FILE" 2>&1
      done
    fi
  fi

  # Set the wallpaper
  log "Setting wallpaper: $SELECTED_IMAGE"
  "${VARIETY_CMD[@]}" --set "$SELECTED_IMAGE" >> "$LOG_FILE" 2>&1

  # Check if the command succeeded
  if [ $? -ne 0 ]; then
    log "Failed to set wallpaper"
    echo "Failed to set wallpaper. Check $LOG_FILE for details."
    exit 1
  else
    log "Wallpaper set successfully"
    echo "Wallpaper set successfully: $SELECTED_IMAGE"
  fi
else
  # No images provided - we can still handle other commands on the current wallpaper
  log "No images provided, operating on current wallpaper"
fi

# Handle favorite/move-to-favorite operations
if [ "$FAVORITE" = true ]; then
  log "Marking current wallpaper as favorite"
  "${VARIETY_CMD[@]}" --favorite >> "$LOG_FILE" 2>&1

  if [ $? -ne 0 ]; then
    log "Failed to mark as favorite"
    echo "Failed to mark as favorite. Check $LOG_FILE for details."
  else
    echo "Current wallpaper marked as favorite"
  fi
fi

if [ "$MOVE_FAVORITE" = true ]; then
  log "Moving current wallpaper to favorites"
  "${VARIETY_CMD[@]}" --move-to-favorites >> "$LOG_FILE" 2>&1

  if [ $? -ne 0 ]; then
    log "Failed to move to favorites"
    echo "Failed to move to favorites. Check $LOG_FILE for details."
  else
    echo "Current wallpaper moved to favorites"
  fi
fi

# Toggle effects if requested
if [ "$TOGGLE_EFFECTS" = true ]; then
  log "Toggling effects for current wallpaper"
  "${VARIETY_CMD[@]}" --toggle-no-effects >> "$LOG_FILE" 2>&1

  if [ $? -ne 0 ]; then
    log "Failed to toggle effects"
    echo "Failed to toggle effects. Check $LOG_FILE for details."
  else
    echo "Effects toggled for current wallpaper"
  fi
fi

exit 0
