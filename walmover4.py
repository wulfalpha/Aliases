#!/usr/bin/env python3

import shutil
from pathlib import Path
from threading import Thread

import gi
from PIL import Image

gi.require_version("Gtk", "3.0")
from gi.repository import GdkPixbuf, GLib, Gtk


class Walmover(Gtk.Window):
    def __init__(self):
        super().__init__(title="Walmover GTK")
        self.set_border_width(10)
        self.set_default_size(800, 600)

        self.src_dir = None
        self.dest_dir = None

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

        # Button to select source directory
        self.src_button = Gtk.Button(label="Source")
        self.src_button.connect("clicked", self.on_src_button_clicked)

        # Button to select destination directory
        self.dest_button = Gtk.Button(label="Destination")
        self.dest_button.connect("clicked", self.on_dest_button_clicked)

        # Start button to initiate the process
        self.start_button = Gtk.Button(label="Start")
        self.start_button.set_sensitive(
            False
        )  # Disabled until directories are selected
        self.start_button.connect("clicked", self.on_start_button_clicked)

        # Done button to exit the application
        self.done_button = Gtk.Button(label="Quit")
        self.done_button.connect("clicked", self.on_done_button_clicked)

        self.vbox = Gtk.VBox(spacing=6)
        self.vbox.pack_start(scrollable_treelist, True, True, 0)
        self.vbox.pack_start(self.progress_bar, False, False, 0)

        # Bottom button box for Done, Source Dir, Dest Dir, and Start buttons
        self.button_box = Gtk.Box(spacing=6, orientation=Gtk.Orientation.HORIZONTAL)
        self.button_box.set_homogeneous(True)
        self.button_box.pack_start(self.done_button, True, True, 0)
        self.button_box.pack_start(self.src_button, True, True, 0)
        self.button_box.pack_start(self.dest_button, True, True, 0)
        self.button_box.pack_start(self.start_button, True, True, 0)

        self.vbox.pack_start(self.button_box, False, False, 0)
        self.add(self.vbox)

    def on_done_button_clicked(self, widget):
        Gtk.main_quit()

    def on_src_button_clicked(self, widget):
        dialog = Gtk.FileChooserDialog(
            title="Select Source Directory",
            action=Gtk.FileChooserAction.SELECT_FOLDER,
            buttons=(
                Gtk.STOCK_CANCEL,
                Gtk.ResponseType.CANCEL,
                Gtk.STOCK_OPEN,
                Gtk.ResponseType.OK,
            ),
        )
        response = dialog.run()
        if response == Gtk.ResponseType.OK:
            self.src_dir = Path(dialog.get_filename())
            # Update the label to reflect only the directory name
            self.src_button.set_label(f"Source: {self.src_dir.name}")
            self.check_start_conditions()

        dialog.destroy()

    def on_dest_button_clicked(self, widget):
        dialog = Gtk.FileChooserDialog(
            title="Select Destination Directory",
            action=Gtk.FileChooserAction.SELECT_FOLDER,
            buttons=(
                Gtk.STOCK_CANCEL,
                Gtk.ResponseType.CANCEL,
                Gtk.STOCK_OPEN,
                Gtk.ResponseType.OK,
            ),
        )
        response = dialog.run()
        if response == Gtk.ResponseType.OK:
            self.dest_dir = Path(dialog.get_filename())
            # Update the label to reflect only the directory name
            self.dest_button.set_label(f"Destination: {self.dest_dir.name}")
            self.check_start_conditions()

        dialog.destroy()

    def check_start_conditions(self):
        # Enable the start button only when both directories are selected
        if self.src_dir and self.dest_dir:
            self.start_button.set_sensitive(True)

    def on_start_button_clicked(self, widget):
        if not self.src_dir or not self.dest_dir:
            return

        if not self.dest_dir.is_dir():
            self.dest_dir.mkdir(parents=True, exist_ok=True)

        # Start copying images in a new thread
        thread = Thread(target=self.copy_images_with_aspect_ratio)
        thread.start()

    def add_image(self, image_path, exists=False):
        pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(
            str(image_path), 128, 128, True
        )
        self.image_list_store.append([pixbuf, image_path.name])
        if exists:
            GLib.idle_add(
                self.update_progress_bar, f"File already exists: {image_path.name}"
            )

    def update_progress_bar(self, message, fraction=None):
        if fraction is not None:
            self.progress_bar.set_fraction(fraction)
        self.progress_bar.set_text(message)

    def stop_progress_bar(self):
        self.progress_bar.set_fraction(1.0)
        self.progress_bar.set_text("Operation complete")

    def copy_images_with_aspect_ratio(self):
        try:
            image_files = list(self.src_dir.iterdir())
            total_files = len(image_files)
            for idx, file_path in enumerate(image_files):
                if not is_valid_image(file_path):
                    continue

                with Image.open(file_path) as img:
                    width, height = img.size

                if has_aspect_ratio(width, height):
                    dest_path = self.dest_dir / file_path.name

                    if not dest_path.exists():
                        shutil.copy(file_path, dest_path)
                        self.add_image(dest_path)
                    else:
                        self.add_image(dest_path, exists=True)

                fraction = (idx + 1) / total_files
                GLib.idle_add(
                    self.update_progress_bar, f"Processing {file_path.name}", fraction
                )

        except IOError as e:
            print(f"An IOError occurred: {e}")
        except Exception as e:
            print(f"An unexpected error occurred: {e}")
        finally:
            GLib.idle_add(self.stop_progress_bar)


def is_valid_image(file_path):
    return file_path.is_file() and file_path.suffix.lower() in [".png", ".jpg", ".jpeg"]


def has_aspect_ratio(width, height, ratio=(16, 9)):
    calculated_ratio = width / height
    expected_ratio = ratio[0] / ratio[1]
    return 0.95 * expected_ratio <= calculated_ratio <= 1.05 * expected_ratio


if __name__ == "__main__":
    app = Walmover()
    app.connect("destroy", Gtk.main_quit)
    app.show_all()
    Gtk.main()
