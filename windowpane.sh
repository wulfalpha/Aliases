#!/bin/bash

# Set up colors
export NEWT_COLORS="
root=,red
window=,black
shadow=,red
border=blue,black
title=blue,black
textbox=blue,black
radiolist=black,blue
label=white,red
checkbox=red,black
compactbutton=black,red
button=red,black"



# Array of website names and URLs
declare -A websites
websites["Amazon.com"]="https://www.amazon.com"
websites["Brave_Search"]="https://search.brave.com"
websites["Google_Search"]="https://www.google.com"
websites["Google_Translate"]="https://translate.google.com"
websites["Outlook"]="https://outlook.live.com/mail"
websites["Gmail"]="https://mail.google.com"
websites["YouTube"]="https://www.youtube.com"
websites["GitHub"]="https://github.com"


# Prepare the checklist options
checklist_options=()
for site in "${!websites[@]}"; do
  checklist_options+=("$site" "" OFF)
done

# Use whiptail to display a checkbox dialog
selected_websites=$(whiptail --separate-output --checklist "Select websites to open:" 15 60 5 "${checklist_options[@]}" 3>&1 1>&2 2>&3)

# Check if the user selected any websites
if [[ -z "$selected_websites" ]]; then
  echo "No websites selected. Exiting."
  exit 0
fi

# Launch pane with the selected websites
for website_name in $selected_websites; do
  url="${websites[$website_name]}"
  echo $url
  if [[ -n "$url" ]]; then
    ./pane.py -l "$url" &
  fi
done
