#!/usr/bin/env bash

clear
ip -4 a | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1 -d'/'
