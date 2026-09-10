#!/usr/bin/env bash

# Configuration
HISTORY_FILE="$HOME/.cache/wallpaper_history"
FAVORITES_FILE="$HOME/.cache/wallpaper_favorites"
STATE_FILE="$HOME/.cache/wallpaper_state"
MAX_HISTORY_SIZE=50
WALLPAPER_DIR="${WALLPAPER_DIR:-$HOME/wallstreet}"

# Show usage information (exit code defaults to 1; pass 0 for explicit --help)
usage() {
    echo "Usage: $0 [OPTIONS] [/path/to/image1.jpg] [/path/to/image2.jpg] ..."
    echo "Options:"
    echo "  -t, --transition TYPE   Set transition type (none, simple, fade, left, right, top,"
    echo "                          bottom, wipe, wave, grow, center, any, outer, random)"
    echo "  -d, --duration SECONDS  Set transition duration in seconds"
    echo "  -f, --filter FILTER     Scaling filter (Lanczos3, Mitchell, CatmullRom, Bilinear, Nearest)"
    echo "  -p, --position X,Y      Set transition position (0.0,0.0 is top left, 1.0,1.0 is bottom right)"
    echo "  -a, --angle DEGREES     Set transition angle in degrees"
    echo "  -r, --resize METHOD     Set resize method (crop, fit, stretch, no)"
    echo "  -c, --color HEX         Set fill color (hex format e.g., '000000')"
    echo "  -o, --outputs LIST      Only set the wallpaper on these monitors"
    echo "                          (comma separated, e.g. 'DP-1,HDMI-A-1')"
    echo "  -R, --random            Select a random wallpaper from \$WALLPAPER_DIR ($WALLPAPER_DIR)"
    echo "  -I, --history           Show wallpaper history (most recent first)"
    echo "  -s, --select INDEX      Select wallpaper from history by index (1 = most recent)"
    echo "  -S, --search PATTERN    List history entries matching pattern"
    echo "  --search-select PATTERN Interactively select a matching history entry"
    echo "  -C, --clear-history     Clear wallpaper history"
    echo "  -u, --undo              Restore the previous per-monitor layout"
    echo "  --current               Show the current wallpaper on every monitor"
    echo "  --favorite              Mark every current wallpaper as favorite"
    echo "  --favorites             Show list of favorite wallpapers"
    echo "  --random-favorite       Set a random wallpaper from favorites"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "Multiple Images:"
    echo "  - Single image: Applied to all monitors"
    echo "  - Multiple images: Each image applied to a different monitor, in the order"
    echo "    monitors are reported by the backend, sorted by connector name (e.g."
    echo "    DP-1 before HDMI-A-1 before eDP-1) -- not by physical arrangement."
    echo ""
    echo "Examples:"
    echo "  $0 wallpaper.jpg                    # Set same wallpaper on all monitors"
    echo "  $0 wall1.jpg wall2.jpg              # Set wall1 on first monitor, wall2 on second"
    echo "  $0 -R -t wave                       # Random wallpaper with wave transition"
    exit "${1:-1}"
}

