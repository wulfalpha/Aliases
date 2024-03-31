#!/bin/sh

manual=$(apropos -s ${SECTION:-''} ${@:-.} | \
    grep -v -E '^.+ \(0\)' |\
    awk '{print $2 "    " $1}' | \
    sort | \
    rofi -dmenu -i -p "Manual: " | \
    sed -E 's/^\((.+)\)/\1/')

if [ -z "$MANUAL" ]; then
  # Use mktemp to create a temporary file.
  tmpfile=$(mktemp /tmp/manpage.XXXXXX.pdf)

  # Generate the manual and save it to the temporary file.
  man -T${FORMAT:-pdf} $manual > "$tmpfile"

  # Open the temporary file with xreader.
  xreader "$tmpfile"

  # Optionally, remove the temporary file after xreader has been closed.
  rm "$tmpfile"
fi
