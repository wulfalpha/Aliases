#!/usr/bin/env bash
# Script to display hotkeys from Hyprland, Qtile, i3, or Sway config files without modifying them
# Dependencies: yad, rg (ripgrep), and at least one of: glow, mdcat, bat
# Usage: ./hotkeys.sh [--renderer=<glow|mdcat|bat>]

# Color definitions for better terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Check dependencies
check_dependency() {
    if ! command -v "$1" &> /dev/null; then
        echo -e "${RED}Error: $1 is not installed. Please install it to continue.${NC}"
        exit 1
    fi
}

check_dependency "yad"
check_dependency "rg"

# Check for available markdown renderers
AVAILABLE_RENDERERS=()
RENDERER_COMMANDS=()

if command -v glow &> /dev/null; then
    AVAILABLE_RENDERERS+=("glow")
    RENDERER_COMMANDS+=("glow")
fi

if command -v mdcat &> /dev/null; then
    AVAILABLE_RENDERERS+=("mdcat")
    RENDERER_COMMANDS+=("mdcat")
fi

if command -v bat &> /dev/null; then
    AVAILABLE_RENDERERS+=("bat")
    RENDERER_COMMANDS+=("bat --language markdown --style=plain")
fi

# Check if any renderers are available
if [ ${#AVAILABLE_RENDERERS[@]} -eq 0 ]; then
    echo -e "${RED}Error: No markdown renderer found. Please install glow, mdcat, or bat.${NC}"
    exit 1
fi

# Default to the first available renderer
MD_RENDERER=${AVAILABLE_RENDERERS[0]}
MD_RENDER_CMD=${RENDERER_COMMANDS[0]}

# If more than one renderer is available, offer a choice if not running in a script and no specific renderer was requested
if [ -z "$FORCE_RENDERER" ] && [ ${#AVAILABLE_RENDERERS[@]} -gt 1 ] && [ -t 1 ]; then
    echo -e "${BLUE}Multiple markdown renderers available:${NC}"
    for i in "${!AVAILABLE_RENDERERS[@]}"; do
        echo -e "  ${YELLOW}$((i+1))${NC}. ${GREEN}${AVAILABLE_RENDERERS[$i]}${NC}"
    done
    
    echo -ne "${YELLOW}Select renderer (1-${#AVAILABLE_RENDERERS[@]}) [default=${MD_RENDERER}]: ${NC}"
    read -r choice
    
    if [[ -n "$choice" && "$choice" =~ ^[0-9]+$ && "$choice" -le "${#AVAILABLE_RENDERERS[@]}" && "$choice" -gt 0 ]]; then
        MD_RENDERER=${AVAILABLE_RENDERERS[$((choice-1))]}
        MD_RENDER_CMD=${RENDERER_COMMANDS[$((choice-1))]}
    fi
fi

echo -e "${GREEN}Using markdown renderer: $MD_RENDERER${NC}"

# Process command line arguments
for arg in "$@"; do
    case $arg in
        --renderer=*)
            FORCE_RENDERER="${arg#*=}"
            ;;
        --help)
            echo "Usage: $0 [--renderer=<glow|mdcat|bat>]"
            echo "Options:"
            echo "  --renderer=<name>  Force using a specific markdown renderer"
            echo "  --help             Display this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Apply renderer choice if specified via command line
if [ -n "$FORCE_RENDERER" ]; then
    RENDERER_FOUND=0
    for i in "${!AVAILABLE_RENDERERS[@]}"; do
        if [ "${AVAILABLE_RENDERERS[$i]}" = "$FORCE_RENDERER" ]; then
            MD_RENDERER="${AVAILABLE_RENDERERS[$i]}"
            MD_RENDER_CMD="${RENDERER_COMMANDS[$i]}"
            RENDERER_FOUND=1
            break
        fi
    done
    
    if [ $RENDERER_FOUND -eq 0 ]; then
        echo -e "${RED}Error: Requested renderer '$FORCE_RENDERER' not found.${NC}"
        echo -e "${YELLOW}Available renderers: ${AVAILABLE_RENDERERS[*]}${NC}"
        exit 1
    fi
fi

# Determine the desktop environment and set config directory accordingly
WM_TYPE=""
CONF_DIR=""
CONFIG_FILE=""
KEYBIND_PATTERN=""

if [ "$XDG_CURRENT_DESKTOP" = "Hyprland" ]; then
    echo -e "${GREEN}Detected Hyprland environment${NC}"
    WM_TYPE="hyprland"
    CONF_DIR="$HOME/.config/hypr"
    CONFIG_FILE="$CONF_DIR/hyprland.conf"
    KEYBIND_PATTERN="bind ="
elif [ "$XDG_CURRENT_DESKTOP" = "qtile" ]; then
    echo -e "${GREEN}Detected qtile environment${NC}"
    WM_TYPE="qtile"
    CONF_DIR="$HOME/.config/qtile"
    CONFIG_FILE="$CONF_DIR/config.py"
    KEYBIND_PATTERN="Key\(\["
elif [ "$XDG_CURRENT_DESKTOP" = "i3" ] || [ "$XDG_SESSION_DESKTOP" = "i3" ] || [ "$I3SOCK" != "" ]; then
    echo -e "${GREEN}Detected i3 environment${NC}"
    WM_TYPE="i3"
    CONF_DIR="$HOME/.config/i3"
    CONFIG_FILE="$CONF_DIR/config"
    KEYBIND_PATTERN="^bindsym"
elif [ "$XDG_CURRENT_DESKTOP" = "sway" ] || [ "$SWAYSOCK" != "" ]; then
    echo -e "${GREEN}Detected Sway environment${NC}"
    WM_TYPE="sway"
    CONF_DIR="$HOME/.config/sway"
    CONFIG_FILE="$CONF_DIR/config"
    KEYBIND_PATTERN="^bindsym"
else
    # If auto-detection fails, ask the user
    WM_CHOICE=$(yad --title="Select Window Manager" --form --field="Window Manager:CB" "Hyprland!qtile!i3!Sway" --button="OK:0")
    case "${WM_CHOICE%%|*}" in
        "Hyprland")
            WM_TYPE="hyprland"
            CONF_DIR="$HOME/.config/hypr"
            CONFIG_FILE="$CONF_DIR/hyprland.conf"
            KEYBIND_PATTERN="bind ="
            ;;
        "qtile")
            WM_TYPE="qtile"
            CONF_DIR="$HOME/.config/qtile"
            CONFIG_FILE="$CONF_DIR/config.py"
            KEYBIND_PATTERN="Key\(\["
            ;;
        "i3")
            WM_TYPE="i3"
            CONF_DIR="$HOME/.config/i3"
            CONFIG_FILE="$CONF_DIR/config"
            KEYBIND_PATTERN="^bindsym"
            ;;
        "Sway")
            WM_TYPE="sway"
            CONF_DIR="$HOME/.config/sway"
            CONFIG_FILE="$CONF_DIR/config"
            KEYBIND_PATTERN="^bindsym"
            ;;
        *)
            echo -e "${RED}No window manager selected. Exiting.${NC}"
            exit 1
            ;;
    esac
