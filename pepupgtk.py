#!/usr/bin/env python3
import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk
import subprocess as s
from functools import partial
import apt


class PepUpWindow(Gtk.Window):
    """Window update class."""
    def __init__(self):
        super().__init__(title="Peppermint Update (GTK)")

        self.set_border_width(10)
        self.set_default_size(640, 200)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.set_resizable(True)

        frame1 = Gtk.Frame(label="Peppermint Update")

        grid1 = Gtk.Grid(row_spacing = 10, column_spacing = 10, column_homogeneous = True)

        label1 = Gtk.Label(label="Updates:")
        label1.set_hexpand(True)

        self.label2 = Gtk.Label(label="Ready...")
        self.label2.set_hexpand(True)
        self.label2.set_vexpand(True)


        button_updates = Gtk.Button(label="Check for updates.")
        button_updates.set_hexpand(True)
        button_updates.connect("clicked", self.on_button_updates_clicked)
        button_updates.set_tooltip_text("apt-get update")

        self.button_upgrade = Gtk.Button(label="Install Updates.")
        self.button_upgrade.set_hexpand(True)
        self.button_upgrade.set_sensitive(False)
        self.button_upgrade.connect("clicked", self.on_button_upgrade_clicked)
        self.button_upgrade.set_tooltip_text("apt-get upgrade")

        button_q = Gtk.Button(label="Quit")
        button_q.set_hexpand(True)
        button_q.connect("clicked", Gtk.main_quit)
        button_q.set_tooltip_text("Quit")

        grid1.attach(label1, 0, 2, 3, 2)
        grid1.attach(self.label2, 0, 4, 3, 2)
        grid1.attach(button_updates, 0, 8, 1, 1)
        grid1.attach(self.button_upgrade, 1, 8, 1, 1)
        grid1.attach(button_q, 2, 8, 1, 1)

        self.add(frame1)
        frame1.add(grid1)


    def on_button_updates_clicked(self, widget):
        """Button to check for updates"""
        s.run("apt-get -q update", shell=True)
        updates = s.run("apt-get -q -y --ignore-hold --allow-change-held-packages --allow-unauthenticated -s dist-upgrade | /bin/grep  ^Inst | wc -l", shell=True, stdout=s.PIPE).stdout.decode("utf-8").strip()
        if updates == "0":
            self.label2.set_text("Your system is up-to-date.")
            self.button_upgrade.set_sensitive(False)
        elif updates == "1":
            self.label2.set_text(f"There is one update available.")
            self.button_upgrade.set_sensitive(True)
        else:
            self.label2.set_text(f"There are {updates} updates available.")
            self.button_upgrade.set_sensitive(True)


    def on_button_upgrade_clicked(self, widget):
        """Button for upgrade. Unlocked only when updates are available."""
        s.run("nala upgrade -y", shell=True)
        self.label2.set_text("Update Complete!")


win1 = PepUpWindow()
win1.connect("destroy", Gtk.main_quit)
win1.show_all()
Gtk.main()
