#!/usr/bin/env python3
from datetime import datetime as dt
from time import sleep
from os import name, system


def greeting():
    print("Welcome to Pytime!")


def main():
    greeting()
    print("Press Control + C to quit!")
    sleep(1)
    clear_scr()
    try:
        while True:
            time = time_now()
            print(dt.strftime(time, "%A %B %d %y | %r"), end="", flush=True)
            print(dt.strftime(time, " | %H:%M:%S"), end="", flush=True)
            print("\r", end="", flush=True)
            sleep(1)
    except KeyboardInterrupt:
        print("Goodbye!")
        input("Press enter to close window.")

def time_now():
    return dt.now()


def clear_scr():
    if name == "nt":
        system("cls")
    else:
        system("clear")


if __name__ == "__main__":
    main()
