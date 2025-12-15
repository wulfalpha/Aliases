#!/usr/bin/env bash

# Interactive man page viewer using fzf
# Modern cross-platform version with ripgrep support

# Check for required dependencies
for cmd in fzf apropos less; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: $cmd is required but not installed. Aborting." >&2
        exit 1
    fi
done

# Detect which grep tool to use (prefer ripgrep)
if command -v rg >/dev/null 2>&1; then
    GREP_CMD="rg"
    GREP_QUIET_FLAG="-q"
    GREP_IGNORE_CASE="-i"
    GREP_CONTEXT_BEFORE="-B"
    GREP_CONTEXT_AFTER="-A"
else
    GREP_CMD="grep"
    GREP_QUIET_FLAG="-q"
    GREP_IGNORE_CASE="-i"
    GREP_CONTEXT_BEFORE="-B"
    GREP_CONTEXT_AFTER="-A"
fi

# Help function
show_help() {
    cat << EOF
Usage: $(basename "$0") [-s SECTION] [-k KEYWORD] [SEARCH_TERM]
Interactive man page viewer using fzf.

Options:
  -s SECTION     Limit search to specified section
  -k KEYWORD     Search within man page content for keyword
  -h, --help     Display this help message

Environment:
  Using: $GREP_CMD for text search
EOF
    exit 0
}

# Handle help option
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
fi

# Set up history file in /tmp directory with username to avoid conflicts
# Using mktemp with proper fallback for different platforms
if command -v mktemp >/dev/null 2>&1; then
    HISTFILE=$(mktemp "/tmp/manfzf_history_$(id -u)_XXXXXX")
else
    HISTFILE="/tmp/manfzf_history_$(id -u)_$$"
    touch "$HISTFILE"
fi

# Ensure the history file is cleaned up on exit
trap 'rm -f "$HISTFILE"' EXIT

# Add color support for man pages with Catppuccin Mocha theme
export LESS_TERMCAP_md=$'\e[1;38;2;245;194;231m'    # Bold & Pink (pink)
export LESS_TERMCAP_me=$'\e[0m'                     # End mode
export LESS_TERMCAP_se=$'\e[0m'                     # End standout mode
export LESS_TERMCAP_so=$'\e[38;2;137;180;250;48;2;30;30;46m'  # Start standout mode - info box (blue on base)
export LESS_TERMCAP_ue=$'\e[0m'                     # End underline
export LESS_TERMCAP_us=$'\e[4;38;2;166;227;161m'    # Start underline - green (green)

# Configure fzf options with proper quoting
FZF_OPTS="--height=100% --layout=reverse --border=rounded --prompt='Manual: '"
FZF_OPTS="$FZF_OPTS --history='$HISTFILE' --preview-window=right:60%"
FZF_OPTS="$FZF_OPTS --preview='man -Pcat {} 2>/dev/null || echo No manual entry found for {}'"
FZF_OPTS="$FZF_OPTS --bind='?:toggle-preview'"

# Cross-platform clipboard support
if command -v xclip >/dev/null 2>&1; then
    # Linux (X11)
    FZF_OPTS="$FZF_OPTS --bind='ctrl-y:execute-silent(echo {} | xclip -selection clipboard 2>/dev/null)'"
elif command -v pbcopy >/dev/null 2>&1; then
    # macOS
    FZF_OPTS="$FZF_OPTS --bind='ctrl-y:execute-silent(echo {} | pbcopy 2>/dev/null)'"
elif command -v xsel >/dev/null 2>&1; then
    # Linux (alternative)
    FZF_OPTS="$FZF_OPTS --bind='ctrl-y:execute-silent(echo {} | xsel --clipboard 2>/dev/null)'"
fi

# Catppuccin Mocha colors
FZF_OPTS="$FZF_OPTS --color=fg:#cdd6f4,bg:#1e1e2e,hl:#89b4fa"
FZF_OPTS="$FZF_OPTS --color=fg+:#cdd6f4,bg+:#313244,hl+:#89dceb"
FZF_OPTS="$FZF_OPTS --color=info:#f5e0dc,prompt:#f5c2e7,pointer:#cba6f7"
FZF_OPTS="$FZF_OPTS --color=marker:#a6e3a1,spinner:#f9e2af,header:#94e2d5"

