#!/usr/bin/env bash
# pacmaster.sh - A tool to manage .pacnew files for Arch Linux users
# This script displays .pacnew files in a dialog, allowing users to view, diff, and manage them

# Source .bashrc to get user's environment settings
# This ensures we use the same tools the user has configured
if [ -f "$HOME/.bashrc" ]; then
    # Create a temporary file to capture exports
    temp_env=$(mktemp)
    # Run bash with .bashrc and export relevant variables
    bash -c 'source ~/.bashrc 2>/dev/null && env | grep -E "^(EDITOR|DIFF_TOOL|MERGE_TOOL|VISUAL|SUDO_EDITOR)="' > "$temp_env"
    # Source the captured environment
    while IFS= read -r line; do
        export "$line"
    done < "$temp_env"
    rm -f "$temp_env"
fi

# Set defaults after loading .bashrc
# Use VISUAL as fallback for EDITOR if set
EDITOR=${EDITOR:-${VISUAL:-nano}}
SUDO_EDITOR=${SUDO_EDITOR:-$EDITOR}
DIFF_TOOL=${DIFF_TOOL:-vimdiff}
MERGE_TOOL=${MERGE_TOOL:-$DIFF_TOOL}
TITLE="Pacnew File Manager"
VERSION="1.3.0"
TEMP_DIR=$(mktemp -d)
USE_COLOR=${USE_COLOR:-true}

# Color definitions
if [ "$USE_COLOR" = "true" ] && [ -t 1 ]; then
    COLOR_RED='\033[0;31m'
    COLOR_GREEN='\033[0;32m'
    COLOR_YELLOW='\033[1;33m'
    COLOR_BLUE='\033[0;34m'
    COLOR_BOLD='\033[1m'
    COLOR_RESET='\033[0m'
else
    COLOR_RED=''
    COLOR_GREEN=''
    COLOR_YELLOW=''
    COLOR_BLUE=''
    COLOR_BOLD=''
    COLOR_RESET=''
fi

# Cleanup function to remove temporary files on exit
cleanup() {
    rm -rf "$TEMP_DIR"
}

# Set up trap to clean temporary files on exit
trap cleanup EXIT INT TERM

# Function to print colored messages
print_info() {
    echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} $1" >&2
}

print_success() {
    echo -e "${COLOR_GREEN}[SUCCESS]${COLOR_RESET} $1" >&2
}

print_warning() {
    echo -e "${COLOR_YELLOW}[WARNING]${COLOR_RESET} $1" >&2
}

print_error() {
    echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $1" >&2
}

