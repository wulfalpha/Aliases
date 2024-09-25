#!/usr/bin/env python3

import logging
import os
from pathlib import Path
from threading import Thread

import gi
import imagehash
from PIL import Image
from send2trash import send2trash

gi.require_version("Gtk", "3.0")
from gi.repository import GdkPixbuf, GLib, Gtk


class DupSleuth(Gtk.Window):
    def __init__(self):
        super().__init__(title="Dup Sleuth")
        self.set_border_width(10)
        self.set_default_size(800, 600)

        self.directory = None

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

        # VBox for layout
        self.vbox = Gtk.VBox(spacing=6)
        self.vbox.pack_start(self.label, False, False, 0)
        self.vbox.pack_start(scrollable_treelist, True, True, 0)
        self.vbox.pack_start(self.progress_bar, False, False, 0)

        # Button for selecting directory
        self.select_directory_button = Gtk.Button(label="Select Source Directory")
        self.select_directory_button.connect("clicked", self.on_select_directory)

        # Close button
        self.close_button = Gtk.Button(label="Close")
        self.close_button.connect("clicked", self.on_quit)

        # HBox for buttons at the bottom
        self.button_box = Gtk.HBox(spacing=6)
        self.button_box.pack_start(self.select_directory_button, True, True, 0)
        self.button_box.pack_start(self.close_button, True, True, 0)

        self.vbox.pack_start(self.button_box, False, False, 0)

        self.add(self.vbox)

    def on_select_directory(self, widget):
        # Use file chooser portal for selecting a directory
        dialog = Gtk.FileChooserDialog(
            title="Please choose a directory",
            parent=self,
            action=Gtk.FileChooserAction.SELECT_FOLDER,
        )
        dialog.add_buttons(
            Gtk.STOCK_CANCEL,
            Gtk.ResponseType.CANCEL,
            Gtk.STOCK_OPEN,
            Gtk.ResponseType.OK,
        )

        response = dialog.run()
        if response == Gtk.ResponseType.OK:
            self.directory = dialog.get_filename()
            logging.info(f"Selected directory: {self.directory}")
            # Start scanning in a separate thread
            self.start_scan()
        dialog.destroy()

    def start_scan(self):
        if self.directory:
            self.progress_bar.set_fraction(0.0)
            self.progress_bar.set_text("Scanning...")
            self.image_list_store.clear()  # Clear previous results

            thread = Thread(target=scan_images, args=(self.directory, self))
            thread.start()

    def on_quit(self, widget):
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
        GLib.idle_add(self.close_button.set_label, "Close")


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
    logging.basicConfig(
        level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
    )

    app = DupSleuth()

    app.connect("destroy", Gtk.main_quit)
    app.show_all()
    Gtk.main()
