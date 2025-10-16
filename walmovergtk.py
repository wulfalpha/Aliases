#!/usr/bin/env python3

import shutil
from pathlib import Path
from threading import Thread

import gi
from PIL import Image, ImageDraw, ImageFont

gi.require_version("Gtk", "3.0")
from gi.repository import GdkPixbuf, GLib, Gtk


# Worker thread class for handling background processing
class Worker(Thread):
    def __init__(self, window, src_dir, dest_dir, ratio=(16, 9), overwrite=False):
        super().__init__()
        self.window = window
        self.src_dir = src_dir
        self.dest_dir = dest_dir
        self.ratio = ratio
        self.overwrite = overwrite
        self.cancelled = False
        self.daemon = True  # Allow app to exit even if thread is running

        # Statistics
        self.stats = {
            "total": 0,
            "copied": 0,
            "skipped": 0,
            "failed": 0,
            "overwritten": 0,
        }

    def run(self):
        try:
            image_files = [f for f in self.src_dir.iterdir() if is_valid_image(f)]
            total_files = len(image_files)
            self.stats["total"] = total_files

            if total_files == 0:
                GLib.idle_add(
                    self.window.update_progress_bar, "No valid image files found", 1.0
                )
                GLib.idle_add(self.window.on_processing_finished, self.stats)
                return

            for idx, file_path in enumerate(image_files):
                # Check for cancellation
                if self.cancelled:
                    GLib.idle_add(self.window.on_processing_cancelled, self.stats)
                    return

                try:
                    # Open image, get dimensions, then close before copying
                    img = Image.open(file_path)
                    width, height = img.size
                    img.close()
                except Exception as e:
                    print(f"Error opening {file_path}: {e}")
                    self.stats["failed"] += 1
                    continue

                if has_aspect_ratio(width, height, self.ratio):
                    dest_path = self.dest_dir / file_path.name
                    exists = dest_path.exists()

                    should_copy = not exists or self.overwrite

                    if should_copy:
                        try:
                            shutil.copy(file_path, dest_path)
                            if exists:
                                self.stats["overwritten"] += 1
                            else:
                                self.stats["copied"] += 1
                        except Exception as e:
                            print(f"Error copying {file_path} to {dest_path}: {e}")
                            self.stats["failed"] += 1
                            GLib.idle_add(
                                self.window.show_error_dialog,
                                f"Failed to copy {file_path.name}: {e}",
                            )
                            continue
                    else:
                        self.stats["skipped"] += 1

                    # Use GLib.idle_add to update UI safely
                    GLib.idle_add(
                        self.window.on_image_added,
                        dest_path,
                        exists and not self.overwrite,
                    )

                fraction = (idx + 1) / total_files
                stats_text = f"Copied: {self.stats['copied']} | Overwritten: {self.stats['overwritten']} | Skipped: {self.stats['skipped']} | Failed: {self.stats['failed']}"
                GLib.idle_add(
                    self.window.update_progress_bar,
                    f"Processing {file_path.name} - {stats_text}",
                    fraction,
                )

            GLib.idle_add(self.window.on_processing_finished, self.stats)
        except Exception as e:
            print(f"Worker error: {e}")
            GLib.idle_add(self.window.on_processing_error, str(e))