# Function to check dependencies
check_dependencies() {
    local missing=()
    # Check for required dependencies
    command -v yad >/dev/null 2>&1 || missing+=("yad")

    if [ ${#missing[@]} -gt 0 ]; then
        print_error "Missing required dependencies: ${missing[*]}"
        echo "Please install them using your package manager."
        exit 1
    fi

    # Check for fd or find - one of them is required
    if ! command -v fd >/dev/null 2>&1 && ! command -v find >/dev/null 2>&1; then
        print_error "Neither fd nor find is installed. Please install one of them."
        exit 1
    fi

    # Check if fd is installed and print a message
    if command -v fd >/dev/null 2>&1; then
        print_info "Using fd for faster file searching."
    else
        print_info "fd not found, falling back to find."
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
  --debug        Show configuration and verbose output

Examples:
  $(basename "$0")                      # Run with default settings
  $(basename "$0") -p /usr/share        # Search for .pacnew files in /usr/share
  $(basename "$0") -e vim               # Use vim as the editor
  $(basename "$0") -m meld              # Use meld for merging

Note: This script uses fd if available (faster, colorized output), with fallback to find.

Configuration:
  The script loads settings from your ~/.bashrc file automatically.
  Command line arguments have the highest priority and override environment settings.

Environment variables (set in ~/.bashrc):
  EDITOR       Editor to use (default: nano, also checks VISUAL)
  SUDO_EDITOR  Editor for sudoedit (default: same as EDITOR)
  DIFF_TOOL    Diff tool to use (default: vimdiff)
  MERGE_TOOL   Merge tool to use (default: same as DIFF_TOOL)
  USE_COLOR    Enable/disable colorized output (default: true)

EOF
    exit 0
}

# Function to find pacnew files
find_pacnew_files() {
    local search_path="$1"
    local recursive="$2"

    # Validate search path exists
    if [ ! -d "$search_path" ]; then
        print_error "Search path does not exist: $search_path"
        return 1
    fi

    print_info "Searching for .pacnew files in $search_path..."

    # Use fd if available, otherwise fall back to find
    if command -v fd >/dev/null 2>&1; then
        local fd_cmd=(fd -t f -e pacnew)

        # Never use color in fd output since we're parsing it
        # Color codes break file path detection
        fd_cmd+=(--color=never)

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

# Function to safely edit a file using sudoedit if available, fallback to manual safe edit
safe_edit() {
    local source_file="$1"

    # Check if sudoedit is available and use it preferentially
    if command -v sudoedit >/dev/null 2>&1; then
        print_info "Using sudoedit for safe editing"

        # Set SUDO_EDITOR if not already set
        export SUDO_EDITOR="${SUDO_EDITOR:-$EDITOR}"

        if [ "$DEBUG" = "true" ]; then
            print_info "SUDO_EDITOR is set to: $SUDO_EDITOR"
            print_info "Launching sudoedit for: $source_file"
        fi

        # Use sudoedit which handles all the safety for us
        if sudoedit "$source_file"; then
            print_success "Changes applied to $source_file"
            yad --center --title="Success" --image="dialog-information" \
                --text="<b>Changes applied successfully!</b>" \
                --timeout=2 --timeout-indicator=bottom \
                --button="ok:0"
            return 0
        else
            # Check if user cancelled or if there was an error
            if [ $? -eq 130 ]; then  # User cancelled (Ctrl+C)
                print_info "Editing cancelled"
            else
                print_error "Failed to edit $source_file"
                yad --center --title="Error" --image="dialog-error" \
                    --text="<b>Failed to edit file!</b>\n\nCheck terminal for details." \
                    --button="ok:0"
            fi
            return 1
        fi
    else
        # Fallback to manual safe edit implementation
        print_info "sudoedit not available, using built-in safe edit"

        local basename_file=$(basename "$source_file")
        # Add PID to temp file name to avoid collisions
        local temp_file="$TEMP_DIR/${basename_file}.$$"

        # Check if source file is readable
        if ! sudo test -r "$source_file"; then
            print_error "Cannot read file: $source_file"
            yad --center --title="Error" --image="dialog-error" \
                --text="<b>Cannot read file:</b>\n$source_file\n\nPermission denied." \
                --width=400 --button="OK:0"
            return 1
        fi

        # Create a copy of the source file
        if ! sudo cp "$source_file" "$temp_file"; then
            print_error "Failed to create temporary copy of $source_file"
            return 1
        fi

        # Set correct permissions for editing
        chmod 600 "$temp_file"

        # Make sure user owns the temp file
        chown "$USER:$USER" "$temp_file" 2>/dev/null

        # Get modification time before editing
        local mtime_before=$(stat -c %Y "$temp_file")

        if [ "$DEBUG" = "true" ]; then
            print_info "Temp file: $temp_file"
            print_info "Modification time before: $mtime_before"
            print_info "Launching editor: $EDITOR"
        fi

        # Edit the file
        $EDITOR "$temp_file"

        # Check editor exit code
        local editor_exit=$?
        if [ "$DEBUG" = "true" ]; then
            print_info "Editor exit code: $editor_exit"
        fi

        # Get modification time after editing
        local mtime_after=$(stat -c %Y "$temp_file")

        if [ "$DEBUG" = "true" ]; then
            print_info "Modification time after: $mtime_after"
            if [ "$mtime_before" = "$mtime_after" ]; then
                print_warning "File was NOT modified (times match)"
            else
                print_success "File WAS modified (times differ)"
                print_info "Temp file contents preview:"
                head -5 "$temp_file" >&2
            fi
        fi

        # Check if the file was modified
        if [ "$mtime_before" != "$mtime_after" ]; then
            # Ask for confirmation before applying changes
            yad --center --title="Confirm Changes" --image="dialog-question" \
                --text="<b>Apply changes to:</b>\n<tt>$source_file</tt>?" \
                --width=500 \
                --button="cancel:1" --button=" apply:0"

            if [ $? -eq 0 ]; then
                # Apply changes
                if sudo cp "$temp_file" "$source_file"; then
                    print_success "Changes applied to $source_file"
                    yad --center --title="Success" --image="dialog-information" \
                        --text="<b>Changes applied successfully!</b>" \
                        --timeout=2 --timeout-indicator=bottom \
                        --button="ok:0"
                    return 0
                else
                    print_error "Failed to apply changes to $source_file"
                    yad --center --title="Error" --image="dialog-error" \
                        --text="<b>Failed to apply changes!</b>\n\nCheck terminal for details." \
                        --button="ok:0"
                    return 1
                fi
            else
                print_info "Changes discarded"
                return 1
            fi
        else
            yad --center --title="No Changes" --image="dialog-information" \
                --text="<b>No changes were made to the file.</b>" \
                --button="ok:0"
            return 1
        fi
    fi
}

# Process command line arguments
search_path="/etc"
recursive=false
default_diff=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            ;;
        -p|--path)
            if [ -z "$2" ]; then
                print_error "Option -p requires an argument"
                exit 1
            fi
            search_path="$2"
            shift 2
            ;;
        -e|--editor)
            if [ -z "$2" ]; then
                print_error "Option -e requires an argument"
                exit 1
            fi
            EDITOR="$2"
            shift 2
            ;;
        -d|--diff)
            default_diff=true
            shift
            ;;
        -m|--merge)
            if [ -z "$2" ]; then
                print_error "Option -m requires an argument"
                exit 1
            fi
            MERGE_TOOL="$2"
            shift 2
            ;;
        -r|--recurse)
            recursive=true
            shift
            ;;
        -N|--no-color)
            USE_COLOR=false
            # Update color variables
            COLOR_RED=''
            COLOR_GREEN=''
            COLOR_YELLOW=''
            COLOR_BLUE=''
            COLOR_BOLD=''
            COLOR_RESET=''
            shift
            ;;
        -v|--version)
            echo "pacmaster.sh version $VERSION"
            exit 0
            ;;
        --debug)
            DEBUG=true
            shift
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help to see available options."
            exit 1
            ;;
    esac