# Require that an option was given a value; call as: need_arg "$@"
need_arg() {
    if [ $# -lt 2 ]; then
        echo "Error: option '$1' requires an argument." >&2
        exit 1
    fi
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

    # Initialize history file and lock the complete read-modify-write cycle.
    init_history

    local lock_fd=""
    if command -v flock >/dev/null 2>&1; then
        exec {lock_fd}>"${HISTORY_FILE}.lock" || return 1
        flock "$lock_fd" || return 1
    fi

    # Create temporary file for new history. Use mktemp so that two concurrent
    # runs (e.g. a timer and a manual invocation) cannot clobber each other.
    local temp_file
    if ! temp_file=$(mktemp "${HISTORY_FILE}.XXXXXX"); then
        [ -z "$lock_fd" ] || exec {lock_fd}>&-
        return 1
    fi

    # Add new entry at the beginning
    echo "${timestamp}|${wallpaper_path}" > "$temp_file"

    # Append existing history, dropping any earlier entry for this exact path.
    # Compare the whole path field rather than substring-matching, otherwise
    # setting "/w/pic.jpg" would also evict an unrelated "/w/pic.jpg.bak".
    if [ -f "$HISTORY_FILE" ]; then
        awk -v p="$wallpaper_path" '
            { i = index($0, "|") }
            i == 0 || substr($0, i + 1) != p
        ' "$HISTORY_FILE" | head -n $((MAX_HISTORY_SIZE - 1)) >> "$temp_file"
    fi

    # Replace old history with new
    mv "$temp_file" "$HISTORY_FILE"
    [ -z "$lock_fd" ] || exec {lock_fd}>&-
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

    # NOTE: this function's stdout is captured by callers, so every diagnostic
    # here must go to stderr or it will be swallowed instead of shown.
    if [ ! -s "$HISTORY_FILE" ]; then
        echo "Error: No wallpaper history found." >&2
        return 1
    fi

    # Validate index
    if ! [[ "$index" =~ ^[0-9]+$ ]] || [ "$index" -lt 1 ]; then
        echo "Error: Invalid index '$index'. Please provide a positive number." >&2
        return 1
    fi

    # Get the wallpaper path at the specified index
    local wallpaper_entry
    wallpaper_entry=$(sed -n "${index}p" "$HISTORY_FILE")

    if [ -z "$wallpaper_entry" ]; then
        echo "Error: No wallpaper found at index $index" >&2
        return 1
    fi

    # Extract the path from the entry
    local wallpaper_path="${wallpaper_entry#*|}"

    if [ ! -f "$wallpaper_path" ]; then
        echo "Error: Wallpaper file no longer exists: $wallpaper_path" >&2
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

# Interactively select a wallpaper from matching history entries. The selected
# path is written to stdout; all UI goes through the controlling terminal.
select_from_search() {
    local pattern="$1"
    local -a indexes=() labels=() paths=()
    local index=1 timestamp wallpaper_path

    init_history
    while IFS='|' read -r timestamp wallpaper_path; do
        if [[ "$wallpaper_path" =~ $pattern ]] && [ -f "$wallpaper_path" ]; then
            indexes+=("$index")
            paths+=("$wallpaper_path")
            labels+=("$index | $timestamp | $wallpaper_path")
        fi
        ((index++))
    done < "$HISTORY_FILE"

    if [ ${#paths[@]} -eq 0 ]; then
        echo "Error: No existing wallpapers match '$pattern'." >&2
        return 1
    fi

    local selection="" selected_index=""
    if command -v fzf >/dev/null 2>&1 && [ -r /dev/tty ]; then
        selection=$(printf '%s\n' "${labels[@]}" | fzf --prompt="Wallpaper> ") || return 1
        selected_index=${selection%% *}
    elif [ -r /dev/tty ]; then
        printf 'Matching wallpapers:\n' >/dev/tty
        printf '  %s\n' "${labels[@]}" >/dev/tty
        printf 'Select a history index: ' >/dev/tty
        IFS= read -r selected_index </dev/tty || return 1
    else
        echo "Error: --search-select requires an interactive terminal." >&2
        return 1
    fi

    for index in "${!indexes[@]}"; do
        if [ "${indexes[$index]}" = "$selected_index" ]; then
            printf '%s\n' "${paths[$index]}"
            return 0
        fi
    done

    echo "Error: '$selected_index' is not one of the matching history indexes." >&2
    return 1
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

# Wayland backend. Upstream renamed swww -> awww in 0.12.0 (the binaries are
# now awww/awww-daemon, with no swww compatibility symlink), so prefer awww and
# fall back to swww for machines still on the old release.
WP_CLI=""
WP_DAEMON=""
detect_wayland_backend() {
    if [ -n "$WP_CLI" ]; then
        return 0
    fi
    if command -v awww >/dev/null 2>&1; then
        WP_CLI="awww"
        WP_DAEMON="awww-daemon"
    elif command -v swww >/dev/null 2>&1; then
        WP_CLI="swww"
        WP_DAEMON="swww-daemon"
    else
        return 1
    fi
    return 0
}

# List connected output names, one per line.
get_monitors() {
    detect_wayland_backend || return 1

    # awww query prints "NAMESPACE: OUTPUT: WxH, scale: N, currently displaying: ..."
    # while swww query omits the leading namespace field. Splitting on ": " and
    # taking field 2 yields the *resolution* in both cases, not the output name.
    if [ "$WP_CLI" = "awww" ]; then
        # JSON is exact and namespace-safe; added in awww 0.12.0.
        if command -v jq >/dev/null 2>&1; then
            "$WP_CLI" query -j 2>/dev/null | jq -r '.[][].name'
            return
        fi
        # Fallback: strip the namespace field, then take the output name.
        "$WP_CLI" query 2>/dev/null | sed -n 's/^[^:]*: *\([^:]*\):.*/\1/p'
    else
        "$WP_CLI" query 2>/dev/null | cut -d: -f1
    fi
}

# Parse the human-readable query format into "OUTPUT<TAB>PATH" lines.
# awww: "NAMESPACE: OUTPUT: WxH, scale: N, currently displaying: image: PATH"
# swww: "OUTPUT: WxH, scale: N, currently displaying: image: PATH"
# Outputs showing a solid colour rather than an image are skipped.
parse_query_text() {
    awk -v strip_ns="$1" '
        {
            line = $0
            if (strip_ns == "1") {
                i = index(line, ": ")
                if (i == 0) next
                line = substr(line, i + 2)
            }
            j = index(line, ":")
            if (j == 0) next
            name = substr(line, 1, j - 1)

            marker = "currently displaying: image: "
            k = index(line, marker)
            if (k == 0) next
            print name "\t" substr(line, k + length(marker))
        }
    '
}

# Current wallpaper of every output, as "OUTPUT<TAB>PATH" lines.
get_current_wallpapers() {
    detect_wayland_backend || return 1

    if [ "$WP_CLI" = "awww" ]; then
        if command -v jq >/dev/null 2>&1; then
            "$WP_CLI" query -j 2>/dev/null |
                jq -r '.[][] | select(.displaying.image != null)
                       | "\(.name)\t\(.displaying.image)"'
            return
        fi
        "$WP_CLI" query 2>/dev/null | parse_query_text 1
    else
        "$WP_CLI" query 2>/dev/null | parse_query_text 0
    fi
}

# Distinct wallpaper paths currently displayed, one per line.
get_current_wallpaper_paths() {
    get_current_wallpapers | cut -f2- | awk 'NF && !seen[$0]++'
}

# Get current wallpaper (first output only; kept for single-monitor callers)
get_current_wallpaper() {
    get_current_wallpaper_paths | head -1
}

# Show the current wallpaper on every output
show_current_wallpaper() {
    local rows
    rows=$(get_current_wallpapers)

    if [ -z "$rows" ]; then
        echo "Could not determine current wallpaper" >&2
        return 1
    fi

    local output path
    while IFS=$'\t' read -r output path; do
        [ -n "$path" ] || continue
        echo "Monitor: $output"
        echo "  Wallpaper: $path"
        if [ -f "$path" ]; then
            echo "  File exists: Yes"
            echo "  Size: $(du -h "$path" | cut -f1)"
        else
            echo "  File exists: No (may have been deleted)"
        fi
        echo ""
    done <<< "$rows"
}

# Snapshot the per-output layout so --undo can restore it exactly. Taken
# immediately before a change, so it records what is being replaced.
save_state_snapshot() {
    local rows
    rows=$(get_current_wallpapers)
    [ -n "$rows" ] || return 0

    mkdir -p "$(dirname "$STATE_FILE")"
    local temp_file
    temp_file=$(mktemp "${STATE_FILE}.XXXXXX") || return 1
    printf '%s\n' "$rows" > "$temp_file"
    mv "$temp_file" "$STATE_FILE"
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
    # stdout is captured by the caller; diagnostics must go to stderr.
    if [ ! -f "$FAVORITES_FILE" ] || [ ! -s "$FAVORITES_FILE" ]; then
        echo "Error: No favorite wallpapers found." >&2
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
        echo "Error: No valid favorite wallpapers found." >&2
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
SEARCH_SELECT_PATTERN=""
CLEAR_HISTORY=false
SHOW_CURRENT=false
UNDO_WALLPAPER=false
MARK_FAVORITE=false
SHOW_FAVORITES=false
RANDOM_FAVORITE=false
OUTPUTS_FILTER=""
IMAGE_PATHS=()
# Parallel arrays describing an explicit output->image mapping (used by --undo)
RESTORE_OUTPUTS=()
RESTORE_PATHS=()

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--transition)
            need_arg "$@"
            TRANSITION_TYPE="$2"
            shift 2
            ;;
        -d|--duration)
            need_arg "$@"
            TRANSITION_DURATION="$2"
            shift 2
            ;;
        -f|--filter)
            need_arg "$@"
            FILTER="$2"
            shift 2
            ;;
        -p|--position)
            need_arg "$@"
            POSITION="$2"
            shift 2
            ;;
        -a|--angle)
            need_arg "$@"
            ANGLE="$2"
            shift 2
            ;;
        -r|--resize)
            need_arg "$@"
            RESIZE="$2"
            shift 2
            ;;
        -c|--color)
            need_arg "$@"
            FILL_COLOR="$2"
            shift 2
            ;;
        -o|--outputs)
            need_arg "$@"
            OUTPUTS_FILTER="$2"
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
            need_arg "$@"
            SELECT_INDEX="$2"
            shift 2
            ;;
        -S|--search)
            need_arg "$@"
            SEARCH_PATTERN="$2"
            shift 2
            ;;
        --search-select)
            need_arg "$@"
            SEARCH_SELECT_PATTERN="$2"
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
            usage 0
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