fi

# Allow user to select a custom config file if the default doesn't exist
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${YELLOW}Config file not found at $CONFIG_FILE${NC}"
    
    # Try some alternative locations
    if [ "$WM_TYPE" = "hyprland" ]; then
        ALT_LOCATIONS=("$HOME/.config/hypr/hyprland.conf" "$HOME/.config/hypr/config.conf")
    elif [ "$WM_TYPE" = "i3" ]; then
        ALT_LOCATIONS=("$HOME/.i3/config" "$HOME/.config/i3/config" "/etc/i3/config")
    elif [ "$WM_TYPE" = "sway" ]; then
        ALT_LOCATIONS=("$HOME/.config/sway/config" "/etc/sway/config")
    elif [ "$WM_TYPE" = "qtile" ]; then
        ALT_LOCATIONS=("$HOME/.config/qtile/config.py" "$HOME/.config/qtile/config")
    fi
    
    # Check alternative locations
    for alt in "${ALT_LOCATIONS[@]}"; do
        if [ -f "$alt" ]; then
            CONFIG_FILE="$alt"
            echo -e "${GREEN}Found config at $CONFIG_FILE${NC}"
            break
        fi
    done
    
    # If still not found, ask the user
    if [ ! -f "$CONFIG_FILE" ]; then
        CONFIG_FILE=$(yad --file --title="Select Config File")
        if [ -z "$CONFIG_FILE" ]; then
            echo -e "${RED}No config file selected. Exiting.${NC}"
            exit 1
        fi
    fi
