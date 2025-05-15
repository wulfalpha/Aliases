#!/usr/bin/env bash
# pacmaster.sh - A tool to manage .pacnew files for Arch Linux users
# This script displays .pacnew files in a dialog, allowing users to view, diff, and manage them

# Set defaults
EDITOR=${EDITOR:-nano}
DIFF_TOOL=${DIFF_TOOL:-vimdiff}
MERGE_TOOL=${MERGE_TOOL:-$DIFF_TOOL}
TITLE="Pacnew File Manager"
VERSION="1.2.0"
TEMP_DIR=$(mktemp -d)
USE_COLOR=${USE_COLOR:-true}

# Cleanup function to remove temporary files on exit
cleanup() {
    rm -rf "$TEMP_DIR"
}

# Set up trap to clean temporary files on exit
trap cleanup EXIT

# Function to check dependencies
check_dependencies() {
    local missing=()
    # Check for required dependencies
    command -v yad >/dev/null 2>&1 || missing+=("yad")
    
    if [ ${#missing[@]} -gt 0 ]; then
        echo "Error: Missing required dependencies: ${missing[*]}"
        echo "Please install them using your package manager."
        exit 1
    fi
    
    # Check for fd or find - one of them is required
    if ! command -v fd >/dev/null 2>&1 && ! command -v find >/dev/null 2>&1; then
        echo "Error: Neither fd nor find is installed. Please install one of them."
        exit 1
    fi
    
    # Check if fd is installed and print a message
    if command -v fd >/dev/null 2>&1; then
        echo "Using fd for faster file searching."
    else
        echo "fd not found, falling back to find."
    fi
}

# Function to show help
show_help() {
    cat << EOF
pacmaster.sh $VERSION - A tool to manage .pacnew files for Arch Linux users

Usage: $(basename "$0") [OPTIONS]

Options:
  -h, --help     Show this help message and exit
  -d, --diff     Use diff mode by default
  -p, --path     Specify a path to search for .pacnew files (default: /etc)
  -e, --editor   Specify an editor to use (default: \$EDITOR or nano)
  -m, --merge    Specify a merge tool (default: \$MERGE_TOOL or \$DIFF_TOOL)
  -r, --recurse  Recursively search all subdirectories (default for fd)
  -N, --no-color Disable colorized output
  -v, --version  Show version information and exit

Examples:
  $(basename "$0")                      # Run with default settings
  $(basename "$0") -p /usr/share        # Search for .pacnew files in /usr/share
  $(basename "$0") -e vim               # Use vim as the editor
  $(basename "$0") -m meld -d vimdiff   # Use meld for merging and vimdiff for diffing
  
Note: This script uses fd if available (faster, colorized output), with fallback to find.

Environment variables:
  EDITOR      Editor to use (default: nano)
  DIFF_TOOL   Diff tool to use (default: vimdiff)
  MERGE_TOOL  Merge tool to use (default: same as DIFF_TOOL)
  USE_COLOR   Enable/disable colorized output (default: true)

EOF
    exit 0
}

# Function to find pacnew files
find_pacnew_files() {
    local search_path="$1"
    local recursive="$2"
    
    echo "Searching for .pacnew files in $search_path..."
    
    # Set up colors for output if enabled
    local color_found=""
    local color_reset=""
    if [ "$USE_COLOR" = "true" ] && [ -t 1 ]; then
        color_found="\033[1;32m"  # Bold green
        color_reset="\033[0m"     # Reset
    fi
    
    # Use fd if available, otherwise fall back to find
    if command -v fd >/dev/null 2>&1; then
        local fd_cmd=(fd -t f -e pacnew)
        
        # Add color flag if color is enabled
        if [ "$USE_COLOR" = "true" ]; then
            fd_cmd+=(--color=always)
        else
            fd_cmd+=(--color=never)
        fi
        
        # Add path restriction if not recursive
        if [ "$recursive" != "true" ]; then
            fd_cmd+=(--max-depth 1)
        fi
        
        # Add search path
        fd_cmd+=(. "$search_path")
        
        # Execute fd command
        "${fd_cmd[@]}" 2>/dev/null
    else
        # Construct find command based on recursion setting
        if [ "$recursive" = "true" ]; then
            find "$search_path" -type f -name "*.pacnew" 2>/dev/null
        else
            find "$search_path" -maxdepth 1 -type f -name "*.pacnew" 2>/dev/null
        fi
    fi
}

# Function to safely edit a file (like sudoedit)
safe_edit() {
    local source_file="$1"
    local basename_file=$(basename "$source_file")
    local temp_file="$TEMP_DIR/$basename_file"
    
    # Create a copy of the source file
    cp "$source_file" "$temp_file"
    
    # Set correct permissions
    chmod 600 "$temp_file"
    
    # Get modification time before editing
    local mtime_before=$(stat -c %Y "$temp_file")
    
    # Edit the file
    $EDITOR "$temp_file"
    
    # Get modification time after editing
    local mtime_after=$(stat -c %Y "$temp_file")
    
    # Check if the file was modified
    if [ "$mtime_before" != "$mtime_after" ]; then
        # Ask for confirmation before applying changes
        yad --center --title="Confirm Changes" \
            --text="Apply changes to $source_file?" \
            --button="Cancel:1" --button="Apply:0"
            
        if [ $? -eq 0 ]; then
            # Apply changes
            sudo cp "$temp_file" "$source_file"
            echo "Changes applied to $source_file"
            return 0
        else
            echo "Changes discarded"
            return 1
        fi
    else
        yad --center --title="No Changes" \
            --text="No changes were made to the file." \
            --button="OK:0"
        return 1
    fi
}

# Process command line arguments
search_path="/etc"
recursive=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            ;;
        -p|--path)
            search_path="$2"
            shift 2
            ;;
        -e|--editor)
            EDITOR="$2"
            shift 2
            ;;
        -d|--diff)
            default_diff=true
            shift
            ;;
        -m|--merge)
            MERGE_TOOL="$2"
            shift 2
            ;;
        -r|--recurse)
            recursive=true
            shift
            ;;
        -N|--no-color)
            USE_COLOR=false
            shift
            ;;
        -v|--version)
            echo "pacmaster.sh version $VERSION"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help to see available options."
            exit 1
            ;;
    esac
