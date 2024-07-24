#!/usr/bin/env python3
import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gtk, Gdk
import yaml
import os
import subprocess as sub
from time import sleep


class NordWindow(Gtk.Window):
    def __init__(self):
        super().__init__(title="Nord Select (Gtk)")
        self.set_border_width(10)
        self.set_default_size(640, 200)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.set_resizable(True)

        self.buttons = {}
        self.server_codes = {}

        frame1 = Gtk.Frame(label="Nord Select")
        grid1 = Gtk.Grid(row_spacing=10, column_spacing=10, column_homogeneous=True)

        label1 = Gtk.Label(label="Select a server Below.")
        label1.set_hexpand(True)

        self.label3 = Gtk.Label(label="")
        self.label3.set_hexpand(True)

        grid1.attach(label1, 0, 0, 3, 1)
        grid1.attach(self.label3, 0, 1, 3, 1)

        # Load servers from YAML file
        config_path = os.path.expanduser("~/.config/nordselect/config.yaml")
        with open(config_path, "r") as file:
            config = yaml.safe_load(file)

        row = 0
        for server in config["servers"]:
            emoji = server["emoji"]
            code = server["code"]
            name = server["name"].lower()
            button = self.create_button(emoji, code, name)
            self.server_codes[name] = code
            grid1.attach(button, row % 3, row // 3 + 2, 1, 1)  # Adjusted the row index
            row += 1

        button_ex = self.create_button("⏼", "disconnect", "disconnect")
        grid1.attach(button_ex, row % 3, row // 3 + 2, 1, 1)  # Adjusted the row index

        button_q = Gtk.Button(label="Quit")
        button_q.connect("clicked", Gtk.main_quit)
        button_q.set_tooltip_text("Quit")
        grid1.attach(
            button_q, (row + 1) % 3, (row + 1) // 3 + 2, 1, 1
        )  # Adjusted the row index

        frame1.add(grid1)
        self.add(frame1)
        self.show_all()

        # Update button colors initially
        self.update_button_colors()

    def get_vpn_status(self):
        try:
            nord = sub.check_output(["nordvpn", "status"]).decode()
            if "Connected" in nord:
                for line in nord.splitlines():
                    if line.startswith("Country:"):
                        country = line.split(":")[1].strip().lower()
                        return country
            return "disconnected"
        except sub.CalledProcessError:
            return "disconnected"

    def create_button(self, label, code, name):
        button = Gtk.Button(label=label)
        button.set_hexpand(True)
        button.connect("clicked", self.on_button_clicked, code)
        button.set_tooltip_text(name.capitalize())
        self.buttons[name] = button
        return button

    def on_button_clicked(self, widget, code):
        if code != "disconnect":
            sub.Popen(["nordvpn", "connect", code])
        else:
            sub.Popen(["nordvpn", "disconnect"])
        sleep(1.5)
        self.current_status = self.get_vpn_status()
        self.label3.set_text(
            self.current_status.capitalize()
            if self.current_status != "disconnected"
            else "Disconnected"
        )
        self.update_button_colors()

    def update_button_colors(self):
        current_status = self.get_vpn_status()
        for name, button in self.buttons.items():
            if name == "disconnect":
                continue
            if current_status == name:
                button.get_style_context().remove_class("disconnected")
                button.get_style_context().add_class("connected")
            else:
                button.get_style_context().remove_class("connected")
                button.get_style_context().add_class("disconnected")

        css = b"""
        button.connected {
            background: green;
        }
        button.disconnected {
            background: red;
        }
        """
        css_provider = Gtk.CssProvider()
        css_provider.load_from_data(css)
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(), css_provider, Gtk.STYLE_PROVIDER_PRIORITY_USER
        )


if __name__ == "__main__":
    win1 = NordWindow()
    win1.connect("destroy", Gtk.main_quit)
    Gtk.main()
