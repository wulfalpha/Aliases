#!/usr/bin/env python3

import os
import argparse
import logging
from PIL import Image
import imagehash
from send2trash import send2trash
from threading import Thread
from pathlib import Path

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, GdkPixbuf, GLib


class DupSleuth(Gtk.Window):
    def __init__(self):
        super().__init__(title="Dup Sleuth")
        self.set_border_width(10)
        self.set_default_size(800, 600)

        # Label for "Duplicate Images found:"
        self.label = Gtk.Label(label="Duplicate Images found:")
        self.label.set_hexpand(True)
        self.label.set_halign(Gtk.Align.START)

        self.image_list_store = Gtk.ListStore(GdkPixbuf.Pixbuf, str)
        self.icon_view = Gtk.IconView.new()
        self.icon_view.set_model(self.image_list_store)
        self.icon_view.set_pixbuf_column(0)
        self.icon_view.set_text_column(1)
        self.icon_view.set_item_width(150)

        scrollable_treelist = Gtk.ScrolledWindow()
        scrollable_treelist.set_vexpand(True)
        scrollable_treelist.add(self.icon_view)

        self.progress_bar = Gtk.ProgressBar()
        self.progress_bar.set_text("Initializing...")
        self.progress_bar.set_show_text(True)

        self.status_bar = Gtk.Statusbar()
        self.status_context_id = self.status_bar.get_context_id("file-status")

        self.vbox = Gtk.VBox(spacing=6)

        # Pack the label above the IconView
        self.vbox.pack_start(self.label, False, False, 0)
        self.vbox.pack_start(scrollable_treelist, True, True, 0)
        self.vbox.pack_start(self.progress_bar, False, False, 0)

        self.button = Gtk.Button(label="Done")
        self.button.connect("clicked", self.on_done_button_clicked)
        self.button_box = Gtk.Box(spacing=6, orientation=Gtk.Orientation.HORIZONTAL)
        self.button_box.set_homogeneous(True)
        self.button_box.pack_start(self.button, True, True, 0)

        self.vbox.pack_start(self.button_box, False, False, 0)
        self.add(self.vbox)

    def on_done_button_clicked(self, widget):
        Gtk.main_quit()

    def add_duplicate_image(self, image_path, original_file):
        if image_path.exists():
            try:
                pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(
                    str(image_path), 128, 128, True
                )
                self.image_list_store.append([pixbuf, f"Duplicate of: {original_file}"])
            except Exception as e:
                logging.warning(f"Failed to load image {image_path}: {e}")
        else:
            logging.warning(f"Skipped displaying {image_path}: file does not exist.")

    def update_status_bar(self, message):
        GLib.idle_add(self.status_bar.push, self.status_context_id, message)

    def update_progress_bar(self, text, fraction=None):
        GLib.idle_add(self.progress_bar.set_text, text)
        if fraction is not None:
            GLib.idle_add(self.progress_bar.set_fraction, fraction)

    def stop_progress_bar(self):
        self.update_progress_bar("Done", 1.0)
        GLib.idle_add(self.button.set_label, "Close")


def calculate_phash(image_path):
    """Calculate the perceptual hash (phash) for an image."""
    try:
        img = Image.open(str(image_path))
        img_hash = imagehash.phash(img)
        return str(img_hash)
    except Exception as e:
        logging.error(f"Error calculating phash for {image_path}: {e}")
        return None


def compare_images(image_hashes, image_path):
    """Compare the phash of the current image with already processed images."""
    new_hash = calculate_phash(image_path)
    if new_hash in image_hashes:
        return True, new_hash, image_hashes[new_hash]
    else:
        image_hashes[new_hash] = str(image_path)
        return False, new_hash, None


def move_to_trash(file_path):
    """Move the specified file to the trash."""
    try:
        send2trash(str(file_path))
        logging.info(f"Moved {file_path} to trash.")
        return True
    except Exception as e:
        logging.error(f"Error moving file {file_path} to trash: {e}")
        return False


def scan_images(directory, app):
    image_hashes = {}
    total_files = 0

    # Count total files for progress bar
    for root, _, files in os.walk(directory):
        for file_name in files:
            if file_name.lower().endswith((".png", ".jpg", ".jpeg")):
                total_files += 1

    scanned_files = 0

    try:
        with open("duplicates.txt", "w") as dup_file:
            for root, _, files in os.walk(directory):
                for file_name in files:
                    if file_name.lower().endswith((".png", ".jpg", ".jpeg")):
                        file_path = Path(root) / file_name
                        is_duplicate, new_hash, original_file = compare_images(
                            image_hashes, file_path
                        )
                        if is_duplicate:
                            logging.info(f"Duplicate found: {file_path}")
                            GLib.idle_add(
                                    app.add_duplicate_image, file_path, original_file
                                )
                            if move_to_trash(file_path):
                                dup_file.write(
                                    f"Duplicate found: {original_file} and {file_path} (moved to trash)\n"
                                )
                                # Ensure to update GUI only after the file is moved and still exists

                        # Update progress
                        scanned_files += 1
                        progress_fraction = scanned_files / total_files
                        GLib.idle_add(
                            app.update_progress_bar,
                            f"Scanning... {scanned_files}/{total_files} files",
                            progress_fraction,
                        )

    except Exception as e:
        GLib.idle_add(app.update_status_bar, f"An error occurred: {e}")
        logging.error(f"An error occurred: {e}")
    finally:
        GLib.idle_add(app.stop_progress_bar)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Compare images in a directory and move duplicates to trash."
    )
    parser.add_argument(
        "directory",
        type=str,
        help="The directory containing the image files to compare",
    )

    logging.basicConfig(
        level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
    )

    args = parser.parse_args()

    app = DupSleuth()

    def run_scan():
        scan_images(args.directory, app)

    thread = Thread(target=run_scan)
    thread.start()

    app.connect("destroy", Gtk.main_quit)
    app.show_all()
    Gtk.main()