done

# Check for required dependencies
check_dependencies

# Find pacnew files
pacnew_files=$(find_pacnew_files "$search_path" "$recursive")

# Check if there was an error with find command
if [ $? -ne 0 ]; then
    yad --center --title="$TITLE" --image="dialog-error" \
        --text="<b>Error searching for .pacnew files</b>\n\nThere was an error searching in $search_path.\nPlease check the terminal output for details." \
        --width=400 --button="OK:0"
    echo "Error searching for .pacnew files in $search_path."
    exit 1
fi

if [ -z "$pacnew_files" ]; then
    yad --center --title="$TITLE" --image="dialog-information" \
        --text="<b>No .pacnew files found</b>\n\nThere are no pending configuration files to review in $search_path.\nThis means your system configuration is up-to-date!" \
        --width=400 --button="OK:0"
    echo "No .pacnew files found in $search_path."
    exit 0
fi

# Get the file list into an array
mapfile -t pacnew_array <<< "$pacnew_files"

# Create a temporary file for YAD output
tmp_file="$TEMP_DIR/yad_output"

# Function to display file selection dialog
show_file_selection() {
    local pacnew_files=("$@")
    local yad_cmd=(
        yad --center --title="$TITLE" --width=800 --height=500
        --text="<b>Select a .pacnew file to manage:</b>"
        --list --column="ID":HD --column="Path":TEXT --column="Size":TEXT --column="Modified":TEXT
        --print-column=2 --button="Refresh:2" --button="Close:1" --button="View/Edit:0"
    )

    # Add rows to YAD command
    local id=1
    for file in "${pacnew_files[@]}"; do
        if [ -f "$file" ]; then
            # Get file info
            local size=$(du -h "$file" 2>/dev/null | cut -f1)
            local modified=$(stat -c "%y" "$file" 2>/dev/null | cut -d. -f1)
            yad_cmd+=("$id" "$file" "$size" "$modified")
            ((id++))
        fi
    done

    # Run YAD and capture selected file
    "${yad_cmd[@]}" > "$tmp_file"
    return $?
}

# First show of file selection
show_file_selection "${pacnew_array[@]}"
exit_code=$?

# Handle Refresh button (exit code 2)
while [ $exit_code -eq 2 ]; do
    echo "Refreshing .pacnew file list..."
    pacnew_files=$(find_pacnew_files "$search_path" "$recursive")
    
    if [ -z "$pacnew_files" ]; then
        yad --center --title="$TITLE" --image="dialog-information" \
            --text="<b>No .pacnew files found</b>\n\nThere are no pending configuration files to review in $search_path.\nThis means your system configuration is up-to-date!" \
            --width=400 --button="OK:0"
        echo "No .pacnew files found in $search_path."
        exit 0
    fi
    
    # Reload the file list
    mapfile -t pacnew_array <<< "$pacnew_files"
    
    # Re-run YAD with the updated list
    show_file_selection "${pacnew_array[@]}"
    exit_code=$?
done

# If user clicked Close (1), exit
if [ $exit_code -eq 1 ]; then
    exit 0
fi

