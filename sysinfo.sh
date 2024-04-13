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
    # Get all relevant neofetch information at once
    info=$(neofetch --stdout)
    
    # Parse each piece of information
    OS=$(echo "$info" | grep "OS:" | cut -f2 -d':')
    Kernel=$(echo "$info" | grep "Kernel:" | cut -f2 -d':')
    Uptime=$(echo "$info" | grep "Uptime:" | cut -f2 -d':')
    Packages=$(echo "$info" | grep "Packages:" | cut -f2 -d':')
    Shell=$(echo "$info" | grep "Shell:" | cut -f2 -d':')
    DE=$(echo "$info" | grep "DE:" | cut -f2 -d':')
    WM=$(echo "$info" | grep "WM:" | cut -f2 -d':')
    CPU=$(echo "$info" | grep "CPU:" | cut -f2 -d':')
    GPU=$(echo "$info" | grep "GPU:" | cut -f2 -d':')
    Distro=$(echo "$info" | grep "Distro:" | cut -f2 -d':')
    
    # Create the os_info variable, formatting each piece of information on a new line
    os_info="OS: $OS\nKernel: $Kernel\nUptime: $Uptime\nPackages: $Packages\nShell: $Shell\nDE: $DE\nWM: $WM\nCPU: $CPU\nGPU: $GPU\nDistro: $Distro"
    
    # Display the info in a window
    whiptail --title "OS Information" --msgbox "$os_info" 20 78
}

# Function to display Networking information
show_network_info() {
    # Fetch and format network interface information
    network_info=$(ip addr | awk '/inet/ && /brd/ {print $NF, $2}' OFS=': ' | sort -k 2 -t ':')

    # Adding labels for better readability
    formatted_network_info="Interface | IP Address\n"
    formatted_network_info+="-----------------------------------\n"
    while IFS= read -r line; do
        formatted_network_info+="$line\n"
    done <<< "$network_info"

    # Display the information in a whiptail message box
    whiptail --title "Networking Information" --msgbox "$formatted_network_info" 20 78
}

# Function to display Memory statistics
show_memory_stats() {
    # Fetch and calculate memory stats
    Total=$(awk '/MemTotal/ {print $2/1024}' /proc/meminfo)
    Free=$(awk '/MemFree/ {print $2/1024}' /proc/meminfo)
    Available=$(awk '/MemAvailable/ {print $2/1024}' /proc/meminfo)

    # Format the memory stats for display
    memory_stats="Memory Information:\n----------------------\nTotal: ${Total} MB\nFree: ${Free} MB\nAvailable: ${Available} MB"

    # Display the memory stats in a whiptail message box
    whiptail --title "Memory Statistics" --msgbox "$memory_stats" 20 78
}

# Main menu using whiptail
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
