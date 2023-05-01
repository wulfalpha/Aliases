#!/usr/bin/env python3
"""A program to make site specific browsers for the pane browser."""
import argparse
import os
import requests
from urllib.parse import urlparse, urljoin


def greeting():
    """Greeting"""
    print("Welcome to Window Maker for Pane.")
    print("A minimal SSB APP.")


def download_favicon(url):
    try:
        # Parse the URL to get the base URL
        base_url = urlparse(url).scheme + "://" + urlparse(url).hostname
        # Try to download the favicon
        response = requests.get(urljoin(base_url, "favicon.ico"), timeout=5)
        if response.status_code == 200:
            # Save the favicon as a file
            icon_path = os.path.expanduser(f"~/.local/share/icons/{nym}.ico")
            with open(icon_path, "wb") as f:
                f.write(response.content)
            print("Favicon downloaded successfully.")
            return icon_path
        else:
            print("Favicon not found.")
            return None
    except requests.exceptions.RequestException:
        print("Failed to download favicon.")
        return None


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
    desktop_path = os.path.expanduser("~/.local/share/applications/")
    with open(os.path.join(desktop_path, f"{nym}.desktop"), "x", encoding="utf-8") as fb:
        fb.write("[Desktop Entry]\n")
        fb.write("Version=1.0\n")
        fb.write(f"Name={nym}\n")
        fb.write("Comment=Pane minimal SSB\n")
        if args.URL:
            qrl = args.URL
            fb.write(f"Exec=pane -l '{qrl}'\n")
            if not args.Icon:
                # Try to download the favicon
                icon_path = download_favicon(qrl)
                if icon_path is not None:
                    fb.write(f"Icon={icon_path}\n")
        else:
            print("No url Passed!")

        if args.Icon:
            ico = os.path.expanduser(args.Icon)
            fb.write(f"Icon={ico}\n")
        if args.Path:
            pth = os.path.expanduser(args.Path)
            fb.write(f"Path={pth}\n")
        else:
            pth = os.path.expanduser("~/.local/share/applications/")
            print(f"default path {pth} selected!")
            fb.write(f"Path={pth}\n")
        fb.write("Terminal=false\n")
        fb.write("Type=Application\n")
        if args.Category:
            cat = args.Category
            fb.write(f"Categories={cat};\n")
        else:
            print("No category Passed!")
        fb.write("StartupNotify=false")
    if args.Icon:
        os.system(f"cp {ico} {icon_path}")
    print(f"{nym}.desktop file created at {desktop_path}. ")

else:
    print("No name passed!")
    print("No .desktop file created.")
    print("-h for help")
