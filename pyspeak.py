#!/usr/bin/env python3
"""
Pulls pop culture sayings from a saying.txt file. Takes nothing, returns nothing.
"""

from random import randrange


def get_random_line(file_path):
    with open(file_path, "r", encoding="utf-8") as db:
        # Determine the number of lines in the file
        line_count = sum(1 for _ in db)
        if line_count == 0:
            return None

        # Select a random line number and read that line
        random_line_number = randrange(line_count)
        db.seek(0)  # Go back to the start of the file
        for current_line_number, line in enumerate(db):
            if current_line_number == random_line_number:
                return line.strip()


saying = get_random_line("/home/wulfalpha/sayings.txt")
if saying:
    print(saying)