class Walmover(Gtk.Window):
    def __init__(self):
        super().__init__(title="Walmover GTK")
        self.set_border_width(10)
        self.set_default_size(800, 600)

        self.src_dir = None
        self.dest_dir = None
        self.worker = None

        # Set up the main layout
        self.vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        self.add(self.vbox)

        # Create image list view
        self.image_list_store = Gtk.ListStore(GdkPixbuf.Pixbuf, str)
        self.icon_view = Gtk.IconView.new()
        self.icon_view.set_model(self.image_list_store)
        self.icon_view.set_pixbuf_column(0)
        self.icon_view.set_text_column(1)
        self.icon_view.set_item_width(150)

        # Make the icon view scrollable
        scrollable_treelist = Gtk.ScrolledWindow()
        scrollable_treelist.set_vexpand(True)
        scrollable_treelist.add(self.icon_view)
        self.vbox.pack_start(scrollable_treelist, True, True, 0)

        # Add progress bar
        self.progress_bar = Gtk.ProgressBar()
        self.progress_bar.set_show_text(True)
        self.vbox.pack_start(self.progress_bar, False, False, 0)

        # Add aspect ratio selection with combo box
        self.ratio_frame = Gtk.Frame(label="Aspect Ratio")
        self.ratio_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        self.ratio_frame.add(self.ratio_box)

        # Create combo box with entry (allows typing)
        self.ratio_combo = Gtk.ComboBoxText.new_with_entry()
        self.ratio_combo.append_text("Desktop (16:9)")
        self.ratio_combo.append_text("Ultrawide (21:9)")
        self.ratio_combo.append_text("Standard (16:10)")
        self.ratio_combo.append_text("Mobile (9:16)")
        self.ratio_combo.set_active(0)  # Default to Desktop

        self.ratio_box.pack_start(self.ratio_combo, True, True, 0)
        self.vbox.pack_start(self.ratio_frame, False, False, 0)

        # Add overwrite checkbox
        self.overwrite_checkbox = Gtk.CheckButton(label="Overwrite existing files")
        self.overwrite_checkbox.set_active(False)
        self.vbox.pack_start(self.overwrite_checkbox, False, False, 0)

        # Add status label for statistics
        self.status_label = Gtk.Label(label="Ready")
        self.status_label.set_xalign(0)  # Left align
        self.vbox.pack_start(self.status_label, False, False, 0)

        # Create buttons
        self.button_box = Gtk.Box(spacing=6, orientation=Gtk.Orientation.HORIZONTAL)
        self.button_box.set_homogeneous(True)
        self.vbox.pack_start(self.button_box, False, False, 0)

        self.src_button = Gtk.Button(label="Select Source")
        self.src_button.connect("clicked", self.on_src_button_clicked)
        self.button_box.pack_start(self.src_button, True, True, 0)

        self.dest_button = Gtk.Button(label="Select Destination")
        self.dest_button.connect("clicked", self.on_dest_button_clicked)
        self.button_box.pack_start(self.dest_button, True, True, 0)

        self.start_button = Gtk.Button(label="Start")
        self.start_button.set_sensitive(
            False
        )  # Disabled until directories are selected
        self.start_button.connect("clicked", self.on_start_button_clicked)
        self.button_box.pack_start(self.start_button, True, True, 0)

        self.cancel_button = Gtk.Button(label="Cancel")
        self.cancel_button.set_sensitive(False)  # Disabled until processing starts
        self.cancel_button.connect("clicked", self.on_cancel_button_clicked)
        self.button_box.pack_start(self.cancel_button, True, True, 0)

        self.done_button = Gtk.Button(label="Quit")
        self.done_button.connect("clicked", self.on_done_button_clicked)
        self.button_box.pack_start(self.done_button, True, True, 0)

    def get_current_ratio(self):
        """Return the aspect ratio tuple based on the combo box selection."""
        text = self.ratio_combo.get_active_text()
        if not text:
            return (16, 9)  # Default

        # Normalize the text (lowercase, remove spaces)
        text_lower = text.lower().replace(" ", "")

        # Check for keywords or full text
        if "16:9" in text or "desktop" in text_lower:
            return (16, 9)
        elif "21:9" in text or "ultrawide" in text_lower:
            return (21, 9)
        elif "16:10" in text or "standard" in text_lower:
            return (16, 10)
        elif "9:16" in text or "mobile" in text_lower:
            return (9, 16)
        else:
            # Default to 16:9 if unrecognized
            return (16, 9)

    def on_done_button_clicked(self, widget):
        Gtk.main_quit()

    def on_cancel_button_clicked(self, widget):
        """Cancel the current processing operation"""
        if self.worker and self.worker.is_alive():
            self.worker.cancelled = True
            self.cancel_button.set_sensitive(False)
            self.status_label.set_text("Cancelling...")

    def on_src_button_clicked(self, widget):
        dialog = Gtk.FileChooserDialog(
            title="Select Source Directory",
            parent=self,
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
            parent=self,
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

        # Prevent multiple concurrent workers
        if self.worker and self.worker.is_alive():
            return

        if not self.dest_dir.is_dir():
            try:
                self.dest_dir.mkdir(parents=True, exist_ok=True)
            except Exception as e:
                self.show_error_dialog(f"Error creating destination: {e}")
                return

        # Clear the image list
        self.image_list_store.clear()

        # Disable buttons during processing
        self.start_button.set_sensitive(False)
        self.src_button.set_sensitive(False)
        self.dest_button.set_sensitive(False)
        self.done_button.set_sensitive(False)
        self.ratio_combo.set_sensitive(False)
        self.overwrite_checkbox.set_sensitive(False)

        # Enable cancel button
        self.cancel_button.set_sensitive(True)

        # Reset progress bar and status
        self.progress_bar.set_fraction(0.0)
        self.progress_bar.set_text("Starting...")
        self.status_label.set_text("Processing...")

        # Create and start the worker thread
        ratio = self.get_current_ratio()
        overwrite = self.overwrite_checkbox.get_active()
        self.worker = Worker(self, self.src_dir, self.dest_dir, ratio, overwrite)
        self.worker.start()

    def on_image_added(self, image_path, exists=False):
        """Safely handle new image added from worker thread"""
        try:
            if exists:
                # Create pixbuf with exclamation mark overlay for duplicates
                pixbuf = self.create_duplicate_thumbnail(str(image_path))
            else:
                pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(
                    str(image_path), 128, 128, True
                )
            self.image_list_store.append([pixbuf, image_path.name])
        except Exception as e:
            print(f"Error adding image: {e}")
        return False  # Important for GLib.idle_add

    def create_duplicate_thumbnail(self, image_path):
        """Create a thumbnail with an exclamation mark overlay for duplicates"""
        try:
            # Load and resize the image using PIL
            pil_img = Image.open(image_path)
            pil_img.thumbnail((128, 128), Image.Resampling.LANCZOS)

            # Convert to RGBA to support transparency
            if pil_img.mode != "RGBA":
                pil_img = pil_img.convert("RGBA")

            # Create overlay layer
            overlay = Image.new("RGBA", pil_img.size, (0, 0, 0, 0))
            draw = ImageDraw.Draw(overlay)

            # Draw semi-transparent circle background
            circle_size = 40
            circle_x = pil_img.width - circle_size - 5
            circle_y = 5
            draw.ellipse(
                [circle_x, circle_y, circle_x + circle_size, circle_y + circle_size],
                fill=(255, 200, 0, 220),  # Orange with transparency
            )

            # Draw exclamation mark
            try:
                # Try to use a larger font
                font = ImageFont.truetype(
                    "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf", 28
                )
            except:
                try:
                    font = ImageFont.truetype(
                        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 28
                    )
                except:
                    font = ImageFont.load_default()

            # Draw exclamation mark centered in circle
            text = "!"
            bbox = draw.textbbox((0, 0), text, font=font)
            text_width = bbox[2] - bbox[0]
            text_height = bbox[3] - bbox[1]
            text_x = circle_x + (circle_size - text_width) // 2
            text_y = circle_y + (circle_size - text_height) // 2 - 2

            draw.text((text_x, text_y), text, fill=(0, 0, 0, 255), font=font)

            # Composite the overlay onto the image
            pil_img = Image.alpha_composite(pil_img, overlay)

            # Convert PIL image to GdkPixbuf
            # Save to bytes and load back
            import io

            buffer = io.BytesIO()
            pil_img.save(buffer, format="PNG")
            buffer.seek(0)

            loader = GdkPixbuf.PixbufLoader.new_with_type("png")
            loader.write(buffer.read())
            loader.close()
            pixbuf = loader.get_pixbuf()

            pil_img.close()
            return pixbuf

        except Exception as e:
            print(f"Error creating duplicate thumbnail: {e}")
            # Fallback to regular thumbnail
            return GdkPixbuf.Pixbuf.new_from_file_at_scale(image_path, 128, 128, True)

    def update_progress_bar(self, message, fraction=None):
        """Update the progress bar text and optionally its fraction"""
        if fraction is not None:
            self.progress_bar.set_fraction(fraction)
        self.progress_bar.set_text(message)
        return False  # Important for GLib.idle_add

    def on_processing_finished(self, stats):
        """Called when processing is complete"""
        self.progress_bar.set_fraction(1.0)
        self.progress_bar.set_text("Processing complete")

        # Update status label with final statistics
        status_text = (
            f"Complete - Total: {stats['total']} | Copied: {stats['copied']} | "
            f"Overwritten: {stats['overwritten']} | Skipped: {stats['skipped']} | "
            f"Failed: {stats['failed']}"
        )
        self.status_label.set_text(status_text)

        # Re-enable buttons
        self.start_button.set_sensitive(True)
        self.src_button.set_sensitive(True)
        self.dest_button.set_sensitive(True)
        self.done_button.set_sensitive(True)
        self.ratio_combo.set_sensitive(True)
        self.overwrite_checkbox.set_sensitive(True)
        self.cancel_button.set_sensitive(False)
        return False  # Important for GLib.idle_add

    def on_processing_cancelled(self, stats):
        """Called when processing is cancelled"""
        self.progress_bar.set_text("Cancelled")

        # Update status label with statistics up to cancellation
        status_text = (
            f"Cancelled - Processed: {stats['copied'] + stats['overwritten'] + stats['skipped']} of {stats['total']} | "
            f"Copied: {stats['copied']} | Overwritten: {stats['overwritten']} | "
            f"Skipped: {stats['skipped']} | Failed: {stats['failed']}"
        )
        self.status_label.set_text(status_text)

        # Re-enable buttons
        self.start_button.set_sensitive(True)
        self.src_button.set_sensitive(True)
        self.dest_button.set_sensitive(True)
        self.done_button.set_sensitive(True)
        self.ratio_combo.set_sensitive(True)
        self.overwrite_checkbox.set_sensitive(True)
        self.cancel_button.set_sensitive(False)
        return False  # Important for GLib.idle_add

    def on_processing_error(self, error_message):
        """Handle errors from worker thread"""
        self.progress_bar.set_text(f"Error: {error_message}")
        self.status_label.set_text(f"Error: {error_message}")
        self.show_error_dialog(error_message)

        # Re-enable buttons
        self.start_button.set_sensitive(True)
        self.src_button.set_sensitive(True)
        self.dest_button.set_sensitive(True)
        self.done_button.set_sensitive(True)
        self.ratio_combo.set_sensitive(True)
        self.overwrite_checkbox.set_sensitive(True)
        self.cancel_button.set_sensitive(False)
        return False  # Important for GLib.idle_add

    def show_error_dialog(self, message):
        """Display an error dialog to the user"""
        dialog = Gtk.MessageDialog(
            transient_for=self,
            flags=0,
            message_type=Gtk.MessageType.ERROR,
            buttons=Gtk.ButtonsType.OK,
            text="Error",
        )
        dialog.format_secondary_text(message)
        dialog.run()
        dialog.destroy()
        return False  # Important for GLib.idle_add


def is_valid_image(file_path):
    """Check if a file is a valid image type"""
    valid_extensions = [
        ".png",
        ".jpg",
        ".jpeg",
        ".webp",
        ".bmp",
        ".gif",
        ".tiff",
        ".tif",
    ]
    return file_path.is_file() and file_path.suffix.lower() in valid_extensions


def has_aspect_ratio(width, height, ratio=(16, 9), tolerance=0.05):
    """Check if an image has the specified aspect ratio within tolerance"""
    calculated_ratio = width / height
    expected_ratio = ratio[0] / ratio[1]
    return (
        (1 - tolerance) * expected_ratio
        <= calculated_ratio
        <= (1 + tolerance) * expected_ratio
    )


if __name__ == "__main__":
    app = Walmover()
    app.connect("destroy", Gtk.main_quit)
    app.show_all()
    Gtk.main()
