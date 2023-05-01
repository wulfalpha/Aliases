#!/usr/bin/env python3
import sys
from PyQt5.QtCore import QUrl, QSize, Qt
from PyQt5.QtGui import QIcon, QDesktopServices
from PyQt5.QtWebEngineWidgets import QWebEngineView
from PyQt5.QtWidgets import QApplication, QMainWindow, QDesktopWidget
import argparse

class Pane(QMainWindow):
    """Class to build the Site specific Browser"""
    def __init__(self, qrl):
        super(Pane, self).__init__()

        # Get the screen resolution and calculate a comfortable window size
        screen_size = QDesktopWidget().availableGeometry().size()
        window_size = QSize(int(screen_size.width() * 0.8), int(screen_size.height() * 0.8))

        self.setMinimumSize(window_size)
        self.setWindowIcon(QIcon('hidive.png'))
        self.setWindowTitle(f"{qrl} - Pane")

        self.browser = QWebEngineView()
        try:
            self.browser.load(QUrl(qrl))
        except Exception as e:
            print(e)

        self.setCentralWidget(self.browser)
        self.show()


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument("-l", "--link", default="https://search.brave.com", help="hyperlink to access")
    args = parser.parse_args()
    qrl = args.link

    app = QApplication(sys.argv)
    app.setApplicationName(f"{qrl} - Pane")
    window = Pane(qrl)

    app.exec_()
