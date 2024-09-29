import os
import logging
from pathlib import Path
from threading import Thread

from PyQt5.QtWidgets import (
    QApplication,
    QMainWindow,
    QLabel,
    QVBoxLayout,
    QPushButton,
    QHBoxLayout,
    QProgressBar,
    QListView,
    QFileDialog,
    QWidget,
    QListWidget,
    QListWidgetItem,
)
from PyQt5.QtGui import QPixmap, QIcon
from PyQt5.QtCore import Qt, pyqtSignal, QObject

import imagehash
from PIL import Image
from send2trash import send2trash


class Worker(QObject):
    update_status = pyqtSignal(str)
    update_progress = pyqtSignal(str, float)
    add_duplicate_image = pyqtSignal(str, str)
    stop_progress_bar = pyqtSignal()

    def __init__(self, directory):
        super().__init__()
        self.directory = directory

    def calculate_phash(self, image_path):
        """Calculate the perceptual hash (phash) for an image."""
        try:
            img = Image.open(str(image_path))
            img_hash = imagehash.phash(img)
            return str(img_hash)
        except Exception as e:
            logging.error(f"Error calculating phash for {image_path}: {e}")
            return None

    def compare_images(self, image_hashes, image_path):
        """Compare the phash of the current image with already processed images."""
        new_hash = self.calculate_phash(image_path)
        if new_hash in image_hashes:
            return True, new_hash, image_hashes[new_hash]
        else:
            image_hashes[new_hash] = str(image_path)
            return False, new_hash, None

    def move_to_trash(self, file_path):
        """Move the specified file to the trash."""
        try:
            send2trash(str(file_path))
            logging.info(f"Moved {file_path} to trash.")
            return True
        except Exception as e:
            logging.error(f"Error moving file {file_path} to trash: {e}")
            return False

    def scan_images(self):
        image_hashes = {}
        total_files = 0

        # Count total files for progress bar
        for root, _, files in os.walk(self.directory):
            for file_name in files:
                if file_name.lower().endswith((".png", ".jpg", ".jpeg")):
                    total_files += 1

        scanned_files = 0

        try:
            with open("duplicates.txt", "w") as dup_file:
                for root, _, files in os.walk(self.directory):
                    for file_name in files:
                        if file_name.lower().endswith((".png", ".jpg", ".jpeg")):
                            file_path = Path(root) / file_name
                            is_duplicate, new_hash, original_file = self.compare_images(
                                image_hashes, file_path
                            )
                            if is_duplicate:
                                logging.info(f"Duplicate found: {file_path}")
                                self.add_duplicate_image.emit(
                                    str(file_path), original_file
                                )
                                if self.move_to_trash(file_path):
                                    dup_file.write(
                                        f"Duplicate found: {original_file} and {file_path} (moved to trash)\n"
                                    )

                            # Update progress
                            scanned_files += 1
                            progress_fraction = scanned_files / total_files
                            self.update_progress.emit(
                                f"Scanning... {scanned_files}/{total_files} files",
                                progress_fraction,
                            )

        except Exception as e:
            self.update_status.emit(f"An error occurred: {e}")
            logging.error(f"An error occurred: {e}")
        finally:
            self.stop_progress_bar.emit()


class DupSleuth(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("Dup Sleuth")
        self.setGeometry(100, 100, 800, 600)

        self.directory = None

        # Layout
        layout = QVBoxLayout()

        # Label
        self.label = QLabel("Duplicate Images found:")
        layout.addWidget(self.label)

        # List View
        self.list_widget = QListWidget()
        layout.addWidget(self.list_widget)

        # Progress Bar
        self.progress_bar = QProgressBar()
        layout.addWidget(self.progress_bar)

        # Buttons
        button_layout = QHBoxLayout()
        self.select_directory_button = QPushButton("Select Source Directory")
        self.select_directory_button.clicked.connect(self.on_select_directory)
        button_layout.addWidget(self.select_directory_button)

        self.close_button = QPushButton("Close")
        self.close_button.clicked.connect(self.close)
        button_layout.addWidget(self.close_button)

        layout.addLayout(button_layout)

        # Set the central widget
        container = QWidget()
        container.setLayout(layout)
        self.setCentralWidget(container)

    def on_select_directory(self):
        self.directory = QFileDialog.getExistingDirectory(self, "Select Directory")
        if self.directory:
            logging.info(f"Selected directory: {self.directory}")
            # Start scanning in a separate thread
            self.start_scan()

    def start_scan(self):
        self.progress_bar.setValue(0)
        self.list_widget.clear()  # Clear previous results

        self.worker = Worker(self.directory)
        self.worker_thread = Thread(target=self.worker.scan_images)
        self.worker_thread.start()

        self.worker.update_status.connect(self.update_status)
        self.worker.update_progress.connect(self.update_progress)
        self.worker.add_duplicate_image.connect(self.add_duplicate_image)
        self.worker.stop_progress_bar.connect(self.stop_progress_bar)

    def add_duplicate_image(self, image_path, original_file):
        try:
            item = QListWidgetItem(f"Duplicate of: {original_file}")
            pixmap = QPixmap(image_path).scaled(128, 128, Qt.KeepAspectRatio)
            item.setIcon(QIcon(pixmap))
            self.list_widget.addItem(item)
        except Exception as e:
            logging.warning(f"Failed to load image {image_path}: {e}")

    def update_status(self, message):
        self.statusBar().showMessage(message)

    def update_progress(self, text, fraction):
        self.progress_bar.setValue(int(fraction * 100))
        self.progress_bar.setFormat(text)

    def stop_progress_bar(self):
        self.progress_bar.setValue(100)
        self.progress_bar.setFormat("Done")


if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
    )

    app = QApplication([])
    window = DupSleuth()
    window.show()
    app.exec_()
