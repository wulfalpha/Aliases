#!/usr/bin/env python3
import gi
import subprocess as s
import os
import logging

gi.require_version("Gtk", "3.0")
import threading
from gi.repository import GLib, Gtk


class ChimeraWindow(Gtk.Window):
    """Window update class."""

    def __init__(self, package_manager):
        super().__init__(title="Chimera Updater (GTK)")
        self.set_border_width(10)
        self.set_default_size(640, 200)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.set_resizable(True)
        self.package_manager = package_manager
        frame1 = Gtk.Frame(label="Chimera Update")
        grid1 = Gtk.Grid(row_spacing=10, column_spacing=10, column_homogeneous=True)
        self.label1 = Gtk.Label(label="Updates: Ready...")
        self.label1.set_hexpand(True)
        self.spinner = Gtk.Spinner()
        self.spinner.set_hexpand(True)
        self.spinner.set_vexpand(True)

        button_updates = self.__create_button(
            "Check for updates", "Checker", self.on_button_updates_clicked, True
        )
        self.button_upgrade = self.__create_button(
            "Install Updates", "Installer", self.on_button_upgrade_clicked, False
        )
        button_q = self.__create_button("Quit", "Quit", Gtk.main_quit, True)
        grid1.attach(self.label1, 0, 2, 3, 2)
        grid1.attach(self.spinner, 0, 4, 3, 2)
        grid1.attach(button_updates, 0, 8, 1, 1)
        grid1.attach(self.button_upgrade, 1, 8, 1, 1)
        grid1.attach(button_q, 2, 8, 1, 1)
        frame1.add(grid1)
        self.add(frame1)  # don't forget to add the frame to the window

    def __create_button(self, label, tooltip_text, event_handler, is_sensitive):
        button = Gtk.Button(label=label)
        button.set_hexpand(True)
        button.set_sensitive(is_sensitive)
        button.set_tooltip_text(tooltip_text)
        button.connect("clicked", event_handler)
        return button

    def update_results(self, updates):
        # Gui Results
        if updates == 0:
            update_msg = "Your system is up-to-date."
        elif updates == 1:
            update_msg = "There is one update available."
        else:
            update_msg = f"There are {updates} updates available."
        self.label1.set_text(f"Updates: {update_msg}")
        self.button_upgrade.set_sensitive(updates > 0)
        self.spinner.stop()

    def set_update_label(self, msg):
        # Update lable
        self.label1.set_text(f"Updates: {msg}")

    def on_button_updates_clicked(self, widget):
        """Button to check for updates"""
        GLib.idle_add(self.spinner.start)
        GLib.idle_add(self.label1.set_text, "Updates: Checking...")
        threading.Thread(target=self.run_update_check).start()

    def run_update_check(self):
        # Check for updates
        update_process = self.package_manager.check_updates()
        if update_process.returncode != 0:
            GLib.idle_add(self.show_error, "Unable to check for updates")
            return

        updates = update_process.stdout.decode("utf-8").strip()
        try:
            updates = int(updates)
        except ValueError:
            GLib.idle_add(self.show_error, "Unable to parse update count")
            return

        GLib.idle_add(self.update_results, updates)

    def show_error(self, message):
        # Display errors in gui
        self.label1.set_text(f"Error: {message}")
        self.spinner.stop()

    def on_button_upgrade_clicked(self, widget):
        """Button for upgrade. Unlocked only when updates are available."""
        GLib.idle_add(self.spinner.start)
        GLib.idle_add(self.label1.set_text, "Updates: Checking...")
        threading.Thread(target=self.run_upgrade).start()

    def run_upgrade(self):
        # Call to run upgrade
        upgrade_process = self.package_manager.upgrade()
        if upgrade_process.returncode != 0:
            GLib.idle_add(self.show_error, "Unable to perform upgrade")
            return
        GLib.idle_add(self.update_after_upgrade)

    def update_after_upgrade(self):
        # Housekeeping
        self.label1.set_text("Updates: Update Complete!")
        self.spinner.stop()


