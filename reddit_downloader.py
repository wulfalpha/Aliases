#!/usr/bin/env python3
import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, GLib
from subprocess import run
import shlex
import threading


class RedditWindow(Gtk.Window):
    """Window update class."""

    def __init__(self):
        super().__init__(title="Reddit Downloader (GTK)")

        self.set_border_width(10)
        self.set_default_size(640, 200)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.set_resizable(True)

        frame1 = Gtk.Frame(label="Reddit Downloader")
        grid1 = Gtk.Grid(row_spacing=10, column_spacing=10, column_homogeneous=True)

        self.status_label = Gtk.Label(label="Status: Ready...")
        self.status_label.set_hexpand(True)

        self.spinner = Gtk.Spinner()
        self.spinner.set_hexpand(True)
        self.spinner.set_vexpand(True)

        button_fetch_reddits = Gtk.Button(label="Get Images")
        button_fetch_reddits.set_hexpand(True)
        button_fetch_reddits.connect("clicked", self.on_button_fetch_reddits_clicked)
        button_fetch_reddits.set_tooltip_text("Reddit")

        reddit_list = Gtk.ListStore(int, str)
        reddit_list.append([1, "reddits.txt"])
        reddit_list.append([2, "moe.txt"])
        reddit_list.append([3, "imaginary.txt"])

        source_combo = Gtk.ComboBox.new_with_model_and_entry(reddit_list)
        source_combo.set_entry_text_column(1)
        source_combo.set_hexpand(True)
        source_combo.connect("changed", self.on_source_combo_changed)
        source_combo.set_tooltip_text("Source file")

        button_q = Gtk.Button(label="Quit")
        button_q.set_hexpand(True)
        button_q.connect("clicked", Gtk.main_quit)
        button_q.set_tooltip_text("Quit")

        grid1.attach(self.status_label, 0, 2, 3, 2)
        grid1.attach(self.spinner, 0, 4, 3, 2)
        grid1.attach(button_fetch_reddits, 0, 8, 1, 1)
        grid1.attach(source_combo, 1, 8, 1, 1)
        grid1.attach(button_q, 2, 8, 1, 1)

        self.add(frame1)
        frame1.add(grid1)

    def on_button_fetch_reddits_clicked(self, widget):
        """Button to fetch reddits"""
        self.spinner.start()

        # Create and start the worker thread
        thread = threading.Thread(target=self.fetch_reddit)
        thread.start()

    def on_source_combo_changed(self, combo):
        """Combo box V1: An attempt to let the user select the reddit list to pull from"""
        self.combo = combo
        tree_iter = combo.get_active_iter()
        if tree_iter is not None:
            model = combo.get_model()
            row_id, reddit = model[tree_iter][:2]
        else:
            entry = combo.get_child()
            reddit = entry.get_text()
        return reddit

    def update_status_label(self, text):
        """Update the status label in the main GTK thread"""
        GLib.idle_add(self.status_label.set_text, "Status: " + text)

    def fetch_reddit(self):
        """Method to fetch reddits from list."""
        count = 10
        file_path = "/home/wulfalpha/Pictures/reddits"
        reddit_list = self.on_source_combo_changed(self.combo)
        with open(reddit_list, "r") as stream:
            total_reddits = sum(1 for _ in stream)  # Count total number of reddits
            stream.seek(0)  # Reset file pointer to the beginning
            for i, reddit in enumerate(stream, start=1):
                reddit = reddit.strip()
                self.update_status_label(f"Downloading {reddit} ({i}/{total_reddits})")
                # Perform the download using bdfr here
                bdfr_command = f"bdfr download -s {reddit} -L {count} {file_path}"
                run(shlex.split(bdfr_command))
        self.update_status_label("Ready...")
        self.spinner.stop()


win1 = RedditWindow()
win1.connect("destroy", Gtk.main_quit)
win1.show_all()
Gtk.main()
