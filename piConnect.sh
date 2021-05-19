#! /bin/bash
echo "What is your ip address"

read ipaddr

echo "Connecting to Raspberry Pi"

# if you have Mosh installed (recommended) uncomment the mosh version. Otherwise uncomment the ssh version.
# ssh version
# ssh pi@ipaddr

mosh version
mosh pi@$ipaddr
