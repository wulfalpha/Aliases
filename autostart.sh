#!/bin/bash


#  __   __  ___  ____  ____  ___       _______   __      ___         _______    __    __       __
# |"  |/  \|  "|("  _||_ " ||"  |     /"     "| /""\    |"  |       |   __ "\  /" |  | "\     /""\
# |'  /    \:  ||   (  ) : |||  |    (: ______)/    \   ||  |       (. |__) :)(:  (__)  :)   /    \
# |: /'        |(:  |  | . )|:  |     \/    | /' /\  \  |:  |       |:  ____/  \/      \/   /' /\  \
#  \//  /\'    | \\ \__/ //  \  |___  // ___)//  __'  \  \  |___    (|  /      //  __  \\  //  __'  \
#  /   /  \\   | /\\ __ //\ ( \_|:  \(:  (  /   /  \\  \( \_|:  \  /|__/ \    (:  (  )  :)/   /  \\  \
# |___/    \___|(__________) \_______)\__/ (___/    \___)\_______)(_______)    \__|  |__/(___/    \___)


function run {
  if ! pgrep -x $(basename $1 | head -c 15) 1>/dev/null;
  then
    $@&
  fi
}

# Run the dynamic monitor configuration script
run $HOME/.config/qtile/scripts/detect-monitors.sh


# Set up notifications
# Ensure Dunst config exists for current theme
python3 "$HOME/.config/qtile/scripts/ensure_dunst_config.py"

# Use systemd to manage dunst (more reliable than manual startup)
systemctl --user restart dunst

run natural-scrolling-forever &
run fusuma -d && notify-send "Fusuma started" &

#Set your native resolution IF it does not exist in xrandr
#More info in the script
#run $HOME/.config/qtile/scripts/set-screen-resolution-in-virtualbox.sh

#Find out your monitor name with xrandr or arandr (save and you get this line)
#xrandr --output VGA-1 --primary --mode 1360x768 --pos 0x0 --rotate normal
#xrandr --output DP2 --primary --mode 1920x1080 --rate 60.00 --output LVDS1 --off &
#xrandr --output LVDS1 --mode 1366x768 --output DP3 --mode 1920x1080 --right-of LVDS1
#xrandr --output HDMI2 --mode 1920x1080 --pos 1920x0 --rotate normal --output HDMI1 --primary --mode 1920x1080 --pos 0x0 --rotate normal --output VIRTUAL1 --off
#autorandr horizontal

keybLayout=$(setxkbmap -v | awk -F "+" '/symbols/ {print $2}')

#Some ways to set your wallpaper besides variety or nitrogen
#feh --bg-fill /usr/share/backgrounds/archlinux/arch-wallpaper.jpg &
#feh --bg-fill /usr/share/backgrounds/arcolinux/arco-wallpaper.jpg &
#wallpaper for other Arch based systems
#feh --bg-fill /usr/share/archlinux-tweak-tool/data/wallpaper/wallpaper.png &
#start the conky to learn the shortcuts
#(conky -c $HOME/.config/qtile/scripts/system-overview) &

#start sxhkd to replace Qtile native key-bindings
#run sxhkd -c ~/.config/qtile/sxhkd/sxhkdrc &

run ~/.config/qtile/scripts/fanfare.sh &

#starting utility applications at boot time
# run variety &
run nm-applet &
run bauh-tray &
run ulauncher &
run xfce4-power-manager &
numlockx on &
blueberry-tray &
picom --config $HOME/.config/qtile/scripts/picom.conf &
/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 &
# /usr/lib/xfce4/notifyd/xfce4-notifyd &  # Disabled - using dunst via systemd instead

#starting user applications at boot time
run volumeicon &
#run discord &
run flameshot &
run /usr/lib/nordtray/nordtray &
#run /home/wulfalpha/.local/share/JetBrains/Toolbox/bin/jetbrains-toolbox %u &
nitrogen --restore &
run optimus-manager-qt &
run teamviewer --daemon start
#run caffeine -a &
#run vivaldi-stable &
#run firefox &
#run solaar &
run kdeconnect-indicator &
run meteo &
#run meteo-qt &
run syncthing &
run syncthingtray-qt6 &
run nordpass &
#run thunar &
#run dropbox &
run insync start &
run megasync &
#run searx-run &
run glance &
#emacs --daemon &
#run ollama serve &
#run spotify &
#run atom &
#run telegram-desktop &
