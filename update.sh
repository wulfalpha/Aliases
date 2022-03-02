#! /bin/bash
clear
echo "Ready to update..."
read -n1 -r -p "Press enter to continue..."
echo "before running me uncomment the proper command to use..."
read -n1 -r -p "Press enter to continue..."
# For solus:
# sudo eopkg upgrade
# For Debian/Ubuntu:
# sudo apt update && sudo apt autoremove && sudo apt upgrade 
# For Manjaro:
# sudo pamac update
# For Arch:
# sudo pacman -Syu
# AUR Update command with yay:
# yay -Syu
# AUR update command with paru (recomended):
# paru
echo "Thanks for running this program!"
