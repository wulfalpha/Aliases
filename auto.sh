#!/bin/bash

# auto.sh - Polymorphic script to manage autostart applications
# Supports different behaviors based on how it's symlinked
# Dependencies: fzf, fd (fallback to find)

set -o pipefail

# Configuration file path
CONFIG_FILE="$HOME/.config/auto.conf"

# Default configuration
AUTOSTART_DIR="$HOME/.config/autostart"
FZF_CMD="fzf -m --reverse --height=40% --border"
CACHE_EXPIRY=3600  # Cache expires after 1 hour (in seconds)
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/auto-sh"
DESKTOP_CACHE="$CACHE_DIR/desktop-files.cache"

# Load configuration if exists
if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

# Create required directories
mkdir -p "$AUTOSTART_DIR" "$CACHE_DIR"

# Script name detection
SCRIPT_NAME=$(basename "$0")

# Error handling function
handle_error() {
    local exit_code=$1
    local error_msg=$2
    echo "Error: $error_msg" >&2
    exit "$exit_code"
}

# Check for required dependencies
check_dependencies() {
    local missing=()

    if ! command -v fzf &> /dev/null; then
        missing+=("fzf")
    fi

    # Check for fd-find with fallback to find
    if ! command -v fd &> /dev/null && ! command -v find &> /dev/null; then
        missing+=("fd or find")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        handle_error 1 "Missing dependencies: ${missing[*]}\nPlease install the missing dependencies to use this script."
    fi

    return 0
}