fi

echo -e "${BLUE}Using config file: $CONFIG_FILE${NC}"

# Create a temporary file for the markdown output
TEMP_MD=$(mktemp)

# Function to categorize Hyprland keybindings
categorize_hyprland_bindings() {
    local line="$1"
    local action=$(echo "$line" | sed -E 's/bind = [^,]+, (.*)/\1/' | tr -d ' ')
    
    if [[ "$action" == exec* ]]; then
        if [[ "$action" == *"rofi"* || "$action" == *"wofi"* || "$action" == *"dmenu"* ]]; then
            echo "launcher"
        elif [[ "$action" == *"terminal"* || "$action" == *"kitty"* || "$action" == *"alacritty"* || "$action" == *"foot"* ]]; then
            echo "terminal"
        elif [[ "$action" == *"screenshot"* || "$action" == *"grim"* || "$action" == *"slurp"* ]]; then
            echo "screenshot"
        else
            echo "application"
        fi
    elif [[ "$action" == *"workspace"* ]]; then
        echo "workspace"
    elif [[ "$action" == *"movetoworkspace"* ]]; then
        echo "window-workspace"
    elif [[ "$action" == *"movefocus"* || "$action" == *"focuswindow"* ]]; then
        echo "focus"
    elif [[ "$action" == *"togglefloating"* || "$action" == *"pseudo"* || "$action" == *"fullscreen"* ]]; then
        echo "window-state"
    elif [[ "$action" == *"moveintogroup"* || "$action" == *"moveoutofgroup"* || "$action" == *"togglegroup"* ]]; then
        echo "group"
    else
        echo "misc"
    fi
}

# Function to categorize i3/Sway keybindings
categorize_i3_bindings() {
    local line="$1"
    local action=$(echo "$line" | sed -E 's/bindsym[[:space:]]+[^[:space:]]+[[:space:]]+(.+)/\1/')
    
    if [[ "$action" == exec* ]]; then
        if [[ "$action" == *"rofi"* || "$action" == *"dmenu"* || "$action" == *"wofi"* ]]; then
            echo "launcher"
        elif [[ "$action" == *"terminal"* || "$action" == *"kitty"* || "$action" == *"alacritty"* || "$action" == *"urxvt"* || "$action" == *"foot"* ]]; then
            echo "terminal"
        elif [[ "$action" == *"screenshot"* || "$action" == *"scrot"* || "$action" == *"grim"* || "$action" == *"slurp"* ]]; then
            echo "screenshot"
        else
            echo "application"
        fi
    elif [[ "$action" == *"workspace"* && ! "$action" == *"move"* ]]; then
        echo "workspace"
    elif [[ "$action" == *"move"* && "$action" == *"workspace"* ]]; then
        echo "window-workspace"
    elif [[ "$action" == *"focus"* ]]; then
        echo "focus"
    elif [[ "$action" == *"floating"* || "$action" == *"fullscreen"* || "$action" == *"sticky"* ]]; then
        echo "window-state"
    elif [[ "$action" == *"layout"* ]]; then
        echo "layout"
    elif [[ "$action" == *"reload"* || "$action" == *"restart"* || "$action" == *"exit"* ]]; then
        echo "system"
    elif [[ "$action" == *"resize"* ]]; then
        echo "resize"
    else
        echo "misc"
    fi
}

