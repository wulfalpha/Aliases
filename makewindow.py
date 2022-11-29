#!/usr/bin/env python3
import sys
import argparse
import os


def greeting():
    print("Welcome to Window Maker for Pane.")
    print("A minimal SSB APP.")


def key():
    print("""
    Possible flags:
    -n, --Name - Name SSB
    -u, --URL - URL for SSB
    -c, --Category - Where to put SSB in Menu
    -i, --Icon - Path to Icon for SSB
    -p, --Path - for .desktop file for SSB
    """)


parser = argparse.ArgumentParser()
greeting()
parser.add_argument("-n", "--Name", help="Name your new SSB")
parser.add_argument("-u", "--URL", help="URL for your SSB")
parser.add_argument("-c", "--Category", help="Where to put your SSB")
parser.add_argument("-i", "--Icon", help="path to icon")
parser.add_argument("-p", "--Path", help="file Path")

args = parser.parse_args()

if args.Name:
    nym = args.Name
    with open(f"{nym}.desktop", "x") as fb:
        fb.write("[Desktop Entry]\n")
        fb.write("Version=1.0\n")
        fb.write(f"Name={nym}\n")
        fb.write("Comment=pane minimal SSB\n")
        if args.URL:
            qrl = args.URL
            fb.write(f"Exec=pane -l '{qrl}'\n")
        else:
            print("No url Passed!")

        if args.Icon:
            ico = args.Icon
            fb.write(f"Icon={ico}\n")
        else:
            print("No Icon Passed!")
        if args.Path:
            pth = args.Path
            fb.write(f"Path={pth}\n")
        else:
            pth = "./local/share/applications/"
            print(f"default path {pth} selected!")
            fb.write("Path={pth}\n")
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
