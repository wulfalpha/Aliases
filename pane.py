#!/usr/bin/env python3
import sys
from PyQt5.Qt import *
from PyQt5.QtWebEngineWidgets import *
from PyQt5.QtWidgets import QApplication
import argparse as qwarg


parser = qwarg.ArgumentParser()
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

app = QApplication(sys.argv)

web = QWebEngineView()

web.load(QUrl(qrl))

web.show()


sys.exit(app.exec_())