# If user clicked View/Edit (0) and selected a file
if [ $exit_code -eq 0 ] && [ -s "$tmp_file" ]; then
    selected_file=$(cat "$tmp_file")
    original_file="${selected_file%.pacnew}"
    
    # Show options for the selected file
    action=$(yad --center --title="$TITLE - Actions" --width=400 \
        --text="<b>Selected file:</b> $selected_file\n\nChoose an action:" \
        --list --no-headers --column="Action" \
        "View/Edit .pacnew file safely" \
        "Diff with original file" \
        "Use .pacnew (replace original)" \
        "Merge/Edit both files" \
        "Delete .pacnew (keep original)" \
        --button="Cancel:1" --button="OK:0")
    
    action_code=$?
    if [ $action_code -eq 0 ]; then
        case "$action" in
            "View/Edit .pacnew file safely")
                safe_edit "$selected_file"
                ;;
            "Diff with original file")
                if [ -f "$original_file" ]; then
                    # Create temporary copies for diff
                    cp "$original_file" "$TEMP_DIR/original"
                    cp "$selected_file" "$TEMP_DIR/pacnew"
                    $DIFF_TOOL "$TEMP_DIR/original" "$TEMP_DIR/pacnew"
                else
                    yad --center --title="Error" --text="Original file not found: $original_file" \
                        --button="OK:0"
                fi
                ;;
            "Merge/Edit both files")
                if [ -f "$original_file" ]; then
                    # Create temporary copies for merging
                    cp "$original_file" "$TEMP_DIR/original"
                    cp "$selected_file" "$TEMP_DIR/pacnew"
                    
                    # Use merge tool
                    echo "Using merge tool: $MERGE_TOOL"
                    $MERGE_TOOL "$TEMP_DIR/original" "$TEMP_DIR/pacnew"
                    
                    # Ask which file to use
                    merged_choice=$(yad --center --title="Apply Changes" --width=400 \
                        --text="What would you like to do with the merged result?" \
                        --list --no-headers --column="Action" \
                        "Apply to original file (replace $original_file)" \
                        "Apply to .pacnew file (replace $selected_file)" \
                        "Save as new file" \
                        "Discard changes" \
                        --button="Cancel:1" --button="OK:0")
                    
                    if [ $? -eq 0 ]; then
                        case "$merged_choice" in
                            "Apply to original file (replace $original_file)")
                                sudo cp "$TEMP_DIR/original" "$original_file"
                                yad --center --title="Success" \
                                    --text="Changes applied to original file." \
                                    --button="OK:0"
                                ;;
                            "Apply to .pacnew file (replace $selected_file)")
                                sudo cp "$TEMP_DIR/pacnew" "$selected_file"
                                yad --center --title="Success" \
                                    --text="Changes applied to .pacnew file." \
                                    --button="OK:0"
                                ;;
                            "Save as new file")
                                save_path=$(yad --center --title="Save File" --file --save \
                                    --filename="$original_file.merged")
                                if [ -n "$save_path" ]; then
                                    if cp "$TEMP_DIR/original" "$save_path"; then
                                        chmod 644 "$save_path"
                                        yad --center --title="Success" \
                                            --text="File saved as: $save_path" \
                                            --button="OK:0"
                                    else
                                        yad --center --title="Error" \
                                            --text="Failed to save file to: $save_path" \
                                            --button="OK:0"
                                    fi
                                fi
                                ;;
                            "Discard changes")
                                # Do nothing
                                ;;
                        esac
                    fi
                else
                    yad --center --title="Error" --text="Original file not found: $original_file" \
                        --button="OK:0"
                fi
                ;;
            "Use .pacnew (replace original)")
                if [ -f "$original_file" ]; then
                    confirmation=$(yad --center --title="Confirm" \
                        --text="Are you sure you want to replace:\n$original_file\nwith:\n$selected_file?" \
                        --button="No:1" --button="Yes:0")
                    if [ $? -eq 0 ]; then
                        # Create backup of original
                        if sudo cp "$original_file" "$original_file.bak"; then
                            # Replace original with pacnew
                            if sudo cp "$selected_file" "$original_file" && sudo rm "$selected_file"; then
                                yad --center --title="Success" \
                                    --text="File replaced successfully.\nBackup saved as: $original_file.bak" \
                                    --button="OK:0"
                            else
                                yad --center --title="Error" \
                                    --text="Failed to replace original file." \
                                    --button="OK:0"
                            fi
                        else
                            yad --center --title="Error" \
                                --text="Failed to create backup of original file." \
                                --button="OK:0"
                        fi
                    fi
                else
                    sudo cp "$selected_file" "$original_file"
                    sudo rm "$selected_file"
                    yad --center --title="Success" \
                        --text="File installed successfully." \
                        --button="OK:0"
                fi
                ;;
            "Delete .pacnew (keep original)")
                confirmation=$(yad --center --title="Confirm" \
                    --text="Are you sure you want to delete:\n$selected_file?" \
                    --button="No:1" --button="Yes:0")
                if [ $? -eq 0 ]; then
                    sudo rm "$selected_file"
                    yad --center --title="Success" \
                        --text="File deleted successfully." \
                        --button="OK:0"
                fi
                ;;
        esac
    fi
fi

exit 0