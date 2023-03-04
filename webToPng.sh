#!/usr/bin/env sh
for file in *.webp;
do
    dwebp "$file" -o "$file"
    mv -- "$file" "${file%.webp}.png"

done