# Reject combinations whose precedence would otherwise be surprising.
ACTION_COUNT=0
for action in "$CLEAR_HISTORY" "$SHOW_HISTORY" "$SHOW_CURRENT" "$MARK_FAVORITE" "$SHOW_FAVORITES"; do
    [ "$action" = false ] || ((ACTION_COUNT++))
done
[ -z "$SEARCH_PATTERN" ] || ((ACTION_COUNT++))
if [ "$ACTION_COUNT" -gt 1 ]; then
    echo "Error: history/current/favorite display actions cannot be combined." >&2
    exit 1
fi

SELECTION_COUNT=0
[ "$UNDO_WALLPAPER" = false ] || ((SELECTION_COUNT++))
[ -z "$SELECT_INDEX" ] || ((SELECTION_COUNT++))
[ -z "$SEARCH_SELECT_PATTERN" ] || ((SELECTION_COUNT++))
[ "$RANDOM_FAVORITE" = false ] || ((SELECTION_COUNT++))
[ "$RANDOM_WALLPAPER" = false ] || ((SELECTION_COUNT++))
[ ${#IMAGE_PATHS[@]} -eq 0 ] || ((SELECTION_COUNT++))
if [ "$SELECTION_COUNT" -gt 1 ]; then
    echo "Error: provide only one wallpaper selection mode." >&2
    exit 1
fi
if [ "$ACTION_COUNT" -gt 0 ] && [ "$SELECTION_COUNT" -gt 0 ]; then
    echo "Error: display/maintenance actions cannot be combined with wallpaper selection." >&2
    exit 1
fi

# Fail early with clearer messages than the backend's argument parser.
case "$TRANSITION_TYPE" in
    none|simple|fade|left|right|top|bottom|wipe|wave|grow|center|any|outer|random) ;;
    *) echo "Error: invalid transition type: $TRANSITION_TYPE" >&2; exit 1 ;;
