#!/usr/bin/env python3

import sys
import shutil
from pathlib import Path
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
    QSpacerItem,
    QSizePolicy,
    QFileDialog,
)
from PyQt5.QtGui import QPixmap, QStandardItemModel, QStandardItem, QIcon
from PyQt5.QtCore import Qt, QThread, pyqtSignal
from PIL import Image  # Ensure this is imported globally


class Worker(QThread):
    finished = pyqtSignal()
    image_added = pyqtSignal(Path, bool)

    def __init__(self, src_dir, dest_dir, parent=None):
        super().__init__(parent)
        self.src_dir = src_dir
        self.dest_dir = dest_dir

    def run(self):
        image_files = list(self.src_dir.iterdir())
        total_files = len(image_files)
        for idx, file_path in enumerate(image_files):
            if not is_valid_image(file_path):
                continue

            with Image.open(file_path) as img:
                width, height = img.size

            if has_aspect_ratio(width, height):
                dest_path = self.dest_dir / file_path.name

                if not dest_path.exists():
                    shutil.copy(file_path, dest_path)
                    self.image_added.emit(dest_path, False)
                else:
                    self.image_added.emit(dest_path, True)

        self.finished.emit()


class ImageCopyApp(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("Image Copy App")
        self.setGeometry(100, 100, 800, 600)

        self.src_dir = None
        self.dest_dir = None

        self.central_widget = QWidget()
        self.setCentralWidget(self.central_widget)

        self.layout = QVBoxLayout(self.central_widget)

        self.image_list_view = QListView()
        self.image_list_view.setViewMode(QListView.IconMode)
        self.image_list_view.setResizeMode(QListView.Adjust)
        self.image_list_view.setIconSize(QPixmap(128, 128).size())
        self.image_list_view.setSelectionMode(QAbstractItemView.NoSelection)

        self.model = QStandardItemModel(self.image_list_view)
        self.image_list_view.setModel(self.model)

        self.layout.addWidget(self.image_list_view)

        self.progress_bar = QProgressBar()
        self.progress_bar.setRange(0, 0)
        self.layout.addWidget(self.progress_bar)

        self.button_box = QHBoxLayout()

        # Source directory button
        self.src_button = QPushButton("Select Source")
        self.src_button.clicked.connect(self.on_src_button_clicked)
        self.button_box.addWidget(self.src_button)

        # Destination directory button
        self.dest_button = QPushButton("Select Destination")
        self.dest_button.clicked.connect(self.on_dest_button_clicked)
        self.button_box.addWidget(self.dest_button)

        # Start button
        self.start_button = QPushButton("Start")
        self.start_button.setEnabled(False)  # Disabled until directories are selected
        self.start_button.clicked.connect(self.on_start_button_clicked)
        self.button_box.addWidget(self.start_button)

        # Done button
        self.done_button = QPushButton("Quit")
        self.done_button.clicked.connect(self.on_done_button_clicked)
        self.button_box.addWidget(self.done_button)

        self.layout.addLayout(self.button_box)

        self.status_bar = QStatusBar()
        self.setStatusBar(self.status_bar)

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

        if not self.dest_dir.is_dir():
            self.dest_dir.mkdir(parents=True, exist_ok=True)

        self.progress_bar.setRange(0, 0)
        self.thread = Worker(self.src_dir, self.dest_dir)
        self.thread.image_added.connect(self.add_image)
        self.thread.finished.connect(self.stop_progress)
        self.thread.start()

    def on_done_button_clicked(self):
        self.close()

    def add_image(self, image_path, exists=False):
        if not exists:  # Only add image if it does not exist in the destination
            pixmap = QPixmap(str(image_path))
            pixmap = pixmap.scaled(
                128, 128, Qt.KeepAspectRatio, Qt.SmoothTransformation
            )

            item = QStandardItem()
            item.setIcon(QIcon(pixmap))
            item.setText(image_path.name)
            item.setEditable(False)
            self.model.appendRow(item)
        else:
            self.update_status_bar(f"File already exists: {image_path.name}")

    def update_status_bar(self, message):
        self.status_bar.showMessage(message, 5000)

    def stop_progress(self):
        self.progress_bar.setRange(0, 1)


def is_valid_image(file_path):
    return file_path.is_file() and file_path.suffix.lower() in [".png", ".jpg", ".jpeg"]


def has_aspect_ratio(width, height, ratio=(16, 9)):
    calculated_ratio = width / height
    expected_ratio = ratio[0] / ratio[1]
    return 0.95 * expected_ratio <= calculated_ratio <= 1.05 * expected_ratio


if __name__ == "__main__":
    app = QApplication(sys.argv)
    window = ImageCopyApp()
    window.show()
    sys.exit(app.exec_())
