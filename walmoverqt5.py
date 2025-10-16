#!/usr/bin/env python3

import sys
import shutil
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import io

from PyQt5.QtWidgets import (
    QApplication,
    QMainWindow,
    QVBoxLayout,
    QHBoxLayout,
    QPushButton,
    QListView,
    QStatusBar,
    QProgressBar,
    QWidget,
    QAbstractItemView,
    QFileDialog,
    QGroupBox,
    QComboBox,
    QCheckBox,
    QLabel,
    QMessageBox,
)
from PyQt5.QtGui import QPixmap, QStandardItemModel, QStandardItem, QIcon
from PyQt5.QtCore import Qt, QThread, pyqtSignal, QByteArray, QBuffer, QIODevice

# --- Constants ---
VALID_EXTENSIONS = {".png", ".jpg", ".jpeg", ".webp", ".bmp", ".gif", ".tiff", ".tif"}
ICON_SIZE = 128
TOLERANCE = 0.05  # 5% tolerance for aspect ratio check


# --- Utility Functions ---
def is_valid_image(file_path):
    return file_path.is_file() and file_path.suffix.lower() in VALID_EXTENSIONS


def has_aspect_ratio(width, height, ratio):
    calculated_ratio = width / height
    expected_ratio = ratio[0] / ratio[1]
    return (
        (1 - TOLERANCE) * expected_ratio
        <= calculated_ratio
        <= (1 + TOLERANCE) * expected_ratio
    )


# --- Worker Thread ---
class Worker(QThread):
    finished = pyqtSignal(dict)
    cancelled = pyqtSignal(dict)
    progress = pyqtSignal(str, float, dict)  # message, fraction, stats
    image_added = pyqtSignal(Path, bool)
    error = pyqtSignal(str)

    def __init__(self, src_dir, dest_dir, ratio, overwrite=False, parent=None):
        super().__init__(parent)
        self.src_dir = src_dir
        self.dest_dir = dest_dir
        self.ratio = ratio
        self.overwrite = overwrite
        self._cancelled = False

        # Statistics
        self.stats = {
            "total": 0,
            "copied": 0,
            "skipped": 0,
            "failed": 0,
            "overwritten": 0,
        }

    def cancel(self):
        self._cancelled = True

    def run(self):
        try:
            image_files = [f for f in self.src_dir.iterdir() if is_valid_image(f)]
            total_files = len(image_files)
            self.stats["total"] = total_files

            if total_files == 0:
                self.progress.emit("No valid image files found", 1.0, self.stats)
                self.finished.emit(self.stats)
                return

            for idx, file_path in enumerate(image_files):
                # Check for cancellation
                if self._cancelled:
                    self.cancelled.emit(self.stats)
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

                if has_aspect_ratio(width, height, ratio=self.ratio):
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
                            self.image_added.emit(
                                dest_path, exists and not self.overwrite
                            )
                        except Exception as e:
                            print(f"Error copying {file_path} to {dest_path}: {e}")
                            self.stats["failed"] += 1
                            self.error.emit(f"Failed to copy {file_path.name}: {e}")
                            continue
                    else:
                        self.stats["skipped"] += 1
                        self.image_added.emit(dest_path, True)

                fraction = (idx + 1) / total_files
                stats_text = f"Copied: {self.stats['copied']} | Overwritten: {self.stats['overwritten']} | Skipped: {self.stats['skipped']} | Failed: {self.stats['failed']}"
                self.progress.emit(
                    f"Processing {file_path.name} - {stats_text}",
                    fraction,
                    self.stats,
                )

            self.finished.emit(self.stats)
        except Exception as e:
            print(f"Worker error: {e}")
            self.error.emit(str(e))


