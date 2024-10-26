#!/usr/bin/env python3
"""
Pulls pop culture sayings from a saying.txt file. takes nothing returns nothing.
"""

from random import choice

worb_list = []
with open("/home/wulfalpha/sayings.txt", "r", encoding="utf-8") as db:
    for line in db:
        worb_list.append(line.strip())

print(choice(worb_list))