# Cache management
refresh_cache() {
    local cache_file="$1"
    local cache_age=0

    if [[ -f "$cache_file" ]]; then
        cache_age=$(($(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file")))
    fi

    # If cache doesn't exist or is too old, refresh it
    if [[ ! -f "$cache_file" ]] || [[ "$cache_age" -gt "$CACHE_EXPIRY" ]]; then
        find_desktop_files > "$cache_file"
        if [[ $? -ne 0 ]]; then
            rm -f "$cache_file"
            handle_error 2 "Failed to refresh desktop files cache."
        fi
    fi
}

# Find desktop files function with fd fallback to find
find_desktop_files() {
    local search_paths=(
        "/usr/share/applications"
        "/usr/local/share/applications"
        "$HOME/.local/share/applications"
    )

    if command -v fd &> /dev/null; then
        # Use fd if available
        fd -e desktop . "${search_paths[@]}" 2>/dev/null
    else
        # Fallback to find
        find "${search_paths[@]}" -name "*.desktop" -type f 2>/dev/null
    fi
}

# Get readable name from desktop file with localization support
get_app_name() {
    local desktop_file="$1"
    local name
    local locale="${LANG%%.*}"
    local locale_short="${locale%%_*}"

    # Try localized name first
    if [[ -n "$locale" ]]; then
        name=$(grep -oP "^Name\[$locale\]=\K.*" "$desktop_file" 2>/dev/null | head -n1)
    fi

    # Try short locale name
    if [[ -z "$name" && -n "$locale_short" ]]; then
        name=$(grep -oP "^Name\[$locale_short\]=\K.*" "$desktop_file" 2>/dev/null | head -n1)
    fi

    # Try standard name
    if [[ -z "$name" ]]; then
        name=$(grep -oP "^Name=\K.*" "$desktop_file" 2>/dev/null | head -n1)
    fi

    # If Name field is empty, use the filename
    if [[ -z "$name" ]]; then
        name=$(basename "$desktop_file" .desktop)
    fi

    echo "$name"
}

# Validate desktop file
validate_desktop_file() {
    local desktop_file="$1"

    # Check if file exists
    if [[ ! -f "$desktop_file" ]]; then
        return 1
    fi

    # Check if it has the required Desktop Entry section
    if ! grep -q "^\[Desktop Entry\]" "$desktop_file"; then
        return 1
    fi

    # Check if it has an Exec line
    if ! grep -q "^Exec=" "$desktop_file"; then
        return 1
    fi

    return 0
}

# List autostart entries
list_autostart() {
    echo "Current autostart applications:"
    echo "------------------------------"

    # Check if directory is empty
    if [[ -z "$(find "$AUTOSTART_DIR" -maxdepth 1 -name "*.desktop" -type f -o -name "*.desktop" -type l 2>/dev/null)" ]]; then
        echo "No applications configured to autostart."
        return 0
    fi

    # Use shopt to avoid nullglob issues
    shopt -s nullglob
    local desktop_files=("$AUTOSTART_DIR"/*.desktop)
    shopt -u nullglob

    for desktop_file in "${desktop_files[@]}"; do
        if [[ -L "$desktop_file" ]]; then
            local target
            target=$(readlink -f "$desktop_file")
            local name
            name=$(get_app_name "$target")
            echo "• $name ($(basename "$desktop_file"))"
        elif [[ -f "$desktop_file" ]]; then
            local name
            name=$(get_app_name "$desktop_file")
            echo "• $name ($(basename "$desktop_file"))"
        fi
    done

    return 0
}

# Add applications to autostart
add_to_autostart() {
    # Refresh cache before using it
    refresh_cache "$DESKTOP_CACHE"

    local desktop_files
    if ! mapfile -t desktop_files < <(
        while IFS= read -r file; do
            if validate_desktop_file "$file"; then
                local name
                name=$(get_app_name "$file")
                echo "$name :: $file"
            fi
        done < "$DESKTOP_CACHE" | sort | $FZF_CMD --header="Select applications to add to autostart (TAB to select multiple)"
    ); then
        echo "Selection cancelled."
        return 0
    fi

    if [[ ${#desktop_files[@]} -eq 0 ]]; then
        echo "No applications selected."
        return 0
    fi

    echo "Adding selected applications to autostart..."
    local success_count=0
    local skip_count=0
    local fail_count=0

    for entry in "${desktop_files[@]}"; do
        local file="${entry##* :: }"
        local name="${entry%% :: *}"
        local target_file="$AUTOSTART_DIR/$(basename "$file")"

        if [[ -e "$target_file" ]]; then
            echo "• $name is already in autostart."
            ((skip_count++))
        else
            if ln -s "$file" "$target_file" 2>/dev/null; then
                echo "• Added $name to autostart."
                ((success_count++))
            else
                echo "• Failed to add $name to autostart. Check permissions."
                ((fail_count++))
            fi
        fi
    done

    echo "Summary: Added $success_count, Skipped $skip_count, Failed $fail_count"
    return 0
}

# Remove applications from autostart
remove_from_autostart() {
    # Check if directory is empty
    if [[ -z "$(find "$AUTOSTART_DIR" -maxdepth 1 -name "*.desktop" -type f -o -name "*.desktop" -type l 2>/dev/null)" ]]; then
        echo "No applications configured to autostart."
        return 0
    fi

    local autostart_files
    if ! mapfile -t autostart_files < <(
        find "$AUTOSTART_DIR" -name "*.desktop" -type f -o -name "*.desktop" -type l |
        while IFS= read -r file; do
            local name
            if [[ -L "$file" ]]; then
                local target
                target=$(readlink -f "$file")
                name=$(get_app_name "$target")
            else
                name=$(get_app_name "$file")
            fi
            echo "$name :: $file"
        done | sort | $FZF_CMD --header="Select applications to remove from autostart (TAB to select multiple)"
    ); then
        echo "Selection cancelled."
        return 0
    fi

    if [[ ${#autostart_files[@]} -eq 0 ]]; then
        echo "No applications selected for removal."
        return 0
    fi

    echo "Removing selected applications from autostart..."
    local success_count=0
    local fail_count=0

    for entry in "${autostart_files[@]}"; do
        local file="${entry##* :: }"
        local name="${entry%% :: *}"

        if [[ -e "$file" ]]; then
            if rm "$file" 2>/dev/null; then
                echo "• Removed $name from autostart."
                ((success_count++))
            else
                echo "• Failed to remove $name from autostart. Check permissions."
                ((fail_count++))
            fi
        fi
    done

    echo "Summary: Removed $success_count, Failed $fail_count"
    return 0
}

# Edit autostart entry
edit_autostart() {
    # Check if directory is empty
    if [[ -z "$(find "$AUTOSTART_DIR" -maxdepth 1 -name "*.desktop" -type f -o -name "*.desktop" -type l 2>/dev/null)" ]]; then
        echo "No applications configured to autostart."
        return 0
    fi

    local autostart_file
    if ! autostart_file=$(
        find "$AUTOSTART_DIR" -name "*.desktop" -type f -o -name "*.desktop" -type l |
        while IFS= read -r file; do
            local name
            if [[ -L "$file" ]]; then
                local target
                target=$(readlink -f "$file")
                name=$(get_app_name "$target")
            else
                name=$(get_app_name "$file")
            fi
            echo "$name :: $file"
        done | sort | $FZF_CMD --header="Select an application to edit" --height=40% | awk -F ' :: ' '{print $2}'
    ); then
        echo "Selection cancelled."
        return 0
    fi

    if [[ -z "$autostart_file" ]]; then
        echo "No application selected."
        return 0
    fi

    # If it's a symlink, make a copy of the target to edit
    if [[ -L "$autostart_file" ]]; then
        local target
        target=$(readlink -f "$autostart_file")
        local new_file="$AUTOSTART_DIR/$(basename "$autostart_file")"

        # Remove the symlink
        rm "$autostart_file"

        # Copy the target file
        if ! cp "$target" "$new_file"; then
            handle_error 3 "Failed to copy desktop file for editing."
        fi

        autostart_file="$new_file"
        echo "• Created editable copy of $(get_app_name "$target")"
    fi

    # Use the default editor
    ${VISUAL:-${EDITOR:-nano}} "$autostart_file"

    echo "• Saved changes to $(get_app_name "$autostart_file")"
    return 0
}

# Create a new custom autostart entry
create_autostart() {
    local template_file="$AUTOSTART_DIR/custom-$(date +%s).desktop"

    cat > "$template_file" << EOF
[Desktop Entry]
Type=Application
Name=Custom Application
Comment=Custom autostart entry
Exec=
Terminal=false
X-GNOME-Autostart-enabled=true
EOF

    # Use the default editor
    ${VISUAL:-${EDITOR:-nano}} "$template_file"

    # Validate the file after editing
    if ! validate_desktop_file "$template_file"; then
        echo "Warning: The desktop file may not be valid. Please check the Exec= line."
    fi

    echo "• Created custom autostart entry: $(get_app_name "$template_file")"
    return 0
}

# Display help information
show_help() {
    cat << EOF
auto.sh - Manage autostart applications using fzf
Usage:
  auto.sh                   - List all current autostart applications
  auto-start.sh             - Select and add applications to autostart
  auto-remove.sh            - Select and remove applications from autostart
  auto-edit.sh              - Edit an existing autostart entry
  auto-create.sh            - Create a new custom autostart entry
  auto-help.sh              - Show this help information

Dependencies:
  • fzf      - Fuzzy finder for selection
  • fd       - Alternative to find (will fall back to find if not available)

Configuration:
  You can create a custom configuration file at:
  $CONFIG_FILE

  Example configuration:
  AUTOSTART_DIR="$HOME/.config/custom-autostart"
  FZF_CMD="fzf -m --reverse --height=60% --border"
  CACHE_EXPIRY=7200  # 2 hours

Setup:
  1. Make the script executable:
     chmod +x auto.sh

  2. Create symbolic links for different functionalities:
     ln -s auto.sh auto-start.sh
     ln -s auto.sh auto-remove.sh
     ln -s auto.sh auto-edit.sh
     ln -s auto.sh auto-create.sh
     ln -s auto.sh auto-help.sh

  3. Add the directory containing these scripts to your PATH

Usage Tips:
  • Use TAB to select multiple applications at once
  • Press ESC to cancel selection
  • Desktop files are searched from standard locations
  • The cache refreshes automatically after $CACHE_EXPIRY seconds
EOF
}

# Main execution logic based on how the script was called
main() {
    check_dependencies

    case "$SCRIPT_NAME" in
        "auto-start.sh")
            add_to_autostart
            ;;
        "auto-remove.sh")
            remove_from_autostart
            ;;
        "auto-edit.sh")
            edit_autostart
            ;;
        "auto-create.sh")
            create_autostart
            ;;
        "auto-help.sh")
            show_help
            ;;
        *)
            list_autostart
            ;;
    esac

    return 0
}

# Execute main function
main
