#!/usr/bin/env python3
import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk
import subprocess as sub
import socket as sock
import sys


set = ""


class IPWindow(Gtk.Window):
    def __init__(self):
        super().__init__(title="IP Monger")

        self.set_border_width(10)
        self.set_default_size(640, 200)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.set_resizable(True)
        hostname = sock.gethostname()
        frame1 = Gtk.Frame(label=f"Hostname: {hostname}")

        grid1 = Gtk.Grid(row_spacing = 10, column_spacing = 10, column_homogeneous = True)


        ipAddr = sub.check_output("ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1 -d'/'", shell=True).decode(sys.stdout.encoding).strip()

        label1 = Gtk.Label(label="IP Address:")
        label1.set_hexpand(True)

        label2 = Gtk.Label()
        label3 = Gtk.Label()
        label3.set_text(ipAddr)
        label3.set_hexpand(True)


        button_q = Gtk.Button(label="Quit")
        button_q.set_hexpand(True)
        button_q.connect("clicked", Gtk.main_quit)

        grid1.attach(label1,  0, 2, 3, 2)
        grid1.attach(label2,  0, 4, 3, 2)
        grid1.attach(label3,  0, 6, 3, 1)
        grid1.attach(button_q, 2, 8, 1, 1)

        self.add(frame1)
        frame1.add(grid1)


win1 = IPWindow()

win1.connect("destroy", Gtk.main_quit)

win1.show_all()
Gtk.main()