# --- Main Application Window ---
class Walmover(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("Walmover Qt")
        self.setGeometry(100, 100, 800, 600)
        self.setStyleSheet("""
            QWidget {
                font-family: "Segoe UI", "Ubuntu", sans-serif;
                font-size: 14px;
            }
            QMainWindow {
                background-color: #f0f0f0;
            }
            QPushButton {
                padding: 6px;
            }
            QProgressBar {
                height: 20px;
            }
            QGroupBox {
                border: 1px solid #ccc;
                border-radius: 4px;
                margin-top: 6px;
            }
            QGroupBox::title {
                subcontrol-origin: margin;
                subcontrol-position: top center;
                padding: 0 3px;
            }
        """)

        self.src_dir = None
        self.dest_dir = None
        self.thread = None

        self.central_widget = QWidget()
        self.setCentralWidget(self.central_widget)

        self.layout = QVBoxLayout(self.central_widget)

        # Image list view configuration
        self.image_list_view = QListView()
        self.image_list_view.setViewMode(QListView.IconMode)
        self.image_list_view.setResizeMode(QListView.Adjust)
        self.image_list_view.setIconSize(QPixmap(ICON_SIZE, ICON_SIZE).size())
        self.image_list_view.setSelectionMode(QAbstractItemView.NoSelection)
        self.model = QStandardItemModel(self.image_list_view)
        self.image_list_view.setModel(self.model)
        self.layout.addWidget(self.image_list_view)

        # Progress bar configuration
        self.progress_bar = QProgressBar()
        self.progress_bar.setRange(0, 100)
        self.progress_bar.setValue(0)
        self.progress_bar.setFormat("%p%")
        self.layout.addWidget(self.progress_bar)

        # Aspect Ratio Selector (ComboBox)
        self.ratio_group_box = QGroupBox("Aspect Ratio")
        self.ratio_layout = QHBoxLayout()
        self.ratio_combo = QComboBox()
        self.ratio_combo.setEditable(True)
        self.ratio_combo.addItem("Desktop (16:9)")
        self.ratio_combo.addItem("Ultrawide (21:9)")
        self.ratio_combo.addItem("Standard (16:10)")
        self.ratio_combo.addItem("Mobile (9:16)")
        self.ratio_combo.setCurrentIndex(0)  # Default to Desktop
        self.ratio_layout.addWidget(self.ratio_combo)
        self.ratio_group_box.setLayout(self.ratio_layout)
        self.layout.addWidget(self.ratio_group_box)

        # Overwrite checkbox
        self.overwrite_checkbox = QCheckBox("Overwrite existing files")
        self.overwrite_checkbox.setChecked(False)
        self.layout.addWidget(self.overwrite_checkbox)

        # Status label for statistics
        self.status_label = QLabel("Ready")
        self.status_label.setAlignment(Qt.AlignLeft)
        self.layout.addWidget(self.status_label)

        # Button layout
        self.button_box = QHBoxLayout()

        self.src_button = QPushButton("Select Source")
        self.src_button.clicked.connect(self.on_src_button_clicked)
        self.button_box.addWidget(self.src_button)

        self.dest_button = QPushButton("Select Destination")
        self.dest_button.clicked.connect(self.on_dest_button_clicked)
        self.button_box.addWidget(self.dest_button)

        self.start_button = QPushButton("Start")
        self.start_button.setEnabled(False)  # Disabled until directories are selected
        self.start_button.clicked.connect(self.on_start_button_clicked)
        self.button_box.addWidget(self.start_button)

        self.cancel_button = QPushButton("Cancel")
        self.cancel_button.setEnabled(False)  # Disabled until processing starts
        self.cancel_button.clicked.connect(self.on_cancel_button_clicked)
        self.button_box.addWidget(self.cancel_button)

        self.done_button = QPushButton("Quit")
        self.done_button.clicked.connect(self.on_done_button_clicked)
        self.button_box.addWidget(self.done_button)

        self.layout.addLayout(self.button_box)

        self.status_bar = QStatusBar()
        self.setStatusBar(self.status_bar)

    def get_current_ratio(self):
        """Return the aspect ratio tuple based on the combo box selection."""
        text = self.ratio_combo.currentText()
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

    def on_src_button_clicked(self):
        src_dir = QFileDialog.getExistingDirectory(self, "Select Source Directory")
        if src_dir:
            self.src_dir = Path(src_dir)
            self.src_button.setText(f"Source: {self.src_dir.name}")
            self.check_start_conditions()

    def on_dest_button_clicked(self):
        dest_dir = QFileDialog.getExistingDirectory(
            self, "Select Destination Directory"
        )
        if dest_dir:
            self.dest_dir = Path(dest_dir)
            self.dest_button.setText(f"Destination: {self.dest_dir.name}")
            self.check_start_conditions()

    def check_start_conditions(self):
        if self.src_dir and self.dest_dir:
            self.start_button.setEnabled(True)

    def on_start_button_clicked(self):
        if not self.src_dir or not self.dest_dir:
            return

        # Prevent multiple concurrent workers
        if self.thread and self.thread.isRunning():
            return

        if not self.dest_dir.exists():
            try:
                self.dest_dir.mkdir(parents=True, exist_ok=True)
            except Exception as e:
                self.show_error_dialog(f"Error creating destination: {e}")
                return

        # Clear the image list
        self.model.clear()

        # Disable buttons during processing
        self.start_button.setEnabled(False)
        self.src_button.setEnabled(False)
        self.dest_button.setEnabled(False)
        self.done_button.setEnabled(False)
        self.ratio_combo.setEnabled(False)
        self.overwrite_checkbox.setEnabled(False)

        # Enable cancel button
        self.cancel_button.setEnabled(True)

        # Reset progress bar and status
        self.progress_bar.setValue(0)
        self.progress_bar.setFormat("Starting...")
        self.status_label.setText("Processing...")

        current_ratio = self.get_current_ratio()
        overwrite = self.overwrite_checkbox.isChecked()
        self.thread = Worker(self.src_dir, self.dest_dir, current_ratio, overwrite)
        self.thread.image_added.connect(self.add_image)
        self.thread.progress.connect(self.update_progress)
        self.thread.finished.connect(self.on_processing_finished)
        self.thread.cancelled.connect(self.on_processing_cancelled)
        self.thread.error.connect(self.show_error_dialog)
        self.thread.start()

    def on_cancel_button_clicked(self):
        """Cancel the current processing operation"""
        if self.thread and self.thread.isRunning():
            self.thread.cancel()
            self.cancel_button.setEnabled(False)
            self.status_label.setText("Cancelling...")

    def on_done_button_clicked(self):
        if self.thread and self.thread.isRunning():
            QMessageBox.warning(
                self,
                "Processing in Progress",
                "Processing is still running. Please wait or cancel first.",
            )
            return
        self.close()

    def add_image(self, image_path, is_duplicate=False):
        try:
            if is_duplicate:
                # Create pixbuf with exclamation mark overlay for duplicates
                pixmap = self.create_duplicate_thumbnail(str(image_path))
            else:
                pixmap = QPixmap(str(image_path))
                if not pixmap.isNull():
                    pixmap = pixmap.scaled(
                        ICON_SIZE,
                        ICON_SIZE,
                        Qt.KeepAspectRatio,
                        Qt.SmoothTransformation,
                    )

            if not pixmap.isNull():
                item = QStandardItem()
                item.setIcon(QIcon(pixmap))
                item.setText(image_path.name)
                item.setEditable(False)
                self.model.appendRow(item)
        except Exception as e:
            print(f"Error adding image: {e}")

    def create_duplicate_thumbnail(self, image_path):
        """Create a thumbnail with an exclamation mark overlay for duplicates"""
        try:
            # Load and resize the image using PIL
            pil_img = Image.open(image_path)
            pil_img.thumbnail((ICON_SIZE, ICON_SIZE), Image.Resampling.LANCZOS)

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
                font = ImageFont.truetype("arial.ttf", 28)
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

            # Convert PIL image to QPixmap
            buffer = io.BytesIO()
            pil_img.save(buffer, format="PNG")
            buffer.seek(0)

            qimage_data = QByteArray(buffer.read())
            pixmap = QPixmap()
            pixmap.loadFromData(qimage_data)

            pil_img.close()
            return pixmap

        except Exception as e:
            print(f"Error creating duplicate thumbnail: {e}")
            # Fallback to regular thumbnail
            pixmap = QPixmap(image_path)
            return pixmap.scaled(
                ICON_SIZE, ICON_SIZE, Qt.KeepAspectRatio, Qt.SmoothTransformation
            )

    def update_progress(self, message, fraction, stats):
        """Update the progress bar and format"""
        self.progress_bar.setValue(int(fraction * 100))
        self.progress_bar.setFormat(f"{int(fraction * 100)}%")
        self.status_bar.showMessage(message)

    def on_processing_finished(self, stats):
        """Called when processing is complete"""
        self.progress_bar.setValue(100)
        self.progress_bar.setFormat("Processing complete")

        # Update status label with final statistics
        status_text = (
            f"Complete - Total: {stats['total']} | Copied: {stats['copied']} | "
            f"Overwritten: {stats['overwritten']} | Skipped: {stats['skipped']} | "
            f"Failed: {stats['failed']}"
        )
        self.status_label.setText(status_text)

        # Re-enable buttons
        self.start_button.setEnabled(True)
        self.src_button.setEnabled(True)
        self.dest_button.setEnabled(True)
        self.done_button.setEnabled(True)
        self.ratio_combo.setEnabled(True)
        self.overwrite_checkbox.setEnabled(True)
        self.cancel_button.setEnabled(False)

    def on_processing_cancelled(self, stats):
        """Called when processing is cancelled"""
        self.progress_bar.setFormat("Cancelled")

        # Update status label with statistics up to cancellation
        processed = stats["copied"] + stats["overwritten"] + stats["skipped"]
        status_text = (
            f"Cancelled - Processed: {processed} of {stats['total']} | "
            f"Copied: {stats['copied']} | Overwritten: {stats['overwritten']} | "
            f"Skipped: {stats['skipped']} | Failed: {stats['failed']}"
        )
        self.status_label.setText(status_text)

        # Re-enable buttons
        self.start_button.setEnabled(True)
        self.src_button.setEnabled(True)
        self.dest_button.setEnabled(True)
        self.done_button.setEnabled(True)
        self.ratio_combo.setEnabled(True)
        self.overwrite_checkbox.setEnabled(True)
        self.cancel_button.setEnabled(False)

    def show_error_dialog(self, message):
        """Display an error dialog to the user"""
        QMessageBox.critical(self, "Error", message)

    def update_status_bar(self, message):
        self.status_bar.showMessage(message, 5000)


if __name__ == "__main__":
    app = QApplication(sys.argv)
    window = Walmover()
    window.show()
    sys.exit(app.exec_())
