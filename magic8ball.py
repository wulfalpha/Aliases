#!/usr/bin/env python3
# magic8ball.py - a simple magic 8 ball game

import os
from random import choice
from time import sleep

CHOICES = [
    "It is certain",
    "It is decidedly so",
    "Without a doubt",
    "Yes, definitely",
    "You may rely on it",
    "As I see it, yes",
    "Most likely",
    "Outlook good",
    "Yes",
    "Signs point to yes",
    "Reply hazy try again",
    "Ask again later",
    "Better not tell you now",
    "Cannot predict now",
    "Concentrate and ask again",
    "Don't count on it",
    "My reply is no",
    "My sources say no",
    "Outlook not so good",
    "Very doubtful",
]


def shake_ball():
    """Pick a random answer from CHOICES, clear the screen, and print the result."""
    answer = choice(CHOICES)
    logo()
    print(answer)


def logo():
    """Clear the terminal and print the Magic 8 ball ASCII art logo."""
    os.system("cls" if os.name == "nt" else "clear")
    print("""
           ____
       ,dP9CGG88@b,
     ,IP  _   Y888@@b,
     dIi  (_)   G8888@b
    dCII  (_)   G8888@@b
    GCCIi     ,GG8888@@@
    GGCCCCCCCGGG88888@@@
    GGGGCCCGGGG88888@@@@...
    Y8GGGGGG8888888@@@@P.....
    Y88888888888@@@@@P......
    `Y8888888@@@@@@@P'......
       `@@@@@@@@@P'.......
          ----- ........
    """)


def start():
    """Display the logo and print the welcome message."""
    logo()
    print("Welcome to the Magic 8ball Program!")
    print("I am a Magic 8 ball.")
    sleep(0.5)


def main():
    """Run the main game loop, prompting the user to shake the ball until they quit."""
    start()
    print("Just give me a toss to get your Mystical Answer.")
    print("Would you like to shake the 8 ball? y/n")
    roll = input().lower()
    sleep(0.5)
    while roll == "y":
        shake_ball()
        print("Would you like to shake the 8 ball again? y/n")
        roll = input().lower()
    if roll != "n":
        print("Sorry, I didn't understand " + roll)
        return
    print("Thanks for running this program!")


if __name__ == "__main__":
    main()
