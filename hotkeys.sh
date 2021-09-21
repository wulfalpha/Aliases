#!/usr/bin/env bash

sed -n '/#HKeys/,/#HKeys-End/p' .config/qtile/sxhkd/sxhkdrc | grep -v '##'| grep -v '#-' | yad --text-info --back=#282c34 --fore=#46d9ff --geometry=1200x800