done

# Show current configuration if in debug mode
if [ "$DEBUG" = "true" ]; then
    print_info "Current configuration:"
    echo "  EDITOR: $EDITOR" >&2
    echo "  SUDO_EDITOR: $SUDO_EDITOR" >&2
    echo "  DIFF_TOOL: $DIFF_TOOL" >&2
    echo "  MERGE_TOOL: $MERGE_TOOL" >&2
    echo "  Search path: $search_path" >&2
    echo "  Recursive: $recursive" >&2
    if command -v sudoedit >/dev/null 2>&1; then
        echo "  sudoedit: available" >&2
    else
        echo "  sudoedit: not available (using fallback)" >&2
    fi
fi

# Check for required dependencies
check_dependencies

# Validate search path
if [ ! -d "$search_path" ]; then
    print_error "Search path does not exist: $search_path"
    yad --center --title="$TITLE" --image="dialog-error" \
        --text="<b>Error: Invalid search path</b>\n\n<tt>$search_path</tt> does not exist or is not a directory." \
        --width=400 --button="ok:0"
    exit 1
fi

# Check if we have permission to read the search path
if [ ! -r "$search_path" ]; then
    print_warning "Need elevated privileges to search in $search_path"
    # Try with sudo - also need to export the print functions and color variables
    pacnew_files=$(sudo bash -c "$(declare -f find_pacnew_files print_info print_error); COLOR_BLUE=''; COLOR_RESET=''; COLOR_RED=''; find_pacnew_files '$search_path' '$recursive'")
