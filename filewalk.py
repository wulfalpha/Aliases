#!/usr/bin/env python3
import argparse
import os
import subprocess


parser = argparse.ArgumentParser(description='Process files in subdirectories')
parser.add_argument('start_dir', nargs='?', default='.',
                    help='the directory to start processing from (default: current directory)')
parser.add_argument('-v', '--videos', action='store_true')
parser.add_argument('-t', '--text', action='store_true')
args = parser.parse_args()

# define file handlers for various file types
program = {}
# for text files
program["txt"] = "micro"
# for video files
program["mkv"] = "mpv"
program["mp4"] = "mpv"
# for image files
program["png"] = "viewnior"
program["jpg"] = "viewnior"
program["jpeg"] = "viewnior"
program["gif"] = "viewnior"

# Remove extensions that the user didn't pass in via an arg
if not args.text:
    program.pop("txt")

if not args.videos:
    program.pop("mkv")
    program.pop("mp4")

print(f"looking in {args.start_dir}")
print(f"I will look for {list(program.keys())}")

try:
    # os.walk is standard lib's recursive folder delve
    for parent_dir, folders, files in sorted(os.walk(args.start_dir), key=lambda s: s[0].lower()):
        current_dir = os.path.basename(parent_dir)
        print(f"⇀ {current_dir} ↽")
        work_files = files
        work_files.sort()
        for file in work_files:
            ext = os.path.splitext(file)[-1].strip('.').lower()
            print(f"deciding how to handle {ext=}")
            if ext not in program:
                # we don't have a handler for this file, skip it
                print(f"Can't handle {ext}, skipping!")
                continue

            print(f"opening {file} with {program[ext]}")

            with subprocess.Popen([
                program[ext],
                os.path.join(parent_dir, file)
            ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) as proc:
                proc.wait()

    print(f"Done with {args.start_dir}!")
except KeyboardInterrupt:
    print()
    print("Cancled...")
finally:
    print("Goodbye")
