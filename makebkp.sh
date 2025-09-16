#!/usr/bin/env bash

# Color codes for progress bar (similar to pacman)
readonly COLOR_RESET='\033[0m'
readonly COLOR_BOLD='\033[1m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_CYAN='\033[0;36m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[0;33m'

# Parse command line arguments
PATH_TO_ITEM="${1}"
DEST_PATH="${2}"
EXT="${3}"

# Function to get terminal dimensions
get_terminal_width() {
    tput cols 2>/dev/null || echo 80
}

# Function to move cursor to bottom of terminal
move_to_bottom() {
    local term_height=$(tput lines 2>/dev/null || echo 24)
    tput cup $((term_height - 1)) 0 2>/dev/null || printf '\033[%d;0H' $((term_height - 1))
}

# Function to save and restore cursor position
save_cursor() {
    tput sc 2>/dev/null || printf '\033[s'
}

restore_cursor() {
    tput rc 2>/dev/null || printf '\033[u'
}

# Function to clear current line
clear_line() {
    printf '\r\033[K'
}

# Function to display progress bar (pacman-style with apt-like positioning)
display_progress() {
    local current=$1
    local total=$2
    local filename=$3
    local width=$(get_terminal_width)

    # Calculate percentage
    local percent=0
    if [ "$total" -gt 0 ]; then
        percent=$((current * 100 / total))
    fi

    # Calculate bar width (leave space for text)
    local bar_width=$((width - 35))
    if [ "$bar_width" -lt 20 ]; then
        bar_width=20
    fi

    local filled=$((percent * bar_width / 100))
    local empty=$((bar_width - filled))

    # Save cursor position, move to bottom, display progress
    save_cursor
    move_to_bottom
    clear_line

    # Build progress bar string (pacman-style)
    printf "${COLOR_BOLD}[${COLOR_BLUE}"

    # Filled portion with blocks
    for ((i=0; i<filled; i++)); do
        printf "█"
    done

    # Empty portion with lighter blocks
    printf "${COLOR_CYAN}"
    for ((i=0; i<empty; i++)); do
        printf "░"
    done

    printf "${COLOR_RESET}${COLOR_BOLD}]${COLOR_RESET} "

    # Show percentage and size info
    printf "${COLOR_GREEN}%3d%%${COLOR_RESET} " "$percent"

    # Show size in human-readable format
    if [ "$total" -gt 0 ]; then
        local current_mb=$((current / 1048576))
        local total_mb=$((total / 1048576))
        if [ "$total_mb" -gt 0 ]; then
            printf "(%dMB/%dMB)" "$current_mb" "$total_mb"
        else
            local current_kb=$((current / 1024))
            local total_kb=$((total / 1024))
            printf "(%dKB/%dKB)" "$current_kb" "$total_kb"
        fi
    fi

    # Restore cursor position
    restore_cursor
}

# Function to copy file/directory with progress
copy_with_progress() {
    local source="$1"
    local destination="$2"

    if [ -d "$source" ]; then
        # For directories, use rsync with progress
        echo -e "${COLOR_BOLD}Creating backup of directory: ${COLOR_YELLOW}$(basename "$source")${COLOR_RESET}"

        # Calculate total size
        local total_size=$(du -sb "$source" 2>/dev/null | cut -f1)

        # Use rsync for directory copying with progress callback
        rsync -ah --info=progress2 "$source" "$(dirname "$destination")/" | \
        while IFS= read -r line; do
            if [[ "$line" =~ ([0-9]+).*([0-9]+)% ]]; then
                local bytes="${BASH_REMATCH[1]}"
                local percent="${BASH_REMATCH[2]}"
                display_progress "$((total_size * percent / 100))" "$total_size" "$(basename "$source")"
            fi
        done

        # Rename to add extension if needed
        if [ "$destination" != "$source" ]; then
            mv "$(dirname "$destination")/$(basename "$source")" "$destination" 2>/dev/null
        fi

        clear_line
        echo -e "${COLOR_GREEN}✓${COLOR_RESET} Backup created: ${COLOR_YELLOW}$destination${COLOR_RESET}"
    else
        # For files, use cp with simulated progress
        echo -e "${COLOR_BOLD}Creating backup of file: ${COLOR_YELLOW}$(basename "$source")${COLOR_RESET}"

        local total_size=$(stat -c%s "$source" 2>/dev/null || stat -f%z "$source" 2>/dev/null || echo 0)

        # Copy the file
        cp "$source" "$destination" &
        local cp_pid=$!

        # Show progress while copying
        local bytes_copied=0
        local update_count=0

        while kill -0 $cp_pid 2>/dev/null; do
            # Check current size of destination file
            if [ -f "$destination" ]; then
                bytes_copied=$(stat -c%s "$destination" 2>/dev/null || stat -f%z "$destination" 2>/dev/null || echo 0)
            fi

            # Update progress every 5 iterations (reduces flickering)
            if [ $((update_count % 5)) -eq 0 ]; then
                display_progress "$bytes_copied" "$total_size" "$(basename "$source")"
            fi

            update_count=$((update_count + 1))
            sleep 0.2
        done

        # Wait for cp to finish and get final size
        wait $cp_pid
        bytes_copied=$total_size
        display_progress "$bytes_copied" "$total_size" "$(basename "$source")"

        clear_line
        echo -e "${COLOR_GREEN}✓${COLOR_RESET} Backup created: ${COLOR_YELLOW}$destination${COLOR_RESET}"
    fi
}

# Function to show usage
show_usage() {
    echo "Usage: $0 <path_to_item> <destination_path> [extension]"
    echo ""
    echo "Arguments:"
    echo "  path_to_item     - Path to file or directory to backup"
    echo "  destination_path - Either a directory (ends with /) or full file path"
    echo "  extension        - Optional backup extension (default: .bak)"
    echo ""
    echo "Examples:"
    echo "  $0 file.txt /backups/                    # Creates /backups/file.txt.bak"
    echo "  $0 file.txt backup                       # Creates backup.bak in current dir"
    echo "  $0 /path/to/dir /backups/ .backup        # Creates /backups/dir.backup"
    echo "  $0 config.conf ~/backups/config .$(date +%Y%m%d)  # Creates ~/backups/config.20240101"
    exit 1
}

# Main script logic

# Check if help is requested
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_usage
fi

# Check if the required arguments are provided
if [ -z "$PATH_TO_ITEM" ] || [ -z "$DEST_PATH" ]; then
    echo -e "${COLOR_YELLOW}Error: Missing required arguments${COLOR_RESET}"
    show_usage
fi

# Normalize paths - remove trailing slashes except for root
PATH_TO_ITEM="${PATH_TO_ITEM%/}"
DEST_PATH="${DEST_PATH%/}"

# Check if source exists
if [ ! -e "$PATH_TO_ITEM" ]; then
    echo -e "${COLOR_YELLOW}Error: Source does not exist: $PATH_TO_ITEM${COLOR_RESET}"
    exit 1
fi

# If user provides extension, use it; otherwise, default to .bak
EXTENSION=".bak"
if [ -n "$EXT" ]; then
    EXTENSION="$EXT"
fi

# Determine if DEST_PATH is a directory or a file path
# If DEST_PATH ends with / or is an existing directory, treat it as a directory
# Otherwise, treat it as the full destination path
if [[ "$DEST_PATH" == */ ]] || [ -d "$DEST_PATH" ]; then
    # Destination is a directory
    if [ ! -d "$DEST_PATH" ]; then
        echo -e "${COLOR_CYAN}Creating destination directory: $DEST_PATH${COLOR_RESET}"
        mkdir -p "$DEST_PATH"
    fi
    # Construct the backup filename
    BACKUP_NAME="$(basename "$PATH_TO_ITEM")$EXTENSION"
    FULL_DEST_PATH="${DEST_PATH}/${BACKUP_NAME}"
else
    # Destination is a full file path
    # Ensure parent directory exists
    DEST_DIR="$(dirname "$DEST_PATH")"
    if [ ! -d "$DEST_DIR" ]; then
        echo -e "${COLOR_CYAN}Creating destination directory: $DEST_PATH${COLOR_RESET}"
        mkdir -p "$DEST_DIR"
    fi
    # Add extension to the provided destination path
    FULL_DEST_PATH="${DEST_PATH}${EXTENSION}"
fi

# Check if backup already exists
if [ -e "$FULL_DEST_PATH" ]; then
    echo -e "${COLOR_YELLOW}Warning: Backup already exists: $FULL_DEST_PATH${COLOR_RESET}"
    read -p "Overwrite? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Backup cancelled."
        exit 0
    fi
fi

# Perform the backup with progress bar
copy_with_progress "$PATH_TO_ITEM" "$FULL_DEST_PATH"

# Clear the progress bar line and show completion
move_to_bottom
clear_line
echo -e "\n${COLOR_GREEN}${COLOR_BOLD}Backup completed successfully!${COLOR_RESET}"
