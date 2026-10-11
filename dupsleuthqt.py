#!/usr/bin/env python3
"""Qt 6 duplicate-image and incorrect-extension finder."""

import hashlib
import logging
import os
import sys
from collections import defaultdict
from pathlib import Path
from threading import Event

import imagehash
from PIL import Image, UnidentifiedImageError
from PyQt6.QtCore import QObject, QSize, Qt, QThread, pyqtSignal, pyqtSlot
from PyQt6.QtGui import QCloseEvent, QIcon, QPixmap
from PyQt6.QtWidgets import (
    QAbstractItemView,
    QApplication,
    QFileDialog,
    QHBoxLayout,
    QLabel,
    QListView,
    QListWidget,
    QListWidgetItem,
    QMainWindow,
    QMessageBox,
    QProgressBar,
    QPushButton,
    QTabWidget,
    QVBoxLayout,
    QWidget,
)
from send2trash import send2trash


LOG = logging.getLogger(__name__)
PHASH_LIMIT = 6
FORMATS = {
    "JPEG": {".jpg", ".jpeg", ".jpe", ".jfif"},
    "PNG": {".png"},
    "GIF": {".gif"},
    "WEBP": {".webp"},
    "BMP": {".bmp", ".dib"},
    "TIFF": {".tif", ".tiff"},
    "ICO": {".ico"},
    "AVIF": {".avif"},
}
IMAGE_SUFFIXES = set().union(*FORMATS.values())
PREFERRED = {
    image_format: min(extensions, key=len)
    for image_format, extensions in FORMATS.items()
}

PATH_ROLE = Qt.ItemDataRole.UserRole
EXTENSION_ROLE = Qt.ItemDataRole.UserRole + 1


def inspect_image(path):
    """Return a Pillow format and perceptual hash, or ``(None, None)``."""
    try:
        with Image.open(path) as image:
            return image.format, imagehash.phash(image.convert("RGB"))
    except (UnidentifiedImageError, OSError, ValueError):
        return None, None


def file_digest(path, cancel):
    """Calculate a SHA-256 digest, stopping early when requested."""
    result = hashlib.sha256()
    with path.open("rb") as stream:
        while data := stream.read(1024 * 1024):
            if cancel.is_set():
                return None
            result.update(data)
    return result.hexdigest()


class ScanWorker(QObject):
    """Scan a directory off the GUI thread and report results through signals."""

    progress = pyqtSignal(str, float)
    result = pyqtSignal(str, str, str, str)
    finished = pyqtSignal(str, bool)
    failed = pyqtSignal(str)

    def __init__(self, directory, cancel):
        super().__init__()
        self.directory = Path(directory)
        self.cancel = cancel

    def cancelled(self):
        if self.cancel.is_set():
            self.finished.emit("Scan cancelled.", True)
            return True
        return False

    @pyqtSlot()
    def run(self):
        try:
            self.scan_images()
        except Exception as error:  # Keep unexpected worker failures out of Qt.
            LOG.exception("Scan failed")
            self.failed.emit(str(error))

    def scan_images(self):
        files = []
        for root, _directories, names in os.walk(self.directory):
            if self.cancelled():
                return
            for name in names:
                path = Path(root) / name
                if not path.is_symlink():
                    files.append(path)

        records = []
        problems = 0
        total_files = len(files)
        for number, path in enumerate(files, 1):
            if self.cancelled():
                return
            image_format, perceptual_hash = inspect_image(path)
            suffix = path.suffix.lower()
            if image_format and perceptual_hash is not None:
                try:
                    records.append((path, path.stat().st_size, perceptual_hash))
                except OSError:
                    continue
                if image_format in FORMATS and suffix not in FORMATS[image_format]:
                    extension = PREFERRED[image_format]
                    problems += 1
                    self.result.emit(
                        "extension",
                        str(path),
                        f"{path.name}\nDetected {image_format}; expected {extension}\n{path.parent}",
                        extension,
                    )
            elif suffix in IMAGE_SUFFIXES:
                problems += 1
                self.result.emit(
                    "extension",
                    str(path),
                    f"{path.name}\nNot a readable image\n{path.parent}",
                    "",
                )
            fraction = number / total_files if total_files else 1.0
            self.progress.emit(f"Inspecting {number}/{total_files}", fraction)

        sizes = defaultdict(list)
        for record in records:
            sizes[record[1]].append(record)

        groups = []
        exact_paths = set()
        candidates = [group for group in sizes.values() if len(group) > 1]
        candidate_count = sum(len(group) for group in candidates)
        hashed = 0
        for same_size in candidates:
            hashes = defaultdict(list)
            for record in same_size:
                if self.cancelled():
                    return
                try:
                    value = file_digest(record[0], self.cancel)
                except OSError:
                    value = None
                if value:
                    hashes[value].append(record)
                hashed += 1
                fraction = hashed / candidate_count if candidate_count else 1.0
                self.progress.emit(
                    f"Checking exact matches {hashed}/{candidate_count}", fraction
                )
            for group in hashes.values():
                if len(group) > 1:
                    groups.append(group)
                    exact_paths.update(item[0] for item in group)

        for group_number, group in enumerate(groups, 1):
            for path, size, _perceptual_hash in group:
                self.result.emit(
                    "exact",
                    str(path),
                    f"Group {group_number}: {path.name}\nExact match, {size:,} bytes\n{path.parent}",
                    "",
                )

        unique = [record for record in records if record[0] not in exact_paths]
        pairs = []
        comparison_count = len(unique) * (len(unique) - 1) // 2
        compared = 0
        for index, left in enumerate(unique):
            if self.cancelled():
                return
            for right in unique[index + 1 :]:
                if self.cancel.is_set():
                    self.finished.emit("Scan cancelled.", True)
                    return
                distance = left[2] - right[2]
                if distance <= PHASH_LIMIT:
                    pairs.append((left, right, distance))
                compared += 1
                if compared % 250 == 0 or compared == comparison_count:
                    fraction = compared / comparison_count if comparison_count else 1.0
                    self.progress.emit(
                        f"Comparing similar images {compared}/{comparison_count}",
                        fraction,
                    )

        for pair_number, (left, right, distance) in enumerate(pairs, 1):
            for record, other in ((left, right), (right, left)):
                path = record[0]
                self.result.emit(
                    "similar",
                    str(path),
                    f"Pair {pair_number}: {path.name}\nSimilar to {other[0].name} "
                    f"(distance {distance})\n{path.parent}",
                    "",
                )

        self.finished.emit(
            f"Found {len(groups)} exact group(s), {len(pairs)} similar pair(s), "
            f"and {problems} extension problem(s).",
            False,
        )


