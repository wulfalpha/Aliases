#!/usr/bin/env python3
import gi
import subprocess as s
import os

gi.require_version("Gtk", "3.0")
import threading
from gi.repository import GLib, Gtk


class PepUpWindow(Gtk.Window):
    """Window update class."""

    def __init__(self):
        super().__init__(title="Peppermint Update (GTK)")

        self.set_border_width(10)
        self.set_default_size(640, 200)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.set_resizable(True)
        self.update_process = None
        self.upgrade_process = None
        self.cancelled = False

        frame1 = Gtk.Frame(label="Peppermint Update")

        grid1 = Gtk.Grid(row_spacing=10, column_spacing=10, column_homogeneous=True)

        self.label1 = Gtk.Label(label="Updates: Ready...")
        self.label1.set_hexpand(True)

        self.progress_label = Gtk.Label(label="")
        self.progress_label.set_hexpand(True)

        self.spinner = Gtk.Spinner()
        self.spinner.set_hexpand(True)
        self.spinner.set_vexpand(True)

        self.button_updates = Gtk.Button(label="Check for updates")
        self.button_updates.set_hexpand(True)
        self.button_updates.connect("clicked", self.on_button_updates_clicked)
        self.button_updates.set_tooltip_text("Check for system updates")

        self.button_upgrade = Gtk.Button(label="Install Updates")
        self.button_upgrade.set_hexpand(True)
        self.button_upgrade.set_sensitive(False)
        self.button_upgrade.connect("clicked", self.on_button_upgrade_clicked)
        self.button_upgrade.set_tooltip_text("Install available updates")

        self.button_cancel = Gtk.Button(label="Cancel")
        self.button_cancel.set_hexpand(True)
        self.button_cancel.set_sensitive(False)
        self.button_cancel.connect("clicked", self.on_button_cancel_clicked)
        self.button_cancel.set_tooltip_text("Cancel current operation")

        button_q = Gtk.Button(label="Quit")
        button_q.set_hexpand(True)
        button_q.connect("clicked", Gtk.main_quit)
        button_q.set_tooltip_text("Quit")

        grid1.attach(self.label1, 0, 2, 4, 1)
        grid1.attach(self.progress_label, 0, 3, 4, 1)
        grid1.attach(self.spinner, 0, 4, 4, 2)
        grid1.attach(self.button_updates, 0, 8, 1, 1)
        grid1.attach(self.button_upgrade, 1, 8, 1, 1)
        grid1.attach(self.button_cancel, 2, 8, 1, 1)
        grid1.attach(button_q, 3, 8, 1, 1)

        self.add(frame1)
        frame1.add(grid1)

        # Check for nala at startup
        self.has_nala = self.check_nala_installed()

    def check_nala_installed(self):
        """Check if nala is installed"""
        result = s.run(["which", "nala"], stdout=s.PIPE, stderr=s.PIPE)
        return result.returncode == 0

    def check_apt_locks(self):
        """Check if apt is locked by another process"""
        dpkg_lock = "/var/lib/dpkg/lock-frontend"
        apt_lock = "/var/lib/apt/lists/lock"

        for lock_file in [dpkg_lock, apt_lock]:
            if os.path.exists(lock_file):
                lock_check = s.run(["lsof", lock_file], stdout=s.PIPE, stderr=s.PIPE)
                if lock_check.returncode == 0:
                    return True  # Locked
        return False  # Not locked

    def set_buttons_sensitive(
        self, updates_sensitive, upgrade_sensitive, cancel_sensitive
    ):
        """Enable or disable buttons based on current state"""
        GLib.idle_add(self.button_updates.set_sensitive, updates_sensitive)
        GLib.idle_add(self.button_upgrade.set_sensitive, upgrade_sensitive)
        GLib.idle_add(self.button_cancel.set_sensitive, cancel_sensitive)

    def update_progress_text(self, text):
        """Update the progress text in the UI"""
        self.progress_label.set_text(text)

    def on_button_cancel_clicked(self, widget):
        """Button to cancel ongoing operations"""
        self.cancelled = True
        if self.update_process and self.update_process.poll() is None:
            try:
                self.update_process.terminate()
            except:
                pass
        if self.upgrade_process and self.upgrade_process.poll() is None:
            try:
                self.upgrade_process.terminate()
            except:
                pass

        GLib.idle_add(self.show_error, "Operation cancelled by user")

    def on_button_updates_clicked(self, widget):
        """Button to check for updates"""
        if self.check_apt_locks():
            self.show_error(
                "Another package manager is running. Please wait and try again."
            )
            return

        self.cancelled = False
        self.spinner.start()
        self.label1.set_text("Updates: Checking...")
        self.update_progress_text("")
        self.set_buttons_sensitive(False, False, True)
        threading.Thread(target=self.run_update_check).start()

    def run_update_check(self):
        try:
            # Use nala if available, otherwise fall back to apt-get
            if self.has_nala:
                update_cmd = ["pkexec", "nala", "update", "-y"]
                GLib.idle_add(
                    self.update_progress_text, "Using Nala for better performance..."
                )
            else:
                update_cmd = ["pkexec", "apt-get", "-q", "update"]
                GLib.idle_add(self.update_progress_text, "Using APT for updates...")

            self.update_process = s.Popen(
                update_cmd, stdout=s.PIPE, stderr=s.STDOUT, universal_newlines=True
            )

            for line in self.update_process.stdout:
                if self.cancelled:
                    return
                GLib.idle_add(self.update_progress_text, line.strip())

            return_code = self.update_process.wait(timeout=300)

            if self.cancelled:
                return

            if return_code != 0:
                GLib.idle_add(self.show_error, "Unable to check for updates")
                return

            # Count available updates
            if self.has_nala:
                updates_cmd = ["nala", "list", "--upgradable"]
                grep_cmd = ["grep", "^Listing"]
            else:
                updates_cmd = [
                    "apt-get",
                    "-q",
                    "-y",
                    "--ignore-hold",
                    "--allow-change-held-packages",
                    "--allow-unauthenticated",
                    "-s",
                    "dist-upgrade",
                ]
                grep_cmd = ["grep", "^Inst"]

            # First get the upgrade list
            process = s.Popen(updates_cmd, stdout=s.PIPE, stderr=s.PIPE)
            if self.has_nala:
                output, _ = process.communicate()
                # Nala output format is different, parse it separately
                try:
                    # Try to extract the number from "Listing N upgradable packages"
                    output_str = output.decode("utf-8")
                    for line in output_str.splitlines():
                        if "upgradable package" in line:
                            parts = line.split()
                            for part in parts:
                                if part.isdigit():
                                    updates = int(part)
                                    break
                            else:
                                updates = 0
                            break
                    else:
                        updates = 0
                except:
                    updates = 0
            else:
                # For apt-get, pipe through grep and count lines
                process2 = s.Popen(grep_cmd, stdin=process.stdout, stdout=s.PIPE)
                process.stdout.close()
                output, _ = process2.communicate()
                updates = len(output.decode("utf-8").splitlines())

            GLib.idle_add(self.update_results, updates)

        except s.TimeoutExpired:
            GLib.idle_add(self.show_error, "Update check timed out")
        except Exception as e:
            GLib.idle_add(self.show_error, f"Unexpected error: {str(e)}")
        finally:
            self.update_process = None

    def show_error(self, message):
        self.label1.set_text(f"Error: {message}")
        self.spinner.stop()
        self.set_buttons_sensitive(True, False, False)
        self.update_progress_text("")

    def update_results(self, updates):
        if updates == 0:
            self.label1.set_text("Updates: Your system is up-to-date.")
            self.set_buttons_sensitive(True, False, False)
        elif updates == 1:
            self.label1.set_text("Updates: There is one update available.")
            self.set_buttons_sensitive(True, True, False)
        else:
            self.label1.set_text(f"Updates: There are {updates} updates available.")
            self.set_buttons_sensitive(True, True, False)
        self.spinner.stop()
        self.update_progress_text("")

    def on_button_upgrade_clicked(self, widget):
        """Button for upgrade. Unlocked only when updates are available."""
        if self.check_apt_locks():
            self.show_error(
                "Another package manager is running. Please wait and try again."
            )
            return

        self.cancelled = False
        self.spinner.start()
        self.label1.set_text("Updates: Installing...")
        self.update_progress_text("")
        self.set_buttons_sensitive(False, False, True)
        threading.Thread(target=self.run_upgrade).start()

    def run_upgrade(self):
        try:
            # Use nala if available for better UI and performance
            if self.has_nala:
                upgrade_cmd = ["pkexec", "nala", "upgrade", "-y"]
                GLib.idle_add(
                    self.update_progress_text, "Using Nala for better performance..."
                )
            else:
                upgrade_cmd = ["pkexec", "apt-get", "upgrade", "-y"]
                GLib.idle_add(self.update_progress_text, "Using APT for updates...")

            self.upgrade_process = s.Popen(
                upgrade_cmd, stdout=s.PIPE, stderr=s.STDOUT, universal_newlines=True
            )

            for line in self.upgrade_process.stdout:
                if self.cancelled:
                    return
                GLib.idle_add(self.update_progress_text, line.strip())

            return_code = self.upgrade_process.wait(timeout=1800)  # 30 minute timeout

            if self.cancelled:
                return

            if return_code != 0:
                GLib.idle_add(self.show_error, "Unable to perform upgrade")
                return

            GLib.idle_add(self.update_after_upgrade)

        except s.TimeoutExpired:
            GLib.idle_add(self.show_error, "Upgrade process timed out")
        except Exception as e:
            GLib.idle_add(self.show_error, f"Unexpected error during upgrade: {str(e)}")
        finally:
            self.upgrade_process = None

    def update_after_upgrade(self):
        self.label1.set_text("Updates: Update Complete!")
        self.spinner.stop()
        self.set_buttons_sensitive(True, False, False)
        self.update_progress_text("")
        # Run another update check to verify we're up to date
        threading.Thread(target=self.run_update_check).start()


win1 = PepUpWindow()
win1.connect("destroy", Gtk.main_quit)
win1.show_all()
Gtk.main()
