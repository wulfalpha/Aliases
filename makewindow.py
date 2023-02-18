#!/usr/bin/env python3
import sys
import argparse
import os


def greeting():
    print("Welcome to Window Maker for Pane.")
    print("A minimal SSB APP.")


def key():
    print("""
   Usage: makewindow [options]
    -n, --Name {name}          Name SSB
    -u, --URL {url}            URL for SSB
    -c, --Category {category}  Where to put SSB in Menu
    -i, --Icon {path to icon}  Path to Icon for SSB
    """)


parser = argparse.ArgumentParser()
greeting()
parser.add_argument("-n", "--Name", help="Name your new SSB")
parser.add_argument("-u", "--URL", help="URL for your SSB")
parser.add_argument("-c", "--Category", help="Where to put your SSB")
parser.add_argument("-i", "--Icon", help="path to icon")


args = parser.parse_args()

usr = os.environ["LOGNAME"]

if args.Name:
    nym = args.Name
    with open(f"{nym}.desktop", "x") as fb:
        fb.write("[Desktop Entry]\n")
        fb.write("Version=1.0\n")
        fb.write(f"Name={nym}\n")
        fb.write("Comment=Pane minimal SSB\n")
        if args.URL:
            qrl = args.URL
            fb.write(f"Exec=/home/{usr}/pane -l '{qrl}'\n")
        else:
            print("No url Passed!")

        if args.Icon:
            ico = args.Icon
            fb.write(f"Icon={ico}\n")
        else:
            print("No Icon Passed!")
        pth = f"/home/{usr}/.local/share/applications/"
        print(f"Path is: {pth}.")
        fb.write(f"Path={pth}\n")
        fb.write("Terminal=false\n")
        fb.write("Type=Application\n")
        if args.Category:
            cat = args.Category
            fb.write(f"Categories={cat};\n")
        else:
            print("No category Passed!")
        fb.write("StartupNotify=false")

    os.system(f"mv {nym}.desktop {pth}{nym}.desktop")
    print(f"{nym}.desktop file created at {pth}. ")

else:
    print("No name Passed!")
    print("No .desktop file created.")
    key()
