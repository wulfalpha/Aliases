#! /bin/bash
clear
echo "Updating System..."
sudo apt update && sudo apt autoremove --yes && sudo apt upgrade --yes && sudo apt autoclean
notify-send 'Update Complete!'
echo "Thanks for using this program!"
read -nl -r -p "Press enter to continue..."