#!/usr/bin/env python3
import os
import shutil
import argparse

def move_images(source_dir, dest_dir, overwrite):
    # Create the destination directory if it doesn't exist
    if not os.path.exists(dest_dir):
        os.mkdir(dest_dir)

    # Loop through all files in the source directory
    for filename in os.listdir(source_dir):
        # Check if the file is an image or gif
        if filename.endswith('.jpg') or filename.endswith('.jpeg') or filename.endswith('.png') or filename.endswith('.gif'):
            # Build the full file path for the source and destination
            src_path = os.path.join(source_dir, filename)
            dest_path = os.path.join(dest_dir, filename)

            # If the file already exists in the destination directory and the overwrite flag is not passed, warn the user
            if os.path.exists(dest_path) and not overwrite:
                print(f"Warning: {dest_path} already exists in the destination directory. Use -O to overwrite.")
                continue

            # Move the file to the destination directory, overwriting if the -O flag is passed
            shutil.move(src_path, dest_path, copy_function=shutil.copy2 if overwrite else shutil.copy)


if __name__ == '__main__':
    # Set up argparse to handle command-line arguments
    parser = argparse.ArgumentParser(description='Move images from a source directory to a new directory in Pictures called img-catch')
    parser.add_argument('source_dir', help='the source directory containing the images')
    parser.add_argument('-d', '--dest_dir', help='the destination directory for the images')
    parser.add_argument('-O', '--overwrite', action='store_true', help='overwrite existing files in the destination directory')
    args = parser.parse_args()


    # Set the destination directory to the default img-catch directory in Pictures if no directory is provided
    dest_dir = args.dest_dir or os.path.expanduser('~/Pictures/img-catch')

    # Call the move_images function with the user-provided source directory and the destination directory
    move_images(args.source_dir, dest_dir, args.overwrite)
