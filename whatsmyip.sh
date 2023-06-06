#!/usr/bin/env bash
clear
IP_Log="iplog.txt"
# If a previous log file exists, delete it.
if [ -f ~/$IP_Log ]
   then rm ~/$IP_Log
fi
# Creating a new log file
touch ~/$IP_Log

pwd

echo "IP address:"
ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1 -d'/'

pwd >> "$IP_Log"
echo "IP address:" >> "$IP_Log"
ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1 -d'/' >> "$IP_Log"