else
    # Find pacnew files
    pacnew_files=$(find_pacnew_files "$search_path" "$recursive")
fi

# Strip any remaining ANSI color codes from the output (safety measure)
pacnew_files=$(echo "$pacnew_files" | sed 's/\x1b\[[0-9;]*m//g')

# Debug: Show raw output
if [ "$DEBUG" = "true" ]; then
    print_info "Raw pacnew_files output:"
    echo "$pacnew_files" | cat -A >&2  # Show all characters including hidden ones
fi

# Check if there was an error with find command
if [ $? -ne 0 ]; then
    yad --center --title="$TITLE" --image="dialog-error" \
        --text="<b>Error searching for .pacnew files</b>\n\nThere was an error searching in:\n<tt>$search_path</tt>\n\nPlease check the terminal output for details." \
        --width=400 --button="ok:0"
    print_error "Error searching for .pacnew files in $search_path."
    exit 1
fi

if [ -z "$pacnew_files" ]; then
    yad --center --title="$TITLE" --image="dialog-information" \
        --text="<b>No .pacnew files found</b>\n\nThere are no pending configuration files to review in:\n<tt>$search_path</tt>\n\nThis means your system configuration is up-to-date!" \
        --width=450 --button="ok:0"
    print_info "No .pacnew files found in $search_path."
    exit 0
fi

# Count files found
file_count=$(echo "$pacnew_files" | wc -l)
print_success "Found $file_count .pacnew file(s)"

# Get the file list into an array
mapfile -t pacnew_array <<< "$pacnew_files"

# Debug: Show what files we found
if [ "$DEBUG" = "true" ]; then
    print_info "Files in array:"
    for i in "${!pacnew_array[@]}"; do
        echo "  [$i]: '${pacnew_array[$i]}'" >&2
    done
fi

# Create a temporary file for YAD output
tmp_file="$TEMP_DIR/yad_output"

# Function to display file selection dialog
show_file_selection() {
    local pacnew_files=("$@")

    if [ "$DEBUG" = "true" ]; then
        print_info "show_file_selection called with ${#pacnew_files[@]} files"
        for f in "${pacnew_files[@]}"; do
            echo "  File: '$f'" >&2
        done
    fi

    local yad_cmd=(
        yad --center --title="$TITLE" --width=900 --height=500
        --text="<b>Found ${#pacnew_files[@]} .pacnew file(s)</b>\nSelect a file to manage:"
        --list --column="ID:NUM" --column="Path:TEXT" --column="Size:TEXT" --column="Modified:TEXT"
        --print-column=2
        --button="refresh:2"
        --button="close:1"
        --button="edit:0"
    )

    # Add rows to YAD command
    local id=1
    local files_added=0
    for file in "${pacnew_files[@]}"; do
        # Skip empty entries
        if [ -z "$file" ]; then
            [ "$DEBUG" = "true" ] && echo "  Skipping empty file entry" >&2
            continue
        fi

        # Check if file exists and is readable
        if [ -f "$file" ]; then
            # Check readability - might need sudo
            if [ -r "$file" ] || sudo test -r "$file" 2>/dev/null; then
                # Get file info (use sudo if needed)
                local size
                local modified
                if [ -r "$file" ]; then
                    size=$(du -h "$file" 2>/dev/null | cut -f1)
                    modified=$(stat -c "%y" "$file" 2>/dev/null | cut -d. -f1)
                else
                    size=$(sudo du -h "$file" 2>/dev/null | cut -f1)
                    modified=$(sudo stat -c "%y" "$file" 2>/dev/null | cut -d. -f1)
                fi

                # Ensure we have valid data before adding
                if [ -n "$size" ] && [ -n "$modified" ]; then
                    yad_cmd+=("$id" "$file" "$size" "$modified")
                    ((id++))
                    ((files_added++))
                    [ "$DEBUG" = "true" ] && echo "  Added: $file (size: $size)" >&2
                else
                    [ "$DEBUG" = "true" ] && echo "  Could not get info for: '$file'" >&2
                fi
            else
                [ "$DEBUG" = "true" ] && echo "  File not readable: '$file'" >&2
            fi
        else
            [ "$DEBUG" = "true" ] && echo "  File not found: '$file'" >&2
        fi
    done

    if [ "$DEBUG" = "true" ]; then
        print_info "Total files added to dialog: $files_added"
        echo "YAD command has ${#yad_cmd[@]} elements" >&2
    fi

    # Run YAD and capture selected file
    if [ "$DEBUG" = "true" ]; then
        print_info "Running YAD dialog..."
    fi

    "${yad_cmd[@]}" > "$tmp_file" 2>/dev/null
    local result=$?

    if [ "$DEBUG" = "true" ]; then
        print_info "YAD dialog returned: $result"
        print_info "Temp file size: $(stat -c %s "$tmp_file" 2>/dev/null || echo 0) bytes"
    fi

    return $result
}

