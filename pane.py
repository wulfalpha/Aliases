#!/usr/bin/env python

import sys
import argparse
import mpv
import re
from PyQt5.QtCore import QUrl, QSize, Qt
from PyQt5.QtGui import QIcon, QResizeEvent
from PyQt5.QtWebEngineWidgets import QWebEngineView, QWebEngineSettings, QWebEngineDownloadItem
from PyQt5.QtWidgets import QApplication, QMainWindow, QDesktopWidget, QMessageBox, QSizePolicy, QFileDialog

DEFAULT_URL = "https://search.brave.com"

class PaneWebEngineView(QWebEngineView):
    def __init__(self):
        super().__init__()
        self.settings().setAttribute(QWebEngineSettings.FullScreenSupportEnabled, True)

        # Connect download requests to a slot
        self.page().profile().downloadRequested.connect(self.handle_download_request)

    def load_url(self, url):
        if QUrl.fromUserInput(url).isValid():
            self.load(QUrl(url))
        else:
            QMessageBox.critical(self, "Error", f"Invalid URL: {url}")

    def handle_download_request(self, download):
        # Prompt user to select a file location
        save_path, _ = QFileDialog.getSaveFileName(self, "Save File", download.downloadFileName())
        if save_path:
            download.setPath(save_path)
            download.accept()
        else:
            download.cancel()


class Pane(QMainWindow):
    def __init__(self, url):
        super().__init__()

        # Create an MPV player instance
        self.mpv_player = None

        # Check if the URL points to a video
        if self.is_video_url(url):
            self.init_mpv(url)
        else:
            self.init_ui(url)
        self.show()

    def init_ui(self, url):
        screen_size = QDesktopWidget().availableGeometry().size()
        window_size = QSize(int(screen_size.width() * 0.8), int(screen_size.height() * 0.8))
        self.setMinimumSize(window_size)

        icon_path = "hidive.png"
        if QIcon.hasThemeIcon(icon_path):
            self.setWindowIcon(QIcon(icon_path))
        else:
            self.setWindowIcon(QIcon.fromTheme("application-x-executable"))

        self.setWindowTitle(f"{url} - Pane")

        self.browser = PaneWebEngineView()
        self.browser.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
        self.browser.load_url(url)
        self.setCentralWidget(self.browser)

    def init_mpv(self, video_url):
        # Initialize MPV player
        self.mpv_player = mpv.MPV(wid=str(int(self.winId())))
        self.mpv_player.play(video_url)

    def is_video_url(self, url):
        # Simple regex to detect common video file formats and URLs
        video_formats = r'.*\.(mp4|mkv|webm|avi|mov|flv)$'
        return re.match(video_formats, url, re.IGNORECASE)

    def resizeEvent(self, event: QResizeEvent):
        if self.mpv_player:
            self.mpv_player.command('set_property', 'wid', str(int(self.winId())))
        else:
            self.browser.resize(event.size())
        super().resizeEvent(event)

    def closeEvent(self, event):
        if self.mpv_player:
            self.mpv_player.terminate()  # Ensure MPV is closed properly
        event.accept()

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Site-Specific Browser")
    parser.add_argument("-l", "--link", default=DEFAULT_URL, help="URL to open")
    args = parser.parse_args()

    app = QApplication(sys.argv)
    app.setApplicationName("Pane Browser")
    window = Pane(args.link)

    app.exec_()
