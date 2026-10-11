#!/usr/bin/env python3
"""GTK duplicate-image and incorrect-extension finder."""
import hashlib
import logging
import os
from collections import defaultdict
from pathlib import Path
from threading import Event, Thread

import gi
import imagehash
from PIL import Image, UnidentifiedImageError
from send2trash import send2trash

gi.require_version("Gtk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import GdkPixbuf, GLib, Gtk

LOG = logging.getLogger(__name__)
PHASH_LIMIT = 6
FORMATS = {
    "JPEG": {".jpg", ".jpeg", ".jpe", ".jfif"}, "PNG": {".png"},
    "GIF": {".gif"}, "WEBP": {".webp"}, "BMP": {".bmp", ".dib"},
    "TIFF": {".tif", ".tiff"}, "ICO": {".ico"}, "AVIF": {".avif"},
}
IMAGE_SUFFIXES = set().union(*FORMATS.values())
PREFERRED = {fmt: min(exts, key=len) for fmt, exts in FORMATS.items()}


class DupSleuth(Gtk.Window):
    def __init__(self):
        super().__init__(title="Dup Sleuth")
        self.set_default_size(950, 680)
        self.set_border_width(10)
        self.directory = None
        self.cancel = Event()
        self.worker = None

        self.label = Gtk.Label(label="Choose a directory to scan.", xalign=0)
        self.notebook = Gtk.Notebook()
        self.notebook.set_vexpand(True)
        self.stores, self.views = {}, {}
        for key, title in (("exact", "Exact duplicates"),
                           ("similar", "Similar images"),
                           ("extension", "Extension problems")):
            store = Gtk.ListStore(GdkPixbuf.Pixbuf, str, str, str)
            view = Gtk.IconView.new_with_model(store)
            view.set_pixbuf_column(0); view.set_text_column(1)
            view.set_item_width(220)
            view.set_selection_mode(Gtk.SelectionMode.MULTIPLE)
            view.connect("selection-changed", self.selection_changed)
            scroll = Gtk.ScrolledWindow(); scroll.add(view)
            self.notebook.append_page(scroll, Gtk.Label(label=title))
            self.stores[key], self.views[key] = store, view

        self.progress = Gtk.ProgressBar(show_text=True, text="Ready")
        self.status = Gtk.Statusbar()
        self.status_id = self.status.get_context_id("status")
        self.choose = Gtk.Button(label="Select Source Directory")
        self.choose.connect("clicked", self.select_directory)
        self.trash = Gtk.Button(label="Move Selected to Trash")
        self.trash.connect("clicked", self.trash_selected)
        self.rename = Gtk.Button(label="Fix Selected Extensions")
        self.rename.connect("clicked", self.rename_selected)
        close = Gtk.Button(label="Close"); close.connect("clicked", self.quit)
        buttons = Gtk.Box(spacing=6)
        for button in (self.choose, self.trash, self.rename, close):
            buttons.pack_start(button, True, True, 0)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        for widget, expand in ((self.label, False), (self.notebook, True),
                               (self.progress, False), (self.status, False),
                               (buttons, False)):
            box.pack_start(widget, expand, expand, 0)
        self.add(box)
        self.notebook.connect("switch-page", self.selection_changed)
        self.selection_changed()

    def current(self):
        key = ("exact", "similar", "extension")[self.notebook.get_current_page()]
        return key, self.stores[key], self.views[key]

    def selected(self):
        key, store, view = self.current()
        return key, store, [(path, store[path]) for path in view.get_selected_items()]

    def selection_changed(self, *_args):
        key, _store, rows = self.selected()
        busy = bool(self.worker and self.worker.is_alive())
        self.trash.set_sensitive(bool(rows) and not busy)
        self.rename.set_sensitive(key == "extension" and not busy and
                                  any(row[3] for _, row in rows))

    def select_directory(self, _button):
        dialog = Gtk.FileChooserDialog("Choose a directory", self,
                                       Gtk.FileChooserAction.SELECT_FOLDER)
        dialog.add_buttons(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
                           Gtk.STOCK_OPEN, Gtk.ResponseType.OK)
        if dialog.run() == Gtk.ResponseType.OK:
            self.directory = Path(dialog.get_filename())
            dialog.destroy(); self.start_scan(); return
        dialog.destroy()

    def start_scan(self):
        if self.worker and self.worker.is_alive(): self.cancel.set()
        self.cancel = Event()
        for store in self.stores.values(): store.clear()
        self.choose.set_sensitive(False)
        self.progress.set_fraction(0); self.progress.set_text("Discovering files...")
        self.label.set_text(f"Scanning: {self.directory}")
        self.set_status("Scanning does not modify files.")
        self.worker = Thread(target=scan_images,
                             args=(self.directory, self, self.cancel), daemon=True)
        self.worker.start(); self.selection_changed()

    def add_result(self, category, path, text, extension=""):
        try:
            pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(str(path), 128, 128, True)
        except GLib.Error:
            pixbuf = None
        self.stores[category].append([pixbuf, text, str(path), extension])
        return False

    def set_progress(self, text, fraction):
        self.progress.set_text(text); self.progress.set_fraction(fraction); return False

    def set_status(self, text):
        self.status.remove_all(self.status_id); self.status.push(self.status_id, text)
        return False

    def finished(self, summary, cancelled=False):
        self.worker = None
        self.choose.set_sensitive(True)
        self.progress.set_fraction(0 if cancelled else 1)
        self.progress.set_text("Cancelled" if cancelled else "Done")
        self.label.set_text(summary)
        self.set_status("Scan cancelled." if cancelled else
                        "Select results to rename or move to trash.")
        self.selection_changed(); return False

    def confirm(self, title, detail):
        dialog = Gtk.MessageDialog(transient_for=self, modal=True,
            message_type=Gtk.MessageType.WARNING, buttons=Gtk.ButtonsType.CANCEL,
            text=title)
        dialog.format_secondary_text(detail)
        dialog.add_button("Continue", Gtk.ResponseType.OK)
        answer = dialog.run() == Gtk.ResponseType.OK; dialog.destroy(); return answer

    def trash_selected(self, _button):
        _key, store, rows = self.selected()
        if not rows or not self.confirm(f"Move {len(rows)} file(s) to trash?",
                                        "Review selected paths before continuing."): return
        moved = 0
        for tree_path, row in sorted(rows, reverse=True, key=lambda item: item[0]):
            try:
                send2trash(row[2]); store.remove(store.get_iter(tree_path)); moved += 1
            except OSError as error: LOG.error("Cannot trash %s: %s", row[2], error)
        self.set_status(f"Moved {moved} file(s) to trash."); self.selection_changed()

    def rename_selected(self, _button):
        key, store, rows = self.selected(); rows = [(p, r) for p, r in rows if r[3]]
        if key != "extension" or not rows or not self.confirm(
                f"Rename {len(rows)} file(s)?", "Existing destinations will be skipped."): return
        count = 0
        for tree_path, row in sorted(rows, reverse=True, key=lambda item: item[0]):
            source = Path(row[2]); destination = source.with_suffix(row[3])
            try:
                if destination.exists(): raise FileExistsError(destination)
                source.rename(destination); store.remove(store.get_iter(tree_path)); count += 1
            except OSError as error: LOG.error("Cannot rename %s: %s", source, error)
        self.set_status(f"Renamed {count} file(s)."); self.selection_changed()

    def quit(self, _widget):
        self.cancel.set(); Gtk.main_quit()


def inspect(path):
    try:
        with Image.open(path) as image:
            return image.format, imagehash.phash(image.convert("RGB"))
    except (UnidentifiedImageError, OSError, ValueError):
        return None, None


def digest(path, cancel):
    result = hashlib.sha256()
    with path.open("rb") as stream:
        while data := stream.read(1024 * 1024):
            if cancel.is_set(): return None
            result.update(data)
    return result.hexdigest()


def scan_images(directory, app, cancel):
    files = [Path(root) / name for root, _dirs, names in os.walk(directory)
             for name in names if not (Path(root) / name).is_symlink()]
    records, problems = [], 0
    for number, path in enumerate(files, 1):
        if cancel.is_set(): GLib.idle_add(app.finished, "Scan cancelled.", True); return
        fmt, phash = inspect(path); suffix = path.suffix.lower()
        if fmt and phash is not None:
            try: records.append((path, path.stat().st_size, phash))
            except OSError: continue
            if fmt in FORMATS and suffix not in FORMATS[fmt]:
                ext = PREFERRED[fmt]; problems += 1
                GLib.idle_add(app.add_result, "extension", path,
                    f"{path.name}\nDetected {fmt}; expected {ext}\n{path.parent}", ext)
        elif suffix in IMAGE_SUFFIXES:
            problems += 1
            GLib.idle_add(app.add_result, "extension", path,
                          f"{path.name}\nNot a readable image\n{path.parent}", "")
        GLib.idle_add(app.set_progress, f"Inspecting {number}/{len(files)}",
                      number / len(files) if files else 1)

    sizes = defaultdict(list)
    for record in records: sizes[record[1]].append(record)
    groups, exact_paths = [], set()
    for candidates in sizes.values():
        if len(candidates) < 2: continue
        hashes = defaultdict(list)
        for record in candidates:
            try: value = digest(record[0], cancel)
            except OSError: continue
            if value: hashes[value].append(record)
        for group in hashes.values():
            if len(group) > 1:
                groups.append(group); exact_paths.update(item[0] for item in group)
    for group_no, group in enumerate(groups, 1):
        for path, size, _phash in group:
            GLib.idle_add(app.add_result, "exact", path,
                f"Group {group_no}: {path.name}\nExact match, {size:,} bytes\n{path.parent}", "")

    unique = [record for record in records if record[0] not in exact_paths]
    pairs = []
    for index, left in enumerate(unique):
        if cancel.is_set(): GLib.idle_add(app.finished, "Scan cancelled.", True); return
        for right in unique[index + 1:]:
            distance = left[2] - right[2]
            if distance <= PHASH_LIMIT: pairs.append((left, right, distance))
    for pair_no, (left, right, distance) in enumerate(pairs, 1):
        for record, other in ((left, right), (right, left)):
            path = record[0]
            GLib.idle_add(app.add_result, "similar", path,
                f"Pair {pair_no}: {path.name}\nSimilar to {other[0].name} "
                f"(distance {distance})\n{path.parent}", "")
    GLib.idle_add(app.finished, f"Found {len(groups)} exact group(s), "
                  f"{len(pairs)} similar pair(s), and {problems} extension problem(s).")


def main():
    """Launch the Dup Sleuth GTK application."""
    logging.basicConfig(level=logging.INFO,
                        format="%(asctime)s - %(levelname)s - %(message)s")
    window = DupSleuth(); window.connect("destroy", window.quit)
    window.show_all(); Gtk.main()


if __name__ == "__main__":
    main()
