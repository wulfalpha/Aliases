#!/bin/bash

export NEWT_COLORS="
root=,red
window=,black
shadow=,red
border=blue,black
title=blue,black
textbox=blue,black
radiolist=black,black
label=black,red
checkbox=black,red
compactbutton=black,red
button=black,red"

# Function to display OS information
show_os_info() {
    info=$(neofetch --stdout)
    
    # Initialize os_info with a title or empty
    os_info=""
    
    # Array of field titles to match with grep
    declare -a fields=("OS" "Host" "Kernel" "Uptime" "Packages" "Shell" "DE" "WM" "CPU" "GPU" "Distro")
    
    # Loop through each field and add it to os_info if not empty
    for field in "${fields[@]}"; do
        value=$(echo "$info" | grep "$field:" | cut -f2 -d':')
        if [ -n "$value" ]; then  # Only add if value is not empty
            os_info+="$field: $value\n"
        fi
    done

    # Display the info in a window
    whiptail --title "OS Information" --msgbox "$os_info" 20 78
}

# Function to display Networking information
show_network_info() {
    network_info=$(ip addr | awk '/inet/ && /brd/ {print $NF, $2}' OFS=': ' | sort -k 2 -t ':')
    formatted_network_info="Interface | IP Address\n-----------------------------------\n"
    while IFS= read -r line; do
        formatted_network_info+="$line\n"
    done <<< "$network_info"
    whiptail --title "Networking Information" --msgbox "$formatted_network_info" 20 78
}

# Function to display Memory statistics
show_memory_stats() {
    Total=$(awk '/MemTotal/ {print $2/1024}' /proc/meminfo)
    Free=$(awk '/MemFree/ {print $2/1024}' /proc/meminfo)
    Available=$(awk '/MemAvailable/ {print $2/1024}' /proc/meminfo)
    memory_stats="Memory Information:\n----------------------\nTotal: ${Total} MB\nFree: ${Free} MB\nAvailable: ${Available} MB"
    whiptail --title "Memory Statistics" --msgbox "$memory_stats" 20 78
}

# Main menu function
main_menu() {
    while true; do
        choice=$(whiptail --title "System Info Viewer" --menu "Choose an option" 15 60 4 \
        "1" "OS Information" \
        "2" "Networking Information" \
        "3" "Memory Statistics" \
        "4" "Exit" 3>&1 1>&2 2>&3)

        case $choice in
            1) show_os_info ;;
            2) show_network_info ;;
            3) show_memory_stats ;;
            4) break ;;
            *) whiptail --title "Error!" --msgbox "Invalid option. Please choose again." 10 50
        esac
    done
}

# Start the application
main_menu
