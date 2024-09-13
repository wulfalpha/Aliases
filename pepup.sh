#! /bin/bash
# by: wulfAlpha
################################################################ Disclaimer ###
# These scripts come without warranty of any kind. Use them at your own risk. I
# assume no liability for the accuracy, correctness, completeness, or usefulness
# of any information provided by this script nor for any sort of damages using
# these scripts may cause.
#
# pepup is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# any later version.
#
# pepup is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

########################################################## Init ###
name="System_Update"
dt="$(date)"
Update_log=$name".md"

# If exist a previews update file, delete it
if [[ -f ~/$Update_log ]]
  then rm ~/$Update_log
fi
# Create a new log file
touch ~/$Update_log
########################################### Colors ###
# BackGround with setab
bred=`tput setab 1`	# red
# ForeGrownd with setaf
red=`tput setaf 1`	# red
grn=`tput setaf 2`	# yellow
wht=`tput setaf 7`	# white
# TxtFormat with setaf
bld=`tput bold`    # Select bold mode
# DefautMode with setaf
reset=`tput sgr0`
# Hide/show cursor
nshw() { tput civis    # Hide cursor
}
yshw() { tput cnorm # return cursor to normal
}
# Peppermint Color
Peppermint_Color=${bred}${bld}${wht}
Peppermint_msg=${bld}${bred}${wht}
Peppermint_good=${bld}${red}
Peppermint_note=${bld}${red}
Peppermint_err=${bld}${bred}${wht}
################################################################## Text ###
title() { # ≡ message
printf "${Peppermint_Color} %s${reset}\n" "$@"
}
msg() { # ⓘ message
printf "${Peppermint_msg} ⁖ ${reset}${bld}%s \n${reset}" "$@"
}
finished() {
if [[ "$*" == "" ]];
  then printf " ${Peppermint_good}[ ☑ COMPLETED ] ${reset}\n";
else
  printf " ${Peppermint_good}[ ☑ %s ] ${reset}\n" "$@"
fi
}
note() { # [ NOTES ] message
printf "${Peppermint_note} > ${reset} %s \n" "$@"
}
notice() { # [ ⚠ message ]
if [ "$*" == "" ];
  then printf "${Peppermint_err} [ ⚠ WARNING ] ${reset}\n"
fi
printf "${Peppermint_err} [ ⚡ %s ] ${reset}\n" "$@"
}
############################################################ Root ###
is_root() { # I am Root!
if [ "$(id -u)" -ne 0 ]; then sudo ls >/dev/null; fi
}
######################################################### Updating functions ###
get() { # get updates
sudo apt-get -y update >> ~/"$Update_log"
}
up() { # install
sudo apt-get -y upgrade >> ~/"$Update_log"
}
housekeeping() { # clean up
  sudo apt-get -y autoremove >> ~/"$Update_log"
  sudo apt-get -y autoclean >> ~/"$Update_log"
}
############################################################ Progress Bar +  ###
spin() {
##  SYNTAX: spin "COMMAND" " Message" "Name of the job"
##          spin "third action" "action" "3rd action"
  nshw # hide cursor

  # LP="\e[2K"
  # Spinner Character
  SPINNER="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"

  spinner() { # start
    task=$1
    msgs=$2
    while :; do
      jobs %1 > /dev/null 2>&1
      [ $? = 0 ] || {
       # printf "${LP}✓ ${task} Done"
       finished "$task Done"
        break
      }
      for (( i=0; i<${#SPINNER}; i++ )); do
        sleep 0.05
        printf "${bld}${red}${SPINNER:$i:1}${reset} ${Peppermint_msg} ${task} ${msgs}${reset}\r"
      done
    done
  }

  msgs="${2-InProgress}"
  task="${3-$1}"
  $1 & spinner "$task" "$msg"

  yshw  # return cursor
}

############################################################## System Update ###
pepup() {
#  mupdate=`sudo apt-get update -y`
  title " ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒ Pepermint Update ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒  "
        echo "$dt"
        echo
        echo "# System Update" > ~/"$Update_log"
        echo "**"$Update_log"**" $dt >> ~/"$Update_log"
  msg " Checking for Updates..."
        echo "## Checking for Updates" >> ~/"$Update_log"
  notice "... this may take some time ..."
  spin 'get' " checking... " "Dowloading"
  msg " Installing new updates..."
        echo "## Instaling new Updates..." >> ~/"$Update_log"
  notice "... please be wait ..."
  spin "up" " updates... " "Installing"
  msg " ... Cleaning up ..."
        echo "## Final run..." >> ~/"$Update_log"
        echo "*... Cleaning up ...*" >> ~/"$Update_log"
  spin "housekeeping" " removing un-needed programs... " "Cleaning up... "
        echo "[END]" >> ~/"$Update_log"
}

final() {
#clear
title " ▞▞▞▞▞▞▞▞▞▞▞▞▞▞▞▞▞▞▞▞▞▞▞▞▞▞▞▞ Finished Updating! ▚▚▚▚▚▚▚▚▚▚▚▚▚▚▚▚▚▚▚▚▚▚▚▚▚▚▚▚  "
echo
echo "For more information see the update log file:"
notify-send 'Update Complete!'
echo "${bld}>${grn} $Update_log${reset} located in your home directory"
echo
#read -p "Press [Enter] key to exit..."
read -n1 -r -p " Press ${bld}\"Q\"${reset} to ${bld}Q${reset}uit, or $bld\"L\"$reset to view the log file. " pause
}

view_log() {
[ "$pause" = "l" ] || [ "$pause" = "L" ] && ( clear
 echo -e "$(cat ~/${Update_log})\n\n\t Press ${bld}\"Q\"${reset} to ${bld}Q${reset}uit and close this window. " | less -R
 clear
 ) || clear
}

clear
is_root
pepup
final
view_log
