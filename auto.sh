#!/bin/bash

# auto.sh - Polymorphic script to manage autostart applications
# Supports different behaviors based on how it's symlinked
# Dependencies: fzf, fd (fallback to find)

# Configuration
AUTOSTART_DIR="$HOME/.config/autostart"
SCRIPT_NAME=$(basename "$0")
FZF_CMD="fzf -m --reverse --height=40% --border"

# Create autostart directory if it doesn't exist
mkdir -p "$AUTOSTART_DIR"

# Check for required dependencies
check_dependencies() {
  local missing=()
  
  if ! command -v fzf &> /dev/null; then
    missing+=("fzf")
  fi
  
  # Check for fd-find with fallback to find
  if ! command -v fd &> /dev/null; then
    if ! command -v find &> /dev/null; then
      missing+=("fd or find")
    fi
  fi
  
  if [ ${#missing[@]} -gt 0 ]; then
    echo "Missing dependencies: ${missing[*]}"
    echo "Please install the missing dependencies to use this script."
    exit 1
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

# Get readable name from desktop file
get_app_name() {
  local desktop_file="$1"
  local name
  
  # Try to get the Name field from the desktop file
  name=$(grep -oP "^Name=\K.*" "$desktop_file" 2>/dev/null | head -n1)
  
  # If Name field is empty, use the filename
  if [ -z "$name" ]; then
    name=$(basename "$desktop_file" .desktop)
  fi
  
  echo "$name"
}

# List autostart entries
list_autostart() {
  echo "Current autostart applications:"
  echo "------------------------------"
  
  if [ -z "$(ls -A "$AUTOSTART_DIR")" ]; then
    echo "No applications configured to autostart."
    return
  fi
  
  for desktop_file in "$AUTOSTART_DIR"/*.desktop; do
    if [ -L "$desktop_file" ]; then
      local target=$(readlink -f "$desktop_file")
      local name=$(get_app_name "$target")
      echo "• $name ($(basename "$desktop_file"))"
    elif [ -f "$desktop_file" ]; then
      local name=$(get_app_name "$desktop_file")
      echo "• $name ($(basename "$desktop_file"))"
    fi
  done
}

# Add applications to autostart
add_to_autostart() {
  local desktop_files
  mapfile -t desktop_files < <(find_desktop_files | sort | while read -r file; do
    local name=$(get_app_name "$file")
    echo "$name :: $file"
  done | $FZF_CMD --header="Select applications to add to autostart (TAB to select multiple)")
  
  if [ ${#desktop_files[@]} -eq 0 ]; then
    echo "No applications selected."
    return
  fi
  
  echo "Adding selected applications to autostart..."
  for entry in "${desktop_files[@]}"; do
    local file="${entry##* :: }"
    local name="${entry%% :: *}"
    local target_file="$AUTOSTART_DIR/$(basename "$file")"
    
    if [ -e "$target_file" ]; then
      echo "• $name is already in autostart."
    else
      ln -s "$file" "$target_file"
      echo "• Added $name to autostart."
    fi
  done
}

# Remove applications from autostart
remove_from_autostart() {
  if [ -z "$(ls -A "$AUTOSTART_DIR")" ]; then
    echo "No applications configured to autostart."
    return
  fi
  
  local autostart_files
  mapfile -t autostart_files < <(find "$AUTOSTART_DIR" -name "*.desktop" -type f -o -name "*.desktop" -type l | sort | while read -r file; do
    if [ -L "$file" ]; then
      local target=$(readlink -f "$file")
      local name=$(get_app_name "$target")
    else
      local name=$(get_app_name "$file")
    fi
    echo "$name :: $file"
  done | $FZF_CMD --header="Select applications to remove from autostart (TAB to select multiple)")
  
  if [ ${#autostart_files[@]} -eq 0 ]; then
    echo "No applications selected for removal."
    return
  fi
  
  echo "Removing selected applications from autostart..."
  for entry in "${autostart_files[@]}"; do
    local file="${entry##* :: }"
    local name="${entry%% :: *}"
    
    if [ -e "$file" ]; then
      rm "$file"
      echo "• Removed $name from autostart."
    fi
  done
}

# Display help information
show_help() {
  cat << EOF
auto.sh - Manage autostart applications using fzf
Usage:
  auto.sh                   - List all current autostart applications
  auto-start.sh             - Select and add applications to autostart
  auto-remove.sh            - Select and remove applications from autostart
  auto-help.sh              - Show this help information

Dependencies:
  • fzf      - Fuzzy finder for selection
  • fd       - Alternative to find (will fall back to find if not available)
  • zoxide   - Smarter cd command

Setup:
  1. Make the script executable:
     chmod +x auto.sh
  
  2. Create symbolic links for different functionalities:
     ln -s auto.sh auto-start.sh
     ln -s auto.sh auto-remove.sh
     ln -s auto.sh auto-help.sh
  
  3. Add the directory containing these scripts to your PATH

Usage Tips:
  • Use TAB to select multiple applications at once
  • Press ESC to cancel selection
  • Desktop files are searched from standard locations
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
    "auto-help.sh")
      show_help
      ;;
    *)
      list_autostart
      ;;
  esac
}

main
