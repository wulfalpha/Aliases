#!/bin/bash

# pac-fix.sh - Fix missing/corrupted package files using pacman
# Logs all operations to fix-log.txt

LOG_FILE="fix-log.txt"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Function to log messages
log() {
    echo "$1" | tee -a "$LOG_FILE"
}

# Function to log without echoing to console
log_only() {
    echo "$1" >> "$LOG_FILE"
}

# Start logging
echo "" >> "$LOG_FILE"
log "=========================================="
log "pac-fix.sh run started: $TIMESTAMP"
log "=========================================="
log ""

# Check for missing/corrupted files
log "Checking for missing/corrupted package files..."
log ""

# Run pacman -Qk to get detailed output
sudo pacman -Qk > /tmp/pac-check-full.txt 2>&1
log_only "--- Full pacman -Qk output ---"
cat /tmp/pac-check-full.txt >> "$LOG_FILE"
log_only ""

# Parse output to find packages with ACTUAL missing files
# Only look for "(No such file or directory)" errors
log "Analyzing output for truly missing files..."
MISSING_FILES_PACKAGES=$(grep -E "warning:.*\(No such file or directory\)" /tmp/pac-check-full.txt | \
    sed 's/warning: \([^:]*\):.*/\1/' | \
    sort -u)

if [ -z "$MISSING_FILES_PACKAGES" ]; then
    log "No packages with missing files found!"
    log ""

    # Check if there are other issues (permissions, modifications, etc.)
    OTHER_ISSUES=$(sudo pacman -Qkq 2>/dev/null | wc -l)
    if [ "$OTHER_ISSUES" -gt 0 ]; then
        log "Note: $OTHER_ISSUES package(s) have other issues (permissions, modifications, etc.)"
        log "These are not critical and do not require reinstallation."
        log "Run 'pacman -Qk' manually if you want to investigate."
    else
        log "System appears to be in perfect state."
    fi

    log ""
    log "=========================================="
    log "pac-fix.sh completed: $(date '+%Y-%m-%d %H:%M:%S')"
    log "=========================================="
    rm -f /tmp/pac-check-full.txt
    exit 0
fi

# Count and display broken packages with missing files
PACKAGE_COUNT=$(echo "$MISSING_FILES_PACKAGES" | wc -l)
log "Found $PACKAGE_COUNT package(s) with missing files:"
log ""

# Show detailed information about what's missing
echo "$MISSING_FILES_PACKAGES" | while read -r pkg; do
    MISSING_COUNT=$(grep -E "warning: $pkg:.*\(No such file or directory\)" /tmp/pac-check-full.txt | wc -l)
    log "  - $pkg ($MISSING_COUNT missing file(s))"

    # Log the actual missing files for reference
    log_only "    Missing files in $pkg:"
    grep -E "warning: $pkg:.*\(No such file or directory\)" /tmp/pac-check-full.txt | \
        sed 's/warning: [^:]*: \(.*\) (No such file or directory)/      \1/' >> "$LOG_FILE"
done
log ""

# Ask for confirmation
echo ""
echo "About to reinstall $PACKAGE_COUNT package(s) with missing files."
read -p "Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log "Operation cancelled by user."
    log ""
    log "=========================================="
    log "pac-fix.sh cancelled: $(date '+%Y-%m-%d %H:%M:%S')"
    log "=========================================="
    rm -f /tmp/pac-check-full.txt
    exit 1
fi

# Reinstall packages
log ""
log "Reinstalling packages with missing files..."
log ""

# Convert newline-separated list to space-separated for pacman
PACKAGES_TO_FIX=$(echo "$MISSING_FILES_PACKAGES" | tr '\n' ' ')

# Run the reinstall
if sudo pacman -S --needed $PACKAGES_TO_FIX 2>&1 | tee -a "$LOG_FILE"; then
    log ""
    log "Package reinstallation completed."
else
    log ""
    log "WARNING: Some packages failed to reinstall. Check the output above."
fi

# Final check - only for packages we tried to fix
log ""
log "Verifying fix..."
STILL_BROKEN=""
for pkg in $MISSING_FILES_PACKAGES; do
    if sudo pacman -Qk "$pkg" 2>&1 | grep -q "(No such file or directory)"; then
        STILL_BROKEN="$STILL_BROKEN $pkg"
    fi
done

if [ -z "$STILL_BROKEN" ]; then
    log "SUCCESS: All missing files have been restored!"
else
    log "WARNING: The following package(s) still have missing files:"
    for pkg in $STILL_BROKEN; do
        log "  - $pkg"
    done
    log ""
    log "You may need to manually investigate these packages."
    log "Try: pacman -Qk <package-name> for details"
fi

log ""
log "=========================================="
log "pac-fix.sh completed: $(date '+%Y-%m-%d %H:%M:%S')"
log "=========================================="

# Cleanup temp files
rm -f /tmp/pac-check-full.txt
