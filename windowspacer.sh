#!/usr/bin/env bash
# Script to convert between Windows and Unix line endings
# Usage: ./windowspacer.sh [-r|--reversed] [-c|--clean] [-g|--git] <file1> [file2 file3 ...]

# Initialize variables
reverse_mode=0
clean_mode=0
git_mode=0

# Spinner function for visual feedback during processing
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while ps -p $pid > /dev/null; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# Function to process a file with visual feedback
process_file() {
    local file=$1
    local cmd=$2
    
    # Run the command in background
    eval "$cmd" &
    local pid=$!
    
    # Display spinner while command runs
    spinner $pid
    
    # Wait for command to finish
    wait $pid
    return $?
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -r|--reversed)
            reverse_mode=1
            shift
            ;;
        -c|--clean)
            clean_mode=1
            shift
            ;;
        -g|--git)
            git_mode=1
            # Git mode overrides reverse mode
            reverse_mode=0
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [-r|--reversed] [-c|--clean] [-g|--git] <file1> [file2 file3 ...]"
            echo "Options:"
            echo "  -r, --reversed  Convert Unix line endings (LF) to Windows format (CRLF)"
            echo "  -c, --clean     Enable additional text cleanup (removes whitespace and empty lines)"
            echo "                  WARNING: Not safe for code where whitespace or empty lines matter!"
            echo "  -g, --git       Git-friendly mode: ensures Unix LF line endings (overrides -r)"
            echo "                  Best for Python and cross-platform development"
            echo "  -h, --help      Display this help message"
            exit 0
            ;;
        *)
            break
            ;;
    esac
done

# Display usage if no file arguments provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 [-r|--reversed] [-c|--clean] [-g|--git] <file1> [file2 file3 ...]"
    echo "By default: Safely converts Windows line endings (CRLF) to Unix format (LF)."
    echo "With -r or --reversed: Converts Unix line endings (LF) to Windows format (CRLF)."
    echo "With -c or --clean: Enables additional text cleanup (WARNING: not safe for code files!)"
    echo "With -g or --git: Ensures Git-friendly Unix line endings (ideal for Python)."
    echo "Use -h or --help for more information."
    exit 1
fi

# Function to calculate file size in human-readable format
get_file_size() {
    local size=$(stat -c %s "$1" 2>/dev/null || stat -f %z "$1" 2>/dev/null)
    if (( size < 1024 )); then
        echo "${size}B"
    elif (( size < 1048576 )); then
        echo "$(( size / 1024 ))KB"
    else
        echo "$(( size / 1048576 ))MB"
    fi
}

# Process each provided file
for file in "$@"; do
    # Check if the file exists
    if [ ! -f "$file" ]; then
        echo "File '$file' does not exist. Skipping."
        continue
    fi
    
    # Get file size
    file_size=$(get_file_size "$file")
    echo "Processing $file ($file_size)..."
    
    # Create a backup with .bak extension
    cp "$file" "${file}.bak"
    
    # Prepare the command based on mode
    if [ $git_mode -eq 1 ]; then
        echo "Converting to Git-friendly Unix format (LF)..."
        if [ $clean_mode -eq 1 ]; then
            echo "  With cleanup mode (WARNING: may affect code functionality)"
            cmd="sed -i -e 's/\r$//' -e 's/[[:space:]]*$//' \"$file\""
        else
            cmd="sed -i 's/\r$//' \"$file\""
        fi
        
        # Run the command with spinner for visual feedback
        process_file "$file" "$cmd"
        
        # Check if .gitattributes exists in the current directory
        if [ ! -f ".gitattributes" ]; then
            echo "Note: No .gitattributes file found. For consistent line endings across platforms,"
            echo "      you might want to create one with: '* text=auto eol=lf'"
        fi
    elif [ $reverse_mode -eq 0 ]; then
        echo "Converting Windows to Unix format (LF)..."
        if [ $clean_mode -eq 1 ]; then
            echo "  With cleanup mode (WARNING: may affect code functionality)"
            cmd="sed -i -e 's/\r$//' -e 's/[[:space:]]*$//' -e 's/^[[:space:]]*//' -e '/^$/d' \"$file\""
        else
            cmd="sed -i 's/\r$//' \"$file\""
        fi
        
        # Run the command with spinner for visual feedback
        process_file "$file" "$cmd"
    else
        echo "Converting Unix to Windows format (CRLF)..."
        if [ $clean_mode -eq 1 ]; then
            echo "  With cleanup mode (WARNING: may affect code functionality)"
            cmd1="sed -i -e 's/\r$//' -e 's/[[:space:]]*$//' -e 's/^[[:space:]]*//' -e '/^$/d' \"$file\""
            cmd2="sed -i 's/$/\r/' \"$file\""
            
            # Run commands with spinner for visual feedback
            process_file "$file" "$cmd1"
            process_file "$file" "$cmd2"
        else
            cmd1="sed -i 's/\r$//' \"$file\""
            cmd2="sed -i 's/$/\r/' \"$file\""
            
            # Run commands with spinner for visual feedback
            process_file "$file" "$cmd1"
            process_file "$file" "$cmd2"
        fi
    fi
    
    # For Python files specifically, offer additional guidance
    if [[ $file == *.py && $git_mode -eq 1 ]]; then
        echo "  Python file detected: LF line endings are recommended (PEP 8)"
    elif [[ $file == *.py && $reverse_mode -eq 1 ]]; then
        echo "  Warning: Converting Python file to CRLF format may cause issues on some platforms"
    fi
    
    echo "Completed. Backup saved as ${file}.bak"
done

echo "All files processed!"