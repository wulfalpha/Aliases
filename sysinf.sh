clear
Fetch="$(date).jpg"

echo "               System Info                 $(date)   "
neofetch

scrot -u "$Fetch"
read -n1 -r -p "Press any key to continue..."