# First show of file selection
show_file_selection "${pacnew_array[@]}"
exit_code=$?

# Handle Refresh button (exit code 2)
while [ $exit_code -eq 2 ]; do
    print_info "Refreshing .pacnew file list..."

    if [ ! -r "$search_path" ]; then
        pacnew_files=$(sudo bash -c "$(declare -f find_pacnew_files print_info print_error); COLOR_BLUE=''; COLOR_RESET=''; COLOR_RED=''; find_pacnew_files '$search_path' '$recursive'")
    else
        pacnew_files=$(find_pacnew_files "$search_path" "$recursive")
    fi

    # Strip any remaining ANSI color codes from the output (safety measure)
    pacnew_files=$(echo "$pacnew_files" | sed 's/\x1b\[[0-9;]*m//g')

    if [ -z "$pacnew_files" ]; then
        yad --center --title="$TITLE" --image="dialog-information" \
            --text="<b>No .pacnew files found</b>\n\nThere are no pending configuration files to review in:\n<tt>$search_path</tt>\n\nThis means your system configuration is up-to-date!" \
            --width=450 --button="ok:0"
        print_info "No .pacnew files found in $search_path."
        exit 0
    fi

    # Reload the file list
    mapfile -t pacnew_array <<< "$pacnew_files"
    file_count=$(echo "$pacnew_files" | wc -l)
    print_success "Found $file_count .pacnew file(s)"

    # Re-run YAD with the updated list
    show_file_selection "${pacnew_array[@]}"
    exit_code=$?
done

# If user clicked Close (1), exit
if [ $exit_code -eq 1 ]; then
    print_info "User closed the dialog"
    exit 0
fi