class DupSleuth(QMainWindow):
    TABS = (
        ("exact", "Exact duplicates"),
        ("similar", "Similar images"),
        ("extension", "Extension problems"),
    )

    def __init__(self):
        super().__init__()
        self.setWindowTitle("Dup Sleuth")
        self.resize(950, 680)
        self.directory = None
        self.cancel = Event()
        self.worker = None
        self.worker_thread = None
        self.close_when_finished = False

        self.label = QLabel("Choose a directory to scan.")
        self.tabs = QTabWidget()
        self.lists = {}
        for key, title in self.TABS:
            result_list = QListWidget()
            result_list.setViewMode(QListView.ViewMode.IconMode)
            result_list.setResizeMode(QListView.ResizeMode.Adjust)
            result_list.setMovement(QListView.Movement.Static)
            result_list.setIconSize(QSize(128, 128))
            result_list.setGridSize(QSize(225, 190))
            result_list.setWordWrap(True)
            result_list.setSelectionMode(
                QAbstractItemView.SelectionMode.ExtendedSelection
            )
            result_list.itemSelectionChanged.connect(self.selection_changed)
            self.tabs.addTab(result_list, title)
            self.lists[key] = result_list
        self.tabs.currentChanged.connect(self.selection_changed)

        self.progress = QProgressBar()
        self.progress.setRange(0, 1000)
        self.progress.setValue(0)
        self.progress.setFormat("Ready")

        self.choose_button = QPushButton("Select Source Directory")
        self.choose_button.clicked.connect(self.select_directory)
        self.trash_button = QPushButton("Move Selected to Trash")
        self.trash_button.clicked.connect(self.trash_selected)
        self.rename_button = QPushButton("Fix Selected Extensions")
        self.rename_button.clicked.connect(self.rename_selected)
        close_button = QPushButton("Close")
        close_button.clicked.connect(self.close)

        buttons = QHBoxLayout()
        for button in (
            self.choose_button,
            self.trash_button,
            self.rename_button,
            close_button,
        ):
            buttons.addWidget(button)

        layout = QVBoxLayout()
        layout.addWidget(self.label)
        layout.addWidget(self.tabs, 1)
        layout.addWidget(self.progress)
        layout.addLayout(buttons)
        container = QWidget()
        container.setLayout(layout)
        self.setCentralWidget(container)
        self.statusBar().showMessage("Ready")
        self.selection_changed()

    def current(self):
        key = self.TABS[self.tabs.currentIndex()][0]
        return key, self.lists[key]

    def selection_changed(self, *_args):
        key, result_list = self.current()
        selected = result_list.selectedItems()
        busy = self.worker_thread is not None and self.worker_thread.isRunning()
        self.trash_button.setEnabled(bool(selected) and not busy)
        self.rename_button.setEnabled(
            key == "extension"
            and not busy
            and any(item.data(EXTENSION_ROLE) for item in selected)
        )

    @pyqtSlot()
    def select_directory(self):
        directory = QFileDialog.getExistingDirectory(self, "Choose a directory")
        if directory:
            self.directory = Path(directory)
            self.start_scan()

    def start_scan(self):
        for result_list in self.lists.values():
            result_list.clear()
        self.cancel = Event()
        self.choose_button.setEnabled(False)
        self.progress.setValue(0)
        self.progress.setFormat("Discovering files...")
        self.label.setText(f"Scanning: {self.directory}")
        self.statusBar().showMessage("Scanning does not modify files.")

        self.worker_thread = QThread(self)
        self.worker = ScanWorker(self.directory, self.cancel)
        self.worker.moveToThread(self.worker_thread)
        self.worker_thread.started.connect(self.worker.run)
        self.worker.progress.connect(self.set_progress)
        self.worker.result.connect(self.add_result)
        self.worker.finished.connect(self.scan_finished)
        self.worker.failed.connect(self.scan_failed)
        self.worker.finished.connect(self.worker_thread.quit)
        self.worker.failed.connect(self.worker_thread.quit)
        self.worker_thread.finished.connect(self.worker.deleteLater)
        self.worker_thread.finished.connect(self.thread_finished)
        self.worker_thread.start()
        self.selection_changed()

    @pyqtSlot(str, str, str, str)
    def add_result(self, category, path, text, extension):
        item = QListWidgetItem(text)
        item.setData(PATH_ROLE, path)
        item.setData(EXTENSION_ROLE, extension)
        pixmap = QPixmap(path)
        if not pixmap.isNull():
            pixmap = pixmap.scaled(
                128,
                128,
                Qt.AspectRatioMode.KeepAspectRatio,
                Qt.TransformationMode.SmoothTransformation,
            )
            item.setIcon(QIcon(pixmap))
        item.setToolTip(path)
        self.lists[category].addItem(item)

    @pyqtSlot(str, float)
    def set_progress(self, text, fraction):
        self.progress.setValue(round(max(0.0, min(1.0, fraction)) * 1000))
        self.progress.setFormat(text)

    @pyqtSlot(str, bool)
    def scan_finished(self, summary, cancelled=False):
        self.progress.setValue(0 if cancelled else 1000)
        self.progress.setFormat("Cancelled" if cancelled else "Done")
        self.label.setText(summary)
        self.statusBar().showMessage(
            "Scan cancelled."
            if cancelled
            else "Select results to rename or move to trash."
        )
        self.selection_changed()

    @pyqtSlot(str)
    def scan_failed(self, message):
        self.progress.setValue(0)
        self.progress.setFormat("Error")
        self.label.setText("Scan failed.")
        self.statusBar().showMessage(message)
        QMessageBox.critical(self, "Scan failed", message)

    @pyqtSlot()
    def thread_finished(self):
        thread = self.worker_thread
        self.worker = None
        self.worker_thread = None
        if thread is not None:
            thread.deleteLater()
        self.choose_button.setEnabled(True)
        self.selection_changed()
        if self.close_when_finished:
            self.close()

    def confirm(self, title, detail):
        dialog = QMessageBox(self)
        dialog.setIcon(QMessageBox.Icon.Warning)
        dialog.setWindowTitle("Dup Sleuth")
        dialog.setText(title)
        dialog.setInformativeText(detail)
        dialog.setStandardButtons(QMessageBox.StandardButton.Cancel)
        continue_button = dialog.addButton(
            "Continue", QMessageBox.ButtonRole.AcceptRole
        )
        dialog.exec()
        return dialog.clickedButton() is continue_button

    @pyqtSlot()
    def trash_selected(self):
        _key, result_list = self.current()
        selected = result_list.selectedItems()
        if not selected or not self.confirm(
            f"Move {len(selected)} file(s) to trash?",
            "Review selected paths before continuing.",
        ):
            return

        moved = 0
        for item in list(selected):
            path = item.data(PATH_ROLE)
            try:
                send2trash(path)
                result_list.takeItem(result_list.row(item))
                moved += 1
            except Exception as error:
                LOG.error("Cannot trash %s: %s", path, error)
        self.statusBar().showMessage(f"Moved {moved} file(s) to trash.")
        self.selection_changed()

    @pyqtSlot()
    def rename_selected(self):
        key, result_list = self.current()
        selected = [
            item
            for item in result_list.selectedItems()
            if item.data(EXTENSION_ROLE)
        ]
        if key != "extension" or not selected or not self.confirm(
            f"Rename {len(selected)} file(s)?",
            "Existing destinations will be skipped.",
        ):
            return

        renamed = 0
        for item in list(selected):
            source = Path(item.data(PATH_ROLE))
            destination = source.with_suffix(item.data(EXTENSION_ROLE))
            try:
                if destination.exists():
                    raise FileExistsError(destination)
                source.rename(destination)
                result_list.takeItem(result_list.row(item))
                renamed += 1
            except OSError as error:
                LOG.error("Cannot rename %s: %s", source, error)
        self.statusBar().showMessage(f"Renamed {renamed} file(s).")
        self.selection_changed()

    def closeEvent(self, event: QCloseEvent):
        if self.worker_thread is not None and self.worker_thread.isRunning():
            self.close_when_finished = True
            self.cancel.set()
            self.choose_button.setEnabled(False)
            self.label.setText("Cancelling scan...")
            self.statusBar().showMessage("Waiting for the scanner to stop safely.")
            event.ignore()
            return
        event.accept()


def main():
    """Launch the Dup Sleuth Qt 6 application."""
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s - %(levelname)s - %(message)s",
    )
    app = QApplication(sys.argv)
    window = DupSleuth()
    window.show()
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