# Generate the markdown content
{
    echo "# 🎮 Hotkeys for $([ -n "$XDG_CURRENT_DESKTOP" ] && echo "$XDG_CURRENT_DESKTOP" || echo "$WM_TYPE")"
    echo ""
    echo "🕒 Generated on $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    
    if [ "$WM_TYPE" = "hyprland" ]; then
        # Get all keybindings and sort them into categories
        declare -A categories
        
        while read -r line; do
            category=$(categorize_hyprland_bindings "$line")
            key=$(echo "$line" | sed -E 's/bind = ([^,]+),.*/\1/' | tr -d ' ')
            action=$(echo "$line" | sed -E 's/bind = [^,]+, (.*)/\1/' | tr -d ' ')
            categories["$category"]+="$key|$action\n"
        done < <(rg "$KEYBIND_PATTERN" "$CONFIG_FILE")
        
        # Output each category
        # Workspace Navigation
        if [ -n "${categories[workspace]}" ]; then
            echo "## 🖥️ Workspace Navigation"
            echo ""
            echo "| Keybinding | Action |"
            echo "|------------|--------|"
            echo -e "${categories[workspace]}" | sort | while IFS="|" read -r key action; do
                echo "| \`$key\` | $action |"
            done
            echo ""
        fi
        
        # Window to Workspace
        if [ -n "${categories[window-workspace]}" ]; then
            echo "## 🪟 Window to Workspace"
            echo ""
            echo "| Keybinding | Action |"
            echo "|------------|--------|"
            echo -e "${categories[window-workspace]}" | sort | while IFS="|" read -r key action; do
                echo "| \`$key\` | $action |"
            done
            echo ""
        fi
        
        # Focus Control
        if [ -n "${categories[focus]}" ]; then
            echo "## 🔍 Focus Control"
            echo ""
            echo "| Keybinding | Action |"
            echo "|------------|--------|"
            echo -e "${categories[focus]}" | sort | while IFS="|" read -r key action; do
                echo "| \`$key\` | $action |"
            done
            echo ""
        fi
        
        # Window State
        if [ -n "${categories[window-state]}" ]; then
            echo "## 📐 Window State"
            echo ""
            echo "| Keybinding | Action |"
            echo "|------------|--------|"
            echo -e "${categories[window-state]}" | sort | while IFS="|" read -r key action; do
                echo "| \`$key\` | $action |"
            done
            echo ""
        fi
        
        # Window Grouping
        if [ -n "${categories[group]}" ]; then
            echo "## 📚 Window Grouping"
            echo ""
            echo "| Keybinding | Action |"
            echo "|------------|--------|"
            echo -e "${categories[group]}" | sort | while IFS="|" read -r key action; do
                echo "| \`$key\` | $action |"
            done
            echo ""
        fi
        
        # Launchers
        if [ -n "${categories[launcher]}" ]; then
            echo "## 🚀 Launchers"
            echo ""
            echo "| Keybinding | Action |"
            echo "|------------|--------|"
            echo -e "${categories[launcher]}" | sort | while IFS="|" read -r key action; do
                echo "| \`$key\` | $action |"
            done
            echo ""
        fi
        
        # Terminal
        if [ -n "${categories[terminal]}" ]; then
            echo "## 💻 Terminal"
            echo ""
            echo "| Keybinding | Action |"
            echo "|------------|--------|"
            echo -e "${categories[terminal]}" | sort | while IFS="|" read -r key action; do
                echo "| \`$key\` | $action |"
            done
            echo ""
        fi
        
        # Screenshots
        if [ -n "${categories[screenshot]}" ]; then
            echo "## 📷 Screenshots"
            echo ""
            echo "| Keybinding | Action |"
            echo "|------------|--------|"
            echo -e "${categories[screenshot]}" | sort | while IFS="|" read -r key action; do
                echo "| \`$key\` | $action |"
            done
            echo ""
        fi
        
        # Applications
        if [ -n "${categories[application]}" ]; then
            echo "## 📱 Applications"
            echo ""
            echo "| Keybinding | Action |"
            echo "|------------|--------|"
            echo -e "${categories[application]}" | sort | while IFS="|" read -r key action; do
                # Try to extract application name for better readability
                app_name=$(echo "$action" | sed -E 's/.*exec[[:space:]]+([^[:space:]]+).*/\1/' | sed 's/^.*\///')
                echo "| \`$key\` | $action (\`$app_name\`) |"
            done
            echo ""
        fi
        
        # Miscellaneous
        if [ -n "${categories[misc]}" ]; then
            echo "## 🔧 Miscellaneous"
            echo ""
            echo "| Keybinding | Action |"
            echo "|------------|--------|"
            echo -e "${categories[misc]}" | sort | while IFS="|" read -r key action; do
                echo "| \`$key\` | $action |"
            done
            echo ""
        fi
        
    elif [ "$WM_TYPE" = "i3" ] || [ "$WM_TYPE" = "sway" ]; then
        # Get all keybindings and sort them into categories
        declare -A categories
        
        while read -r line; do
            # Skip comments and empty lines
            if [[ $line =~ ^[[:space:]]*# || -z "$line" ]]; then
                continue
            fi
            
            category=$(categorize_i3_bindings "$line")
            key=$(echo "$line" | sed -E 's/bindsym[[:space:]]+([^[:space:]]+).*/\1/')
            action=$(echo "$line" | sed -E 's/bindsym[[:space:]]+[^[:space:]]+[[:space:]]+(.+)/\1/')
            categories["$category"]+="$key|$action\n"
        done < <(rg "$KEYBIND_PATTERN" "$CONFIG_FILE")
        
        # Output each category
        # Workspace Navigation
        if [ -n "${categories[workspace]}" ]; then
            echo "## 🖥️ Workspace Navigation"
            echo ""
            echo "| Keybinding | Action |"
            echo "|------------|--------|"
            echo -e "${categories[workspace]}" | sort | while IFS="|" read -r key action; do
                echo "| \`$key\` | $action |"
            done
            echo ""
        fi
        
        # Window to Workspace
        if [ -n "${categories[window-workspace]}" ]; then
            echo "## 🪟 Window to Workspace"
            echo ""
            echo "| Keybinding | Action |"
            echo "|------------|--------|"
            echo -e "${categories[window-workspace]}" | sort | while IFS="|" read -r key action; do
                echo "| \`$key\` | $action |"
            done
            echo ""
        fi
        
        # Focus Control
        if [ -n "${categories[focus]}" ]; then
            echo "## 🔍 Focus Control"
            echo ""
            echo "| Keybinding | Action |"
            echo "|------------|--------|"
            echo -e "${categories[focus]}" | sort | while IFS="|" read -r key action; do
                echo "| \`$key\` | $action |"
            done
            echo ""
        fi
        
        # Window State
        if [ -n "${categories[window-state]}" ]; then
            echo "## 📐 Window State"
            echo ""
            echo "| Keybinding | Action |"
            echo "|------------|--------|"
            echo -e "${categories[window-state]}" | sort | while IFS="|" read -r key action; do
                echo "| \`$key\` | $action |"
            done
            echo ""
        fi
        
        # Layout
        if [ -n "${categories[layout]}" ]; then
            echo "## 📏 Layout Control"
            echo ""
            echo "| Keybinding | Action |"
            echo "|------------|--------|"
            echo -e "${categories[layout]}" | sort | while IFS="|" read -r key action; do
                echo "| \`$key\` | $action |"
            done
            echo ""
        fi
        
        # Resize
        if [ -n "${categories[resize]}" ]; then
            echo "## 📏 Resize Control"
            echo ""
            echo "| Keybinding | Action |"
            echo "|------------|--------|"
            echo -e "${categories[resize]}" | sort | while IFS="|" read -r key action; do
                echo "| \`$key\` | $action |"
            done
            echo ""
        fi
        
        # System
        if [ -n "${categories[system]}" ]; then
            echo "## ⚙️ System Control"
            echo ""
            echo "| Keybinding | Action |"
            echo "|------------|--------|"
            echo -e "${categories[system]}" | sort | while IFS="|" read -r key action; do
                echo "| \`$key\` | $action |"
            done
            echo ""
        fi
        
        # Launchers
        if [ -n "${categories[launcher]}" ]; then
            echo "## 🚀 Launchers"
            echo ""
            echo "| Keybinding | Action |"
            echo "|------------|--------|"
            echo -e "${categories[launcher]}" | sort | while IFS="|" read -r key action; do
                echo "| \`$key\` | $action |"
            done
            echo ""
        fi
        
        # Terminal
        if [ -n "${categories[terminal]}" ]; then
            echo "## 💻 Terminal"
            echo ""
            echo "| Keybinding | Action |"
            echo "|------------|--------|"
            echo -e "${categories[terminal]}" | sort | while IFS="|" read -r key action; do
                echo "| \`$key\` | $action |"
            done
            echo ""
        fi
        
        # Screenshots
        if [ -n "${categories[screenshot]}" ]; then
            echo "## 📷 Screenshots"
            echo ""
            echo "| Keybinding | Action |"
            echo "|------------|--------|"
            echo -e "${categories[screenshot]}" | sort | while IFS="|" read -r key action; do
                echo "| \`$key\` | $action |"
            done
            echo ""
        fi
        
        # Applications
        if [ -n "${categories[application]}" ]; then
            echo "## 📱 Applications"
            echo ""
            echo "| Keybinding | Action |"
            echo "|------------|--------|"
            echo -e "${categories[application]}" | sort | while IFS="|" read -r key action; do
                # Try to extract application name for better readability
                app_name=$(echo "$action" | sed -E 's/.*exec[[:space:]]+([^[:space:]]+).*/\1/' | sed 's/^.*\///')
                echo "| \`$key\` | $action (\`$app_name\`) |"
            done
            echo ""
        fi
        
        # Miscellaneous
        if [ -n "${categories[misc]}" ]; then
            echo "## 🔧 Miscellaneous"
            echo ""
            echo "| Keybinding | Action |"
            echo "|------------|--------|"
            echo -e "${categories[misc]}" | sort | while IFS="|" read -r key action; do
                echo "| \`$key\` | $action |"
            done
            echo ""
        fi
        
    elif [ "$WM_TYPE" = "qtile" ]; then
        # For qtile, we'll keep it simpler for now
        echo "## ⌨️ Keyboard Shortcuts"
        echo ""
        echo "| Keybinding | Action |"
        echo "|------------|--------|"
        rg "$KEYBIND_PATTERN" "$CONFIG_FILE" | while read -r line; do
            # Basic extraction for qtile - may need refinement
            key=$(echo "$line" | sed -E 's/.*Key\(\[([^]]+).*/\1/' | tr -d ' ')
            action=$(echo "$line" | sed -E 's/.*\], ([^,]+).*/\1/' | tr -d ' ')
            echo "| \`$key\` | $action |"
        done
        echo ""
    fi
    
    echo "## ℹ️ Additional Information"
    echo ""
    echo "This is a read-only view of your hotkeys. To modify hotkeys, edit your config file directly."
    echo ""
    echo "Config file location: \`$CONFIG_FILE\`"
    echo ""
    echo "---"
    echo "Generated with 💙 by Hotkeys Rosetta"
} > "$TEMP_MD"

# Display the markdown file using the selected renderer and yad
echo -e "${GREEN}Displaying hotkeys with $MD_RENDERER...${NC}"

# Customize renderer behavior based on selected renderer
case "$MD_RENDERER" in
    "glow")
        # Glow has good built-in paging and formatting
        $MD_RENDER_CMD "$TEMP_MD" | yad --text-info --back=#282c34 --fore=#46d9ff --geometry=1200x800 --title="Hotkeys Rosetta [$MD_RENDERER]" --button="Close:0"
        ;;
    "mdcat")
        # mdcat may need different handling for some terminals
        $MD_RENDER_CMD "$TEMP_MD" | yad --text-info --back=#282c34 --fore=#46d9ff --geometry=1200x800 --title="Hotkeys Rosetta [$MD_RENDERER]" --button="Close:0"
        ;;
    "bat")
        # For bat, we'll use its built-in paging but with a custom style
        $MD_RENDER_CMD --style=plain --paging=never "$TEMP_MD" | yad --text-info --back=#282c34 --fore=#46d9ff --geometry=1200x800 --title="Hotkeys Rosetta [$MD_RENDERER]" --button="Close:0"
        ;;
    *)
        # Default fallback
        $MD_RENDER_CMD "$TEMP_MD" | yad --text-info --back=#282c34 --fore=#46d9ff --geometry=1200x800 --title="Hotkeys Rosetta [$MD_RENDERER]" --button="Close:0"
        ;;
esac

# Option to save the markdown file
if yad --question --text="Would you like to save this hotkeys reference to a file?" --title="Save Hotkeys"; then
    SAVE_PATH=$(yad --file --save --title="Save Hotkeys Reference" --filename="$HOME/hotkeys_reference.md")
    if [ -n "$SAVE_PATH" ]; then
        cp "$TEMP_MD" "$SAVE_PATH"
        echo -e "${GREEN}Hotkeys reference saved to $SAVE_PATH${NC}"
    fi
fi

# Clean up
rm "$TEMP_MD"
echo -e "${GREEN}Done!${NC}"

# Display information about the renderers for future reference
echo -e "\n${BLUE}Markdown renderer information:${NC}"
echo -e "  ${YELLOW}glow${NC}: Render markdown with beautiful formatting and themes (recommended)"
echo -e "  ${YELLOW}mdcat${NC}: Lightweight markdown renderer with terminal image support"
echo -e "  ${YELLOW}bat${NC}: Syntax-highlighting cat clone with markdown support"
echo -e "\nInstall your preferred renderer with your package manager if needed."