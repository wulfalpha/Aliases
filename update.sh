#! /bin/bash
echo "Ready to update..."
echo "press enter to continue..."
pause
echo "before running me uncomment the proper command to use... Press enter to Continue"
pause
# For solus:
# sudo eopkg upgrade
# For Debian/Ubuntu:
# sudo apt update && sudo apt autoremove && sudo apt upgrade 
# For Manjaro:
# sudo pamac update
# For Arch:
# sudo pacman -Syu
# AUR Update command with yay (note yay is not recommended):
# yay -Syu
# AUR update command with paru (recomended):
# paru -Syu
echo "Thanks for running this program!"
