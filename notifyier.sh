#!/usr/bin/env sh
notify-send -i nordvpn "Nord Select" "$(nordvpn status | tail -n 8)"
