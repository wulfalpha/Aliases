#!/usr/bin/env python3

import argparse
import shutil
import sys
from pathlib import Path
from PIL import Image
from threading import Thread
import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, GdkPixbuf, GLib


class walmover(Gtk.Window):
    def __init__(self):
        super().__init__(title="Walmover GTK")
        self.set_border_width(10)
        self.set_default_size(800, 600)

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
        self.progress_bar.set_show_text(True)

        self.vbox = Gtk.VBox(spacing=6)
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

    def add_image(self, image_path, exists=False):
        pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(
            str(image_path), 128, 128, True
        )
        self.image_list_store.append([pixbuf, image_path.name])
        if exists:
            GLib.idle_add(self.update_progress_bar, f"File already exists: {image_path.name}")

    def update_progress_bar(self, message, fraction=None):
        if fraction is not None:
            self.progress_bar.set_fraction(fraction)
        self.progress_bar.set_text(message)

    def stop_progress_bar(self):
        self.progress_bar.set_fraction(1.0)
        self.progress_bar.set_text("Operation complete")


def is_valid_image(file_path):
    return file_path.is_file() and file_path.suffix.lower() in [".png", ".jpg", ".jpeg"]


def has_aspect_ratio(width, height, ratio=(16, 9)):
    calculated_ratio = width / height
    expected_ratio = ratio[0] / ratio[1]
    return 0.95 * expected_ratio <= calculated_ratio <= 1.05 * expected_ratio


def copy_images_with_aspect_ratio(src_dir, dest_dir, app):
    try:
        image_files = list(src_dir.iterdir())
        total_files = len(image_files)
        for idx, file_path in enumerate(image_files):
            if not is_valid_image(file_path):
                continue

            with Image.open(file_path) as img:
                width, height = img.size

            if has_aspect_ratio(width, height):
                dest_path = dest_dir / file_path.name

                if not dest_path.exists():
                    shutil.copy(file_path, dest_path)
                    app.add_image(dest_path)
                else:
                    app.add_image(dest_path, exists=True)

            fraction = (idx + 1) / total_files
            GLib.idle_add(app.update_progress_bar, f"Processing {file_path.name}", fraction)

    except IOError as e:
        print(f"An IOError occurred: {e}")
    except Exception as e:
        print(f"An unexpected error occurred: {e}")
    finally:
        GLib.idle_add(app.stop_progress_bar)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Copy images with 16:9 aspect ratio from source to destination directory"
    )
    parser.add_argument("source", type=str, help="The source directory")
    parser.add_argument("destination", type=str, help="The destination directory")
    args = parser.parse_args()

    src_dir = Path(args.source)
    dest_dir = Path(args.destination)

    if not src_dir.is_dir():
        print(f"Error: {args.source} is not a valid directory!")
        sys.exit(1)

    if not dest_dir.is_dir():
        dest_dir.mkdir(parents=True, exist_ok=True)

    app = walmover()

    def copy_images():
        copy_images_with_aspect_ratio(src_dir, dest_dir, app)

    thread = Thread(target=copy_images)
    thread.start()

    app.connect("destroy", Gtk.main_quit)
    app.show_all()
    Gtk.main()