export FZF_DEFAULT_OPTS="$FZF_OPTS"

# Process options
SECTION=""
KEYWORD=""
while getopts ":s:k:" opt; do
    case $opt in
        s) SECTION=$OPTARG; shift 2;;
        k) KEYWORD=$OPTARG; shift 2;;
        \?) echo "Invalid option: -$OPTARG" >&2; exit 1;;
        :) echo "Option -$OPTARG requires an argument" >&2; exit 1;;
    esac
done

# Clear screen for better UI experience
clear

# Search term from remaining arguments, defaulting to "." if none provided
SEARCH_TERM="${*:-.}"

# Set up section option for apropos if specified
section_opt=""
[ -n "$SECTION" ] && section_opt="-s $SECTION"

# If keyword is provided, search within man page content
if [ -n "$KEYWORD" ]; then
    # This is a more complex search that looks inside man pages
    echo "Searching man pages for content matching: $KEYWORD"

    # Get list of man pages to search through
    manuals=$(apropos $section_opt "$SEARCH_TERM" | grep -v -E '^.+ \(0\)' | awk '{print $1}' | sed 's/(.*)$//' | sort -u)

    if [ -z "$manuals" ]; then
        echo "No matching manual entries found." >&2
        exit 1
    fi

    # Use a temporary file to store results
    if command -v mktemp >/dev/null 2>&1; then
        results_file=$(mktemp "/tmp/manfzf_results_XXXXXX")
    else
        results_file="/tmp/manfzf_results_$$"
        touch "$results_file"
    fi
    trap 'rm -f "$HISTFILE" "$results_file"' EXIT

    echo "Searching man pages, please wait..."

    # Process each manual to find the keyword
    total=$(echo "$manuals" | wc -l)
    current=0

    echo "$manuals" | while read -r manual; do
        current=$((current + 1))
        printf "\rProcessing %d/%d: %s" "$current" "$total" "$manual"

        # Check if the man page contains the keyword using ripgrep or grep
        if [ "$GREP_CMD" = "rg" ]; then
            if man "$manual" 2>/dev/null | rg -q -i "$KEYWORD"; then
                echo "$manual" >> "$results_file"
            fi
        else
            if man "$manual" 2>/dev/null | grep -q -i "$KEYWORD"; then
                echo "$manual" >> "$results_file"
            fi
        fi
    done

    printf "\rCompleted search: found %d results.                \n" "$(wc -l < "$results_file")"

    if [ ! -s "$results_file" ]; then
        echo "No man pages containing '$KEYWORD' found." >&2
        rm -f "$results_file"
        exit 1
    fi

    # Let user select from matching manuals
    manual=$(cat "$results_file" | fzf --prompt="Man pages containing '$KEYWORD': ")
    rm -f "$results_file"

    if [ -n "$manual" ]; then
        # Display the selected manual with the keyword highlighted
        # Use ripgrep if available, otherwise fall back to grep without --color
        if [ "$GREP_CMD" = "rg" ]; then
            man "$manual" | rg --color=always -i -A 2 -B 2 "$KEYWORD" | less -R
        else
            # Plain grep without --color flag for better cross-platform compatibility
            man "$manual" | grep -i -A 2 -B 2 "$KEYWORD" | less
        fi
    fi
else
    # Standard search by manual name
    manual=$(apropos $section_opt "$SEARCH_TERM" | \
        grep -v -E '^.+ \(0\)' | \
        fzf --with-nth=1 | \
        awk '{print $1}' | \
        sed 's/([^)]*)$//')

    # Exit if no manual was selected
    [ -z "$manual" ] && exit 0

    # Display the selected manual
    if ! man "$manual"; then
        echo "Failed to display manual for '$manual'" >&2
        exit 1
    fi
fi
