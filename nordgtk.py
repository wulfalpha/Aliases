#!/usr/bin/env python3
import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk
import subprocess as sub
from time import sleep


class NordWindow(Gtk.Window):
    def __init__(self):
        super().__init__(title="Nord Select (Gtk)")

        self.set_border_width(10)
        self.set_default_size(640, 200)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.set_resizable(True)

        frame1 = Gtk.Frame(label="Nord Select")
        nord = sub.check_output(["nordvpn", "status"]).decode()
        switch = False
        if "Disconnected" in nord:
            sub.call(["./notimin.sh"])
        else:
            sub.call(["./notifyier.sh"])

        grid1 = Gtk.Grid(row_spacing = 10, column_spacing = 10, column_homogeneous = True)

        label1 = Gtk.Label(label="Select a server Below.")
        label1.set_hexpand(True)

        if "Connected" in nord:
            status = "Connected"
        else:
            status = "Disconnected"

        label2 = Gtk.Label()
        self.label3 = Gtk.Label(status)
        self.label3.set_hexpand(True)

        button_us = Gtk.Button(label="🇺🇸")
        button_us.set_hexpand(True)
        button_us.connect("clicked", self.on_button_us_clicked)


        button_uk = Gtk.Button(label="🇬🇧")
        button_uk.set_hexpand(True)
        button_uk.connect("clicked", self.on_button_uk_clicked)


        button_jp = Gtk.Button(label="🇯🇵")
        button_jp.set_hexpand(True)
        button_jp.connect("clicked", self.on_button_jp_clicked)

        button_mx = Gtk.Button(label="🇲🇽")
        button_mx.set_hexpand(True)
        button_mx.connect("clicked", self.on_button_mx_clicked)

        button_ca = Gtk.Button(label="🇨🇦")
        button_ca.set_hexpand(True)
        button_ca.connect("clicked", self.on_button_ca_clicked)

        button_fn = Gtk.Button(label="🇫🇮")
        button_fn.set_hexpand(True)
        button_fn.connect("clicked", self.on_button_fn_clicked)

        button_ex = Gtk.Button(label="⏼")
        button_ex.set_hexpand(True)
        button_ex.connect("clicked", self.on_button_ex_clicked)

        button_q = Gtk.Button(label="Quit")
        button_q.set_hexpand(True)
        button_q.connect("clicked", Gtk.main_quit)

        grid1.attach(label1,  0, 2, 3, 2)
        grid1.attach(label2,  0, 4, 3, 2)
        grid1.attach(self.label3,  0, 6, 3, 1)
        grid1.attach(button_us, 0, 7, 1, 1)
        grid1.attach(button_uk, 1, 7, 1, 1)
        grid1.attach(button_jp, 2, 7, 1, 1)
        grid1.attach(button_mx, 0, 8, 1, 1)
        grid1.attach(button_ca, 1, 8, 1, 1)
        grid1.attach(button_fn, 2, 8, 1, 1)
        grid1.attach(button_ex, 0, 9, 1, 1)
        grid1.attach(button_q, 2, 9, 1, 1)

        self.add(frame1)
        frame1.add(grid1)


    def on_button_us_clicked(self, widget):
        sub.Popen("nordvpn connect us", shell=True)
        self.label3.set_text("US")
        sleep(1.5)
        sub.call(["./notifyier.sh"])


    def on_button_uk_clicked(self, widget):
        sub.Popen("nordvpn connect uk", shell=True)
        self.label3.set_text("UK")
        sleep(1.5)
        sub.call(["./notifyier.sh"])


    def on_button_jp_clicked(self, widget):
        sub.Popen("nordvpn connect jp", shell=True)
        self.label3.set_text("Japan")
        sleep(1.5)
        sub.call(["./notifyier.sh"])


    def on_button_mx_clicked(self, widget):
        sub.Popen("nordvpn connect mexico", shell=True)
        self.label3.set_text("Mexico")
        sleep(1.5)
        sub.call(["./notifyier.sh"])


    def on_button_ca_clicked(self, widget):
        sub.Popen("nordvpn connect ca", shell=True)
        self.label3.set_text("Canada")
        sleep(1.5)
        sub.call(["./notifyier.sh"])


    def on_button_fn_clicked(self, widget):
        sub.Popen("nordvpn connect finland", shell=True)
        self.label3.set_text("Finland")
        sleep(1.5)
        sub.call(["./notifyier.sh"])


    def on_button_ex_clicked(self,widget):
        sub.Popen("nordvpn d", shell=True)
        self.label3.set_text("Disconnected")
        sleep(1)
        sub.call(["./notimin.sh"])


win1 = NordWindow()
win1.connect("destroy", Gtk.main_quit)
win1.show_all()
Gtk.main()
