#!/usr/bin/env bash
clear
echo "Updating System..."
for i in paru yay pacman;
do
    if [ "$i" = "paru" ]
    then
        echo "Paru detected..."
        sudo paru -Syu
        break
    fi
    if [  "$i" = "yay" ]
    then
        echo "Yay detected..."
        sudo yay -Syu
        break
    fi
    if [ "$i" = "pacman" ]
    then
        echo "No helper Detected..."
        sudo pacman -Syu
    fi
done
notify-send 'Update Complete!'
echo "Thanks for using this program!"
read -n1 -r -p "Press enter to continue..."
