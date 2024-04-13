#!/usr/bin/env python
import gi
import subprocess as sub
import socket as sock
import sys

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk


def get_ip_address():
    try:
        return (
            sub.check_output(
                "ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1 -d'/'",
                shell=True,
            )
            .decode(sys.stdout.encoding)
            .strip()
        )
    except sub.CalledProcessError:
        return "Error retrieving IP"


class IPWindow(Gtk.Window):
    def __init__(self):
        super().__init__(title="IP Monger")
        self.configure_window()
        self.create_widgets()

    def configure_window(self):
        self.set_border_width(10)
        self.set_default_size(640, 200)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.set_resizable(True)

    def create_widgets(self):
        hostname = sock.gethostname()
        frame = Gtk.Frame(label=f"Hostname: {hostname}")
        grid = Gtk.Grid(row_spacing=10, column_spacing=10, column_homogeneous=True)

        ip_address = get_ip_address()

        ip_address_label = Gtk.Label(label="IP Address:")
        ip_address_label.set_hexpand(True)

        ip_value_label = Gtk.Label()
        ip_value_label.set_text(ip_address)
        ip_value_label.set_hexpand(True)

        quit_button = Gtk.Button(label="Quit")
        quit_button.set_hexpand(True)
        quit_button.connect("clicked", Gtk.main_quit)

        grid.attach(ip_address_label, 0, 2, 3, 2)
        grid.attach(ip_value_label, 0, 4, 3, 2)
        grid.attach(quit_button, 1, 8, 1, 1)

        self.add(frame)
        frame.add(grid)


if __name__ == "__main__":
    win = IPWindow()
    win.connect("destroy", Gtk.main_quit)
    win.show_all()
    Gtk.main()
