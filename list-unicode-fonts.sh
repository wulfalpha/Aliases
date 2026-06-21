#!/bin/sh
# list-unicode-fonts.sh
# Lists installed Nerd Fonts, emoji fonts, and Unicode symbol fonts.
# Requires: fontconfig (fc-list)

PATTERNS='nerd|NF|emoji|symbol|awesome|powerline|material|codicon|devicon|feather|octicon|twemoji|joypixels|symbola|unifont|noto.*emoji|seguiemj|phosphor|boxicons|remixicon|tabler|heroicon'

if ! command -v fc-list >/dev/null 2>&1; then
    printf 'Error: fc-list not found. Install fontconfig.\n' >&2
    exit 1
fi

printf '=== Font Families ===\n'
fc-list : family \
    | tr ',' '\n' \
    | sed 's/^[[:space:]]*//' \
    | sed 's/[[:space:]]*$//' \
    | sort -u \
    | grep -iE "$PATTERNS"

printf '\n=== Font Files ===\n'
fc-list \
    | grep -iE "$PATTERNS" \
    | sed 's/:.*//' \
    | sort -u
