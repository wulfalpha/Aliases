#!/usr/bin/env bash

# Function to toggle Bluetooth hardware and optionally restart the service
toggle_bluetooth() {
    # Check if Bluetooth is enabled
    if rfkill list bluetooth | grep -q "Soft blocked: no"; then
        # Disable Bluetooth
        rfkill block bluetooth
        echo "Bluetooth disabled"
        return 0
    else
        # Enable Bluetooth
        rfkill unblock bluetooth
        echo "Bluetooth enabled"
        
        # Try to restart the service if available
        # This helps ensure the service is properly working after unblocking
        # Check for systemd
        if command -v systemctl &> /dev/null && systemctl list-unit-files bluetooth.service &> /dev/null; then
            systemctl restart bluetooth.service &>/dev/null
        # Check for SysV init system
        elif command -v service &> /dev/null && service --status-all 2>&1 | grep -q "bluetooth"; then
            service bluetooth restart &>/dev/null
        # Check for Upstart
        elif command -v initctl &> /dev/null && initctl list | grep -q "bluetooth"; then
            initctl restart bluetooth &>/dev/null
        fi
        
        return 1
    fi
}

# Function to check bluetooth status (can be used by waybar to display status)
get_bluetooth_status() {
    if rfkill list bluetooth | grep -q "Soft blocked: no"; then
        echo '{"text":"BT: ON", "class":"on", "tooltip":"Bluetooth is enabled"}'
    else
        echo '{"text":"BT: OFF", "class":"off", "tooltip":"Bluetooth is disabled"}'
    fi
}

# Main logic
case "$1" in
    status)
        get_bluetooth_status
        ;;
    *)
        toggle_bluetooth
        ;;
esac