class PackageManager:
    # Package manager Super Class
    def __init__(self):
        self.check_updates_cmd = ""
        self.count_updates_cmd = ""
        self.upgrade_cmd = ""

    def check_updates(self):
        # Initial Updates check
        return self.run_command(self.check_updates_cmd)

    def count_updates(self):
        # Display available updates
        return self.run_command(self.count_updates_cmd)

    def upgrade(self):
        # Start the package manager
        return self.run_command(self.upgrade_cmd)

    def run_command(self, cmd):
        # Run the command
        try:
            return s.run(cmd, shell=True, capture_output=True, text=True)
        except Exception as e:
            logging.error(str(e))
            raise Exception(f"Failed to run command: {cmd}.")


class AptManager(PackageManager):
    # Debian Based support
    def __init__(self):
        super().__init__()
        self.check_updates_cmd = "apt-get -q update"
        self.count_updates_cmd = "apt-get -q -y --ignore-hold --allow-change-held-packages \
                                  --allow-unauthenticated -s dist-upgrade | grep ^Inst | wc -l"
        self.upgrade_cmd = "apt upgrade -y"


class NalaManager(AptManager):
    # Support for Nala
    def __init__(self):
        super().__init__()
        self.upgrade_cmd = "nala upgrade -y"


class DnfManager(PackageManager):
    # Fedora/rpm updates
    def __init__(self):
        super().__init__()
        self.count_updates_cmd = "dnf check-update | grep -v '^$' | wc -l"
        self.check_updates_cmd = "dnf check-update"
        self.upgrade_cmd = "dnf upgrade"


class PacmanManager(PackageManager):
    # Arch Based update
    def __init__(self):
        super().__init__()
        self.count_updates_cmd = "pacman -Qu | wc -l"
        self.check_updates_cmd = "pacman -Qu"
        self.upgrade_cmd = "pacman -Syu"


class DistroCheck:
    # Check for proper package manager for supporte Distros
    def __init__(self):
        self.distro_id = self.get_distro_id()
        self.package_managers = {
            "debian": [("nala", NalaManager), ("apt", AptManager)],
            "ubuntu": [("nala", NalaManager), ("apt", AptManager)],
            "fedora": [("dnf", DnfManager)],
            # 'centos': [('yum', YumManager)],
            "arch": [("pacman", PacmanManager)],
            "arcolinux": [("pacman", PacmanManager)],
        }

    def get_distro_id(self):
        # Look at OS release to check for supported distro
        filename = "/etc/os-release"
        logging.info(f"Reading distro ID from {filename}")
        try:
            with open(filename, "r") as f:
                lines = f.readlines()
            for line in lines:
                if line.startswith("ID="):
                    return line[3:].strip()
            raise Exception("Could not determine distro from /etc/os-release")
        except Exception as e:
            logging.error(f"Failed to read distro ID from {filename}. Error: {str(e)}")
            raise

    def get_package_manager_for_distro(self):
        # Pick the Package manager
        options = self.package_managers.get(self.distro_id)
        if options is None:
            raise Exception(
                f"No supported package manager found for distro: {self.distro_id}"
            )
        # Iterate over the options and return the first available package manager
        for pkg_name, pkg_manager_class in options:
            if self.is_tool_available(pkg_name):
                return pkg_manager_class()
        raise Exception(
            f"No supported package manager available for distro: {self.distro_id}"
        )

    def is_tool_available(self, name):
        # Check if `name` is on PATH and marked as executable.
        return s.call(["which", name], stdout=s.DEVNULL, stderr=s.DEVNULL) == 0


class ErrorDialog(Gtk.Dialog):
    # Error dialog settings
    def __init__(self, parent, message):
        Gtk.Dialog.__init__(self, title="Error", transient_for=parent, flags=0)
        self.add_buttons(
            Gtk.STOCK_OK,
            Gtk.ResponseType.OK,
        )

        label = Gtk.Label(label=message)

        box = self.get_content_area()
        box.add(label)
        self.show_all()


try:
    distro_check = DistroCheck()
    package_manager = distro_check.get_package_manager_for_distro()
except Exception as e:
    error_dialog = ErrorDialog(None, str(e))
    response = error_dialog.run()

    if response == Gtk.ResponseType.OK:
        error_dialog.destroy()

    Gtk.main_quit()
else:
    win1 = ChimeraWindow(package_manager)
    win1.connect("destroy", Gtk.main_quit)
    win1.show_all()

Gtk.main()
