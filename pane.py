#!/usr/bin/env python3
import sys
from PyQt5.Qt import *
from PyQt5.QtWebEngineWidgets import *
from PyQt5.QtWidgets import QApplication
import argparse


class Pane(QMainWindow):
    """Clas to build the Site specific Browser"""
    def __init__(self, *args, **kwargs):
        super(Pane, self).__init__(*args, **kwargs)

        width = 1280
        height = 720
        self.setMinimumSize(width, height)

        self.browser = QWebEngineView()
        self.browser.load(QUrl(qrl))

        self.setCentralWidget(self.browser)

        self.show()


    def run(self):
        print(self.qrl)
        return 0




if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument("-l", "--link", default="https://search.brave.com", help="hyperlink to access")
    args = parser.parse_args()
    qrl = args.link

    app = QApplication(sys.argv)
    app.setApplicationName(f"{qrl} - Pane")
    window = Pane()

    app.exec_()
