#!/usr/bin/env python3

import sys
import shutil
import argparse
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
        for file_path in self.src_dir.iterdir():
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
        self.done_button = QPushButton("Done")
        self.done_button.clicked.connect(self.on_done_button_clicked)
        self.button_box.addItem(
            QSpacerItem(20, 40, QSizePolicy.Expanding, QSizePolicy.Minimum)
        )
        self.button_box.addWidget(self.done_button)
        self.layout.addLayout(self.button_box)

        self.status_bar = QStatusBar()
        self.setStatusBar(self.status_bar)

    def start_copy(self, src_dir, dest_dir):
        self.thread = Worker(src_dir, dest_dir)
        self.thread.image_added.connect(self.add_image)
        self.thread.finished.connect(self.stop_progress)
        self.thread.start()

    def on_done_button_clicked(self):
        self.close()


    def add_image(self, image_path, exists=False):
        if not exists:  # Only add image if it does not exist in the destination
            pixmap = QPixmap(str(image_path))
            pixmap = pixmap.scaled(128, 128, Qt.KeepAspectRatio, Qt.SmoothTransformation)

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
    parser = argparse.ArgumentParser(
        description="Copy images with 16:9 aspect ratio from source to destination directory"
    )
    parser.add_argument("source", type=str, help="The source directory")
    parser.add_argument("destination", type=str, help="The destination directory")
    args = parser.parse_args()

    src_dir = Path(args.source)
    dest_dir = Path(args.destination)

    if not src_dir.is_dir():
        print(f"Error: {args.source} is not a valid directory!")
        sys.exit(1)

    if not dest_dir.is_dir():
        dest_dir.mkdir(parents=True, exist_ok=True)

    app = QApplication(sys.argv)
    window = ImageCopyApp()

    window.start_copy(src_dir, dest_dir)
    window.show()
    sys.exit(app.exec_())
