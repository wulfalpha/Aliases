#!/usr/bin/env python3

import sys
import shutil
from pathlib import Path
from PIL import Image

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
    QRadioButton,
)
from PyQt5.QtGui import QPixmap, QStandardItemModel, QStandardItem, QIcon
from PyQt5.QtCore import Qt, QThread, pyqtSignal

# --- Constants ---
VALID_EXTENSIONS = {".png", ".jpg", ".jpeg"}
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
    finished = pyqtSignal()
    progress = pyqtSignal(int)  # emits progress percentage (0 to 100)
    image_added = pyqtSignal(Path, bool)

    def __init__(self, src_dir, dest_dir, ratio, parent=None):
        super().__init__(parent)
        self.src_dir = src_dir
        self.dest_dir = dest_dir
        self.ratio = ratio

    def run(self):
        image_files = [f for f in self.src_dir.iterdir() if is_valid_image(f)]
        total_files = len(image_files)
        if total_files == 0:
            self.finished.emit()
            return

        for idx, file_path in enumerate(image_files):
            try:
                with Image.open(file_path) as img:
                    width, height = img.size
            except Exception as e:
                print(f"Error opening {file_path}: {e}")
                continue

            if has_aspect_ratio(width, height, ratio=self.ratio):
                dest_path = self.dest_dir / file_path.name
                if not dest_path.exists():
                    try:
                        shutil.copy(file_path, dest_path)
                        self.image_added.emit(dest_path, False)
                    except Exception as e:
                        print(f"Error copying {file_path} to {dest_path}: {e}")
                        continue
                else:
                    self.image_added.emit(dest_path, True)

            progress_percent = int((idx + 1) / total_files * 100)
            self.progress.emit(progress_percent)

        self.finished.emit()


# --- Main Application Window ---
class Walmover(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("Walmover 4")
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
        self.layout.addWidget(self.progress_bar)

        # Aspect Ratio Selector (Radio Buttons)
        self.ratio_group_box = QGroupBox("Aspect Ratio")
        self.ratio_layout = QHBoxLayout()
        self.desktop_radio = QRadioButton("Desktop (16:9)")
        self.mobile_radio = QRadioButton("Mobile (9:16)")
        self.desktop_radio.setChecked(True)  # Default to Desktop
        self.ratio_layout.addWidget(self.desktop_radio)
        self.ratio_layout.addWidget(self.mobile_radio)
        self.ratio_group_box.setLayout(self.ratio_layout)
        self.layout.addWidget(self.ratio_group_box)

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

        self.done_button = QPushButton("Quit")
        self.done_button.clicked.connect(self.on_done_button_clicked)
        self.button_box.addWidget(self.done_button)

        self.layout.addLayout(self.button_box)

        self.status_bar = QStatusBar()
        self.setStatusBar(self.status_bar)

    def current_ratio(self):
        """Return the aspect ratio tuple based on the radio button selection."""
        if self.desktop_radio.isChecked():
            return (16, 9)
        else:
            return (9, 16)

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

        if not self.dest_dir.exists():
            try:
                self.dest_dir.mkdir(parents=True, exist_ok=True)
            except Exception as e:
                self.update_status_bar(f"Error creating destination: {e}")
                return

        # Disable buttons during processing
        self.start_button.setEnabled(False)
        self.src_button.setEnabled(False)
        self.dest_button.setEnabled(False)
        self.done_button.setEnabled(False)
        self.progress_bar.setValue(0)

        current_ratio = self.current_ratio()
        self.thread = Worker(self.src_dir, self.dest_dir, current_ratio)
        self.thread.image_added.connect(self.add_image)
        self.thread.progress.connect(self.update_progress)
        self.thread.finished.connect(self.on_thread_finished)
        self.thread.start()

    def on_done_button_clicked(self):
        if self.thread and self.thread.isRunning():
            self.update_status_bar("Processing in progress. Please wait.")
            return
        self.close()

    def add_image(self, image_path, exists=False):
        if not exists:
            pixmap = QPixmap(str(image_path))
            if not pixmap.isNull():
                pixmap = pixmap.scaled(
                    ICON_SIZE, ICON_SIZE, Qt.KeepAspectRatio, Qt.SmoothTransformation
                )
                item = QStandardItem()
                item.setIcon(QIcon(pixmap))
                item.setText(image_path.name)
                item.setEditable(False)
                self.model.appendRow(item)
            else:
                self.update_status_bar(f"Failed to load image: {image_path.name}")
        else:
            self.update_status_bar(f"File already exists: {image_path.name}")

    def update_progress(self, value):
        self.progress_bar.setValue(value)

    def update_status_bar(self, message):
        self.status_bar.showMessage(message, 5000)

    def on_thread_finished(self):
        # Re-enable buttons when processing is complete
        self.start_button.setEnabled(True)
        self.src_button.setEnabled(True)
        self.dest_button.setEnabled(True)
        self.done_button.setEnabled(True)
        self.update_status_bar("Processing complete.")


if __name__ == "__main__":
    app = QApplication(sys.argv)
    window = Walmover()
    window.show()
    sys.exit(app.exec_())
