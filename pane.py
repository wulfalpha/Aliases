#!/usr/bin/env python3
import sys
from PyQt5.Qt import *
from PyQt5.QtWebEngineWidgets import *
from PyQt5.QtWidgets import QApplication
import argparse


parser = argparse.ArgumentParser()
def key():
    print("""
    Usage: pane [options]
     -l, --Link {url}  Pass Pane a hyperlink
     -h, --Help        This page
    """)

parser.add_argument("-l", "--Link", help = "pass Pane a hyperlink")

args = parser.parse_args()

if args.Link:
    qrl = args.Link
else:
    key()
    qrl = "https://search.brave.com/"

class Pane(QMainWindow):
    def __init__(self, *args, **kwargs):
        super(Pane, self).__init__(*args, **kwargs)

        width = 1280
        height = 720
        self.setMinimumSize(width, height)

        self.browser = QWebEngineView()
        self.browser.load(QUrl(qrl))

        self.setCentralWidget(self.browser)

        self.show()


app = QApplication(sys.argv)
app.setApplicationName(f"{qrl} - Pane")
window = Pane()

app.exec_()