esac
case "$FILTER" in
    Lanczos3|Mitchell|CatmullRom|Bilinear|Nearest) ;;
    *) echo "Error: invalid scaling filter: $FILTER" >&2; exit 1 ;;
esac
case "$RESIZE" in
    crop|fit|stretch|no) ;;
    *) echo "Error: invalid resize method: $RESIZE" >&2; exit 1 ;;
esac
if ! [[ "$TRANSITION_DURATION" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    echo "Error: duration must be a non-negative number: $TRANSITION_DURATION" >&2
    exit 1
fi
if ! [[ "$ANGLE" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
    echo "Error: angle must be a number: $ANGLE" >&2
    exit 1
fi
if ! [[ "$POSITION" =~ ^(center|top|left|right|bottom|top-left|top-right|bottom-left|bottom-right|-?[0-9]+([.][0-9]+)?,-?[0-9]+([.][0-9]+)?)$ ]]; then
    echo "Error: position must be an awww position name or an X,Y coordinate: $POSITION" >&2
    exit 1
fi
if ! [[ "$FILL_COLOR" =~ ^([[:xdigit:]]{6}|[[:xdigit:]]{8})$ ]]; then
    echo "Error: fill color must contain 6 or 8 hexadecimal digits: $FILL_COLOR" >&2
    exit 1
fi

SESSION_TYPE=$(detect_session_type)

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
    # Favorite every distinct wallpaper currently displayed, not just the one
    # on the first monitor.
    mapfile -t CURRENT_PATHS < <(get_current_wallpaper_paths)

    if [ ${#CURRENT_PATHS[@]} -eq 0 ]; then
        echo "Error: Could not determine current wallpaper to mark as favorite." >&2
        exit 1
    fi

    for current in "${CURRENT_PATHS[@]}"; do
        add_to_favorites "$current"
    done
    exit 0
fi

if [ -n "$SEARCH_PATTERN" ]; then
    search_history "$SEARCH_PATTERN"
    exit 0
fi

if [ -n "$SEARCH_SELECT_PATTERN" ]; then
    if ! SELECTED_PATH=$(select_from_search "$SEARCH_SELECT_PATTERN"); then
        exit 1
    fi
    IMAGE_PATHS=("$SELECTED_PATH")
    echo "Selected from history: $SELECTED_PATH"
fi

# Handle undo (restore the previous per-monitor layout)
if [ "$UNDO_WALLPAPER" = true ]; then
    # Prefer the snapshot: it restores exactly what each monitor was showing,
    # even if that layout was set by something other than this script. The flat
    # history cannot express "different image per monitor".
    if [ "$SESSION_TYPE" = "wayland" ] && [ -s "$STATE_FILE" ]; then
        while IFS=$'\t' read -r _out _path; do
            [ -n "$_out" ] && [ -n "$_path" ] || continue
            if [ ! -f "$_path" ]; then
                echo "Warning: skipping $_out, file no longer exists: $_path" >&2
                continue
            fi
            RESTORE_OUTPUTS+=("$_out")
            RESTORE_PATHS+=("$_path")
        done < "$STATE_FILE"
    fi

    if [ ${#RESTORE_PATHS[@]} -gt 0 ]; then
        # The apply stage prints the per-monitor breakdown.
        IMAGE_PATHS=("${RESTORE_PATHS[@]}")
    else
        # No snapshot (first run, or X11 where there is nothing to query):
        # fall back to the flat history.
        init_history

        if [ ! -s "$HISTORY_FILE" ]; then
            echo "Error: No saved layout or wallpaper history found. Cannot undo." >&2
            exit 1
        fi

        # Index 1 is current, index 2 is previous
        if ! PREVIOUS_PATH=$(get_from_history 2); then
            echo "Error: No previous wallpaper in history to restore." >&2
            exit 1
        fi

        IMAGE_PATHS=("$PREVIOUS_PATH")
        echo "Restoring previous wallpaper: $PREVIOUS_PATH"
    fi
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
    # Check if wallpaper directory exists
    if [ ! -d "$WALLPAPER_DIR" ]; then
        echo "Error: Wallpaper directory does not exist: $WALLPAPER_DIR" >&2
        echo "Set \$WALLPAPER_DIR to override." >&2
        exit 1
    fi

    # Get list of image files (NUL-delimited, so newlines in names are safe)
    IMAGE_FILES=()
    while IFS= read -r -d '' _f; do
        IMAGE_FILES+=("$_f")
    done < <(find "$WALLPAPER_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" -o -iname "*.webp" -o -iname "*.avif" -o -iname "*.svg" -o -iname "*.tif" -o -iname "*.tiff" -o -iname "*.bmp" \) -print0)

    # Check if any images were found
    if [ ${#IMAGE_FILES[@]} -eq 0 ]; then
        echo "Error: No image files found in $WALLPAPER_DIR" >&2
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
    if [[ "$img" == *['|'$'\t'$'\n']* ]]; then
        echo "Error: wallpaper paths cannot contain '|', tab, or newline characters." >&2
        exit 1
    fi

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

if [ "$SESSION_TYPE" = "wayland" ]; then
    # Wayland session - use awww (formerly swww)
    if ! detect_wayland_backend; then
        echo "Error: awww is not installed. Please install it first." >&2
        echo "  pacman -S awww" >&2
        echo "Visit: https://codeberg.org/LGFae/awww" >&2
        exit 1
    fi

    # Initialize the daemon if not already running. setsid detaches it so it
    # survives this script exiting (e.g. when launched from a WM keybind).
    if ! command -v "$WP_DAEMON" >/dev/null 2>&1; then
        echo "Error: $WP_DAEMON is not installed or not in PATH." >&2
        exit 1
    fi

    # Querying the target namespace is more reliable than looking for any
    # process with the daemon name.
    if ! "$WP_CLI" query >/dev/null 2>&1; then
        echo "Starting $WP_DAEMON..."
        setsid -f "$WP_DAEMON" >/dev/null 2>&1

        # Wait for daemon to initialize properly
        daemon_ready=false
        for i in {1..20}; do
            if "$WP_CLI" query >/dev/null 2>&1; then
                daemon_ready=true
                break
            fi
            sleep 0.1
        done

        if [ "$daemon_ready" = false ]; then
            echo "Error: $WP_DAEMON failed to start properly" >&2
            exit 1
        fi

        echo "$WP_DAEMON started successfully"
    fi

    # Get list of monitors
    mapfile -t MONITORS < <(get_monitors | sort)

    if [ ${#MONITORS[@]} -eq 0 ]; then
        echo "Error: No monitors detected by $WP_CLI" >&2
        exit 1
    fi

    echo "Detected ${#MONITORS[@]} monitor(s): ${MONITORS[*]}"

    # Apply one image, optionally restricted to a comma-separated output list.
    apply_image() {
        local img="$1"
        local outputs="$2"
        local -a out_args=()
        [ -n "$outputs" ] && out_args=(--outputs "$outputs")

        "$WP_CLI" img "$img" \
            "${out_args[@]}" \
            --transition-type "$TRANSITION_TYPE" \
            --transition-pos "$POSITION" \
            --transition-duration "$TRANSITION_DURATION" \
            --transition-angle "$ANGLE" \
            --filter "$FILTER" \
            --resize "$RESIZE" \
            --fill-color "$FILL_COLOR"
    }

    # Record the layout we are about to replace, so --undo can restore it.
    save_state_snapshot

    SUCCESS=true

    if [ ${#RESTORE_OUTPUTS[@]} -gt 0 ]; then
        # Undo: reapply the snapshot pairwise, output by output.
        echo "Restoring ${#RESTORE_OUTPUTS[@]} monitor(s)..."
        for i in "${!RESTORE_OUTPUTS[@]}"; do
            echo "  Monitor ${RESTORE_OUTPUTS[$i]}: $(basename "${RESTORE_PATHS[$i]}")"
            if apply_image "${RESTORE_PATHS[$i]}" "${RESTORE_OUTPUTS[$i]}"; then
                add_to_history "${RESTORE_PATHS[$i]}"
            else
                SUCCESS=false
            fi
        done
        # Newest-first history: add in reverse so the first monitor ends up at index 1.
    elif [ ${#IMAGE_PATHS[@]} -eq 1 ]; then
        # Single image - all monitors, or just those named by -o/--outputs
        if [ -n "$OUTPUTS_FILTER" ]; then
            echo "Setting wallpaper on: $OUTPUTS_FILTER"
        else
            echo "Setting single wallpaper on all monitors..."
        fi

        if apply_image "${IMAGE_PATHS[0]}" "$OUTPUTS_FILTER"; then
            add_to_history "${IMAGE_PATHS[0]}"
            safe_notify -i "${IMAGE_PATHS[0]}" "Wallpaper Set (Wayland)" \
                "Applied $(basename "${IMAGE_PATHS[0]}") to ${OUTPUTS_FILTER:-all monitors}"
            echo "✓ Wallpaper set to: ${IMAGE_PATHS[0]}"
        else
            SUCCESS=false
        fi

    else
        # Multiple images - apply one per monitor, in MONITORS order
        if [ ${#IMAGE_PATHS[@]} -gt ${#MONITORS[@]} ]; then
            echo "Warning: ${#IMAGE_PATHS[@]} images given but only ${#MONITORS[@]} monitor(s); ignoring the extras." >&2
        fi

        echo "Setting different wallpaper on each monitor..."
        for i in "${!MONITORS[@]}"; do
            if [ "$i" -lt ${#IMAGE_PATHS[@]} ]; then
                echo "  Monitor ${MONITORS[$i]}: $(basename "${IMAGE_PATHS[$i]}")"
                if apply_image "${IMAGE_PATHS[$i]}" "${MONITORS[$i]}"; then
                    add_to_history "${IMAGE_PATHS[$i]}"
                else
                    SUCCESS=false
                fi
            else
                echo "  Monitor ${MONITORS[$i]}: No image provided, keeping current wallpaper"
            fi
        done

    fi

    if [ "$SUCCESS" = true ]; then
        if [ ${#IMAGE_PATHS[@]} -gt 1 ] || [ ${#RESTORE_OUTPUTS[@]} -gt 0 ]; then
            safe_notify "Wallpaper Set (Wayland)" "Applied ${#IMAGE_PATHS[@]} wallpaper(s) to ${#MONITORS[@]} monitor(s)"
            echo "✓ Wallpapers set successfully"
        fi
    else
        safe_notify -u critical "Wallpaper Error" "Some wallpapers failed to set on Wayland"
        echo "Error: Some wallpapers failed to set" >&2
        exit 1
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

    if [ -n "$OUTPUTS_FILTER" ]; then
        echo "Warning: --outputs is not supported on X11; setting all screens." >&2
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