# If user clicked View/Edit (0) and selected a file
if [ $exit_code -eq 0 ]; then
    # Check if a file was actually selected
    if [ ! -s "$tmp_file" ]; then
        print_warning "No file was selected. Please select a file before clicking Edit."
        yad --center --title="No Selection" --image="dialog-warning" \
            --text="<b>No file selected</b>\n\nPlease select a file from the list before clicking Edit." \
            --width=400 --button="ok:0"
        # Re-show the file selection dialog
        exec "$0" "$@"
    fi

    # YAD outputs with a trailing pipe separator, need to remove it
    # Read the file and clean it up
    selected_file=$(cat "$tmp_file")

    # Debug: Show what was selected BEFORE cleaning
    if [ "$DEBUG" = "true" ]; then
        print_info "Raw selected file from dialog (before cleaning): '$selected_file'"
        print_info "Raw length: ${#selected_file}"
        print_info "Temp file contents with special chars:"
        cat "$tmp_file" | cat -A >&2
        print_info "Hex dump of temp file:"
        hexdump -C "$tmp_file" | head -3 >&2
    fi

    # Remove trailing pipe if present
    selected_file="${selected_file%|}"
    # Remove any trailing whitespace/newlines
    selected_file="$(echo "$selected_file" | tr -d '\n\r' | xargs)"

    # Debug: Show what was selected AFTER cleaning
    if [ "$DEBUG" = "true" ]; then
        print_info "Cleaned selected file: '$selected_file'"
        print_info "Cleaned length: ${#selected_file}"
    fi

    # Verify the selected file is valid
    if [ -z "$selected_file" ] || [ "$selected_file" = "0" ]; then
        print_error "Invalid selection: '$selected_file'"
        yad --center --title="Error" --image="dialog-error" \
            --text="<b>Invalid file selection</b>\n\nPlease try again." \
            --width=400 --button="ok:0"
        exit 1
    fi

    # Extra check: does the file actually exist?
    if [ ! -f "$selected_file" ]; then
        print_error "Selected file does not exist: '$selected_file'"
        print_info "Checking with sudo..."
        if ! sudo test -f "$selected_file"; then
            print_error "File really doesn't exist even with sudo"
            yad --center --title="Error" --image="dialog-error" \
                --text="<b>File not found:</b>\n<tt>$selected_file</tt>\n\nThe file may have been deleted." \
                --width=400 --button="ok:0"
            exit 1
        else
            print_info "File exists but requires sudo to access"
        fi
    fi

    original_file="${selected_file%.pacnew}"

    if [ "$DEBUG" = "true" ]; then
        print_info "Original file would be: '$original_file'"
    fi

    # Check if files exist and show appropriate status
    status_text="<b>Selected file:</b>\n<tt>$selected_file</tt>\n\n"
    if [ -f "$original_file" ]; then
        status_text+="<b>Original file exists:</b> <span color='green'>Yes</span>\n<tt>$original_file</tt>\n\n"
    else
        status_text+="<b>Original file exists:</b> <span color='red'>No</span>\n<tt>$original_file</tt> (will be created)\n\n"
    fi
    status_text+="<b>Choose an action:</b>"

    # Show options for the selected file
    if [ "$DEBUG" = "true" ]; then
        print_info "About to show action dialog..."
        print_info "Status text: $status_text"
    fi

    action=$(yad --center --title="$TITLE - Actions" --width=500 \
        --text="$status_text" \
        --list --no-headers --column="Action" \
        "View/Edit .pacnew file safely" \
        "Diff with original file" \
        "Merge/Edit both files" \
        "Use .pacnew (replace original)" \
        "Delete .pacnew (keep original)" \
        --print-column=1 \
        --button="cancel:1" --button="ok:0" 2>&1)

    action_code=$?

    if [ "$DEBUG" = "true" ]; then
        print_info "Action dialog returned code: $action_code"
        print_info "Action selected: '$action'"
        if [ -z "$action" ]; then
            print_warning "No action was selected or dialog failed"
        fi
    fi
    if [ "$DEBUG" = "true" ]; then
        print_info "Checking action_code ($action_code) and action ('$action')"
    fi

    if [ $action_code -eq 0 ] && [ -n "$action" ]; then
        # Remove any trailing pipe, whitespace or newlines
        action=$(echo "$action" | sed 's/|$//' | tr -d '\n' | sed 's/[[:space:]]*$//')

        if [ "$DEBUG" = "true" ]; then
            print_info "Executing action: '$action'"
        fi

        case "$action" in
            "View/Edit .pacnew file safely")
                if [ "$DEBUG" = "true" ]; then
                    print_info "Calling safe_edit for: $selected_file"
                fi
                safe_edit "$selected_file"
                edit_result=$?
                if [ "$DEBUG" = "true" ]; then
                    print_info "safe_edit returned: $edit_result"
                fi
                ;;
            "Diff with original file")
                if [ -f "$original_file" ]; then
                    print_info "Opening diff tool: $DIFF_TOOL"
                    # Create temporary copies for diff with better names
                    cp "$original_file" "$TEMP_DIR/$(basename "$original_file").original"
                    cp "$selected_file" "$TEMP_DIR/$(basename "$original_file").pacnew"
                    $DIFF_TOOL "$TEMP_DIR/$(basename "$original_file").original" \
                               "$TEMP_DIR/$(basename "$original_file").pacnew"
                else
                    yad --center --title="Error" --image="dialog-error" \
                        --text="<b>Original file not found:</b>\n<tt>$original_file</tt>\n\nCannot perform diff operation." \
                        --width=400 --button="ok:0"
                    print_error "Original file not found: $original_file"
                fi
                ;;
            "Merge/Edit both files")
                if [ -f "$original_file" ]; then
                    # Create temporary copies for merging with better names
                    cp "$original_file" "$TEMP_DIR/$(basename "$original_file").original"
                    cp "$selected_file" "$TEMP_DIR/$(basename "$original_file").pacnew"

                    # Use merge tool
                    print_info "Opening merge tool: $MERGE_TOOL"
                    $MERGE_TOOL "$TEMP_DIR/$(basename "$original_file").original" \
                                "$TEMP_DIR/$(basename "$original_file").pacnew"

                    # Ask which file to use
                    merged_choice=$(yad --center --title="Apply Changes" --width=500 \
                        --text="<b>What would you like to do with the merged result?</b>" \
                        --list --no-headers --column="Action" \
                        "Apply to original file" \
                        "Apply to .pacnew file" \
                        "Save as new file" \
                        "Discard changes" \
                        --print-column=1 \
                        --button="cancel:1" --button="ok:0")

                    if [ $? -eq 0 ] && [ -n "$merged_choice" ]; then
                        merged_choice=$(echo "$merged_choice" | tr -d '\n' | sed 's/[[:space:]]*$//')
                        case "$merged_choice" in
                            "Apply to original file")
                                if sudo cp "$TEMP_DIR/$(basename "$original_file").original" "$original_file"; then
                                    print_success "Changes applied to original file"
                                    yad --center --title="Success" --image="dialog-information" \
                                        --text="<b>Changes applied to original file:</b>\n<tt>$original_file</tt>" \
                                        --timeout=3 --timeout-indicator=bottom \
                                        --button="ok:0"
                                else
                                    print_error "Failed to apply changes to original file"
                                    yad --center --title="Error" --image="dialog-error" \
                                        --text="<b>Failed to apply changes!</b>" \
                                        --button="ok:0"
                                fi
                                ;;
                            "Apply to .pacnew file")
                                if sudo cp "$TEMP_DIR/$(basename "$original_file").pacnew" "$selected_file"; then
                                    print_success "Changes applied to .pacnew file"
                                    yad --center --title="Success" --image="dialog-information" \
                                        --text="<b>Changes applied to .pacnew file:</b>\n<tt>$selected_file</tt>" \
                                        --timeout=3 --timeout-indicator=bottom \
                                        --button="ok:0"
                                else
                                    print_error "Failed to apply changes to .pacnew file"
                                    yad --center --title="Error" --image="dialog-error" \
                                        --text="<b>Failed to apply changes!</b>" \
                                        --button="ok:0"
                                fi
                                ;;
                            "Save as new file")
                                save_path=$(yad --center --title="Save File" --file --save \
                                    --filename="$original_file.merged")
                                if [ -n "$save_path" ]; then
                                    if cp "$TEMP_DIR/$(basename "$original_file").original" "$save_path"; then
                                        chmod 644 "$save_path"
                                        print_success "File saved as: $save_path"
                                        yad --center --title="Success" --image="dialog-information" \
                                            --text="<b>File saved as:</b>\n<tt>$save_path</tt>" \
                                            --timeout=3 --timeout-indicator=bottom \
                                            --button="ok:0"
                                    else
                                        print_error "Failed to save file to: $save_path"
                                        yad --center --title="Error" --image="dialog-error" \
                                            --text="<b>Failed to save file to:</b>\n<tt>$save_path</tt>" \
                                            --button="ok:0"
                                    fi
                                fi
                                ;;
                            "Discard changes")
                                print_info "Changes discarded"
                                ;;
                        esac
                    fi
                else
                    yad --center --title="Error" --image="dialog-error" \
                        --text="<b>Original file not found:</b>\n<tt>$original_file</tt>\n\nCannot perform merge operation." \
                        --width=400 --button="ok:0"
                    print_error "Original file not found: $original_file"
                fi
                ;;
            "Use .pacnew (replace original)")
                if [ -f "$original_file" ]; then
                    yad --center --title="Confirm Replace" --image="dialog-warning" \
                        --text="<b>⚠ Warning: This will replace the original file!</b>\n\n<b>Replace:</b>\n<tt>$original_file</tt>\n\n<b>With:</b>\n<tt>$selected_file</tt>\n\nA backup will be created as:\n<tt>$original_file.bak</tt>" \
                        --width=500 \
                        --button="cancel:1" --button="ok:0"

                    if [ $? -eq 0 ]; then
                        # Create backup of original
                        if sudo cp "$original_file" "$original_file.bak"; then
                            # Replace original with pacnew
                            if sudo cp "$selected_file" "$original_file" && sudo rm "$selected_file"; then
                                print_success "File replaced successfully"
                                yad --center --title="Success" --image="dialog-information" \
                                    --text="<b>File replaced successfully!</b>\n\nBackup saved as:\n<tt>$original_file.bak</tt>" \
                                    --timeout=3 --timeout-indicator=bottom \
                                    --button="ok:0"
                            else
                                print_error "Failed to replace original file"
                                yad --center --title="Error" --image="dialog-error" \
                                    --text="<b>Failed to replace original file!</b>\n\nCheck terminal for details." \
                                    --button="ok:0"
                            fi
                        else
                            print_error "Failed to create backup of original file"
                            yad --center --title="Error" --image="dialog-error" \
                                --text="<b>Failed to create backup of original file!</b>\n\nOperation cancelled." \
                                --button="ok:0"
                        fi
                    fi
                else
                    # Original doesn't exist, just move pacnew to original location
                    yad --center --title="Confirm Install" --image="dialog-question" \
                        --text="<b>Original file does not exist.</b>\n\nInstall .pacnew file as:\n<tt>$original_file</tt>?" \
                        --width=400 \
                        --button="cancel:1" --button="ok:0"

                    if [ $? -eq 0 ]; then
                        if sudo cp "$selected_file" "$original_file" && sudo rm "$selected_file"; then
                            print_success "File installed successfully"
                            yad --center --title="Success" --image="dialog-information" \
                                --text="<b>File installed successfully!</b>\n\n<tt>$original_file</tt>" \
                                --timeout=3 --timeout-indicator=bottom \
                                --button="ok:0"
                        else
                            print_error "Failed to install file"
                            yad --center --title="Error" --image="dialog-error" \
                                --text="<b>Failed to install file!</b>\n\nCheck terminal for details." \
                                --button="ok:0"
                        fi
                    fi
                fi
                ;;
            "Delete .pacnew (keep original)")
                yad --center --title="Confirm Delete" --image="dialog-warning" \
                    --text="<b>Are you sure you want to delete:</b>\n<tt>$selected_file</tt>?\n\nThis action cannot be undone." \
                    --width=400 \
                    --button="cancel:1" --button=" delete:0"

                if [ $? -eq 0 ]; then
                    if sudo rm "$selected_file"; then
                        print_success "File deleted successfully"
                        yad --center --title="Success" --image="dialog-information" \
                            --text="<b>File deleted successfully!</b>" \
                            --timeout=2 --timeout-indicator=bottom \
                            --button="ok:0"
                    else
                        print_error "Failed to delete file"
                        yad --center --title="Error" --image="dialog-error" \
                            --text="<b>Failed to delete file!</b>\n\nCheck terminal for details." \
                            --button="ok:0"
                    fi
                fi
                ;;
        esac
    else
        if [ "$DEBUG" = "true" ]; then
            print_info "Action dialog was cancelled or no action selected"
            print_info "action_code: $action_code, action: '$action'"
        fi
    fi
else
    if [ "$DEBUG" = "true" ]; then
        print_info "Script ending - exit_code was not 0 or tmp_file issue"
        print_info "exit_code: $exit_code"
    fi
fi

exit 0
