#! /bin/bash
# Created by WulfAlpha with love!
echo "What is your ip address?"

read -r ipaddr

echo "Connecting to Raspberry Pi..."

clear && pwd
# if you have Mosh installed (recommended) uncomment the mosh version. Otherwise uncomment the ssh version.
# ssh version
# ssh pi@ipaddr
# mosh version
mosh pi@"$ipaddr"
