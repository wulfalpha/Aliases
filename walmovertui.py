#!/usr/bin/env python3
"""
Walmover TUI - A terminal user interface for copying images by aspect ratio.

Uses the Textual library for cross-platform TUI support.
Install dependencies: pip install textual pillow
"""

import json
import os
import shutil
import time
from pathlib import Path

from PIL import Image
from rich.text import Text
from textual import work
from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.containers import Container, Horizontal, Vertical
from textual.css.query import NoMatches
from textual.message import Message
from textual.suggester import Suggester
from textual.widgets import (
    Button,
    Checkbox,
    DataTable,
    Footer,
    Header,
    Input,
    Label,
    ProgressBar,
    Select,
    Static,
)

# --- Constants ---
VALID_EXTENSIONS = {".png", ".jpg", ".jpeg", ".webp", ".bmp", ".gif", ".tiff", ".tif"}
TOLERANCE = 0.05  # 5% tolerance for aspect ratio check

ASPECT_RATIOS = {
    "Desktop (16:9)": (16, 9),
    "Ultrawide (21:9)": (21, 9),
    "Standard (16:10)": (16, 10),
    "Mobile (9:16)": (9, 16),
}

CONFIG_PATH = Path.home() / ".config" / "walmover" / "tui.json"

# How often the worker is allowed to push progress/status to the UI.
UI_REFRESH_INTERVAL = 0.1

MAX_COMPLETION_HINTS = 8

TAB_HINT = "Tab completes a path (again to list matches), → accepts the ghost suggestion"


# --- Utility Functions ---
def is_valid_image(file_path: Path) -> bool:
    """Check if file is a valid image based on extension."""
    return file_path.is_file() and file_path.suffix.lower() in VALID_EXTENSIONS


def has_aspect_ratio(width: int, height: int, ratio: tuple[int, int]) -> bool:
    """Check if dimensions match the target aspect ratio within tolerance."""
    calculated_ratio = width / height
    expected_ratio = ratio[0] / ratio[1]
    return (
        (1 - TOLERANCE) * expected_ratio
        <= calculated_ratio
        <= (1 + TOLERANCE) * expected_ratio
    )


def directory_candidates(value: str, limit: int = 500) -> list[str]:
    """Return directory completions for a partially typed path.

    Completions keep whatever prefix the user typed (so "~/Pic" completes to
    "~/Pictures/" rather than the expanded home path) and end with a separator
    so completion can be chained.
    """
    if not value:
        return []

    if value == "~":
        return ["~/"]

    expanded = Path(value).expanduser()
    if value.endswith(os.sep):
        parent, stem = expanded, ""
    else:
        parent, stem = expanded.parent, expanded.name

    # The untouched part of what the user typed, e.g. "~/" in "~/Pic".
    prefix = value[: len(value) - len(stem)]

    try:
        entries = [entry for entry in parent.iterdir() if entry.is_dir()]
    except OSError:
        return []

    if not stem.startswith("."):
        entries = [entry for entry in entries if not entry.name.startswith(".")]

    lowered = stem.lower()
    matches = sorted(
        (entry.name for entry in entries if entry.name.lower().startswith(lowered)),
        key=str.lower,
    )
    return [f"{prefix}{name}{os.sep}" for name in matches[:limit]]


def path_state(value: str, *, allow_create: bool) -> tuple[str, str, str]:
    """Classify a typed path as (glyph, css class, explanation)."""
    if not value.strip():
        return "·", "path-empty", ""

    path = Path(value.strip()).expanduser()

    if path.is_dir():
        return "✓", "path-ok", ""
    if path.exists():
        return "✗", "path-bad", "not a directory"
    if not allow_create:
        return "✗", "path-bad", "does not exist"

    # Destination may be created, as long as an existing ancestor is writable.
    for parent in path.parents:
        if parent.exists():
            if parent.is_dir() and os.access(parent, os.W_OK):
                return "+", "path-new", "will be created"
            return "✗", "path-bad", f"cannot write in {parent}"
    return "✗", "path-bad", "does not exist"


def load_config() -> dict:
    """Load saved settings, ignoring a missing or unreadable config."""
    try:
        with CONFIG_PATH.open(encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, json.JSONDecodeError):
        return {}
    return data if isinstance(data, dict) else {}


def save_config(data: dict) -> None:
    """Persist settings, ignoring any failure to write."""
    try:
        CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
        with CONFIG_PATH.open("w", encoding="utf-8") as handle:
            json.dump(data, handle, indent=2)
    except OSError:
        pass


class DirectorySuggester(Suggester):
    """Inline ghost-text suggestion of the first matching directory."""

    def __init__(self) -> None:
        super().__init__(use_cache=False, case_sensitive=True)

    async def get_suggestion(self, value: str) -> str | None:
        candidates = directory_candidates(value, limit=1)
        return candidates[0] if candidates else None


class PathInput(Input):
    """An Input that completes directory paths on Tab."""

    BINDINGS = [Binding("tab", "complete", "Complete path", show=False)]

    class CompletionOptions(Message):
        """Posted when Tab is ambiguous and the choices should be shown."""

        def __init__(self, path_input: "PathInput", options: list[str]) -> None:
            self.path_input = path_input
            self.options = options
            super().__init__()

    def action_complete(self) -> None:
        candidates = directory_candidates(self.value)

        if not candidates:
            # Nothing to complete - fall through to normal Tab navigation.
            self.screen.focus_next()
            return

        common = os.path.commonprefix(candidates)
        completed = len(common) > len(self.value)
        if completed:
            self.value = common
            self.cursor_position = len(self.value)

        if len(candidates) > 1:
            # Still ambiguous - list what the path could become.
            self.post_message(self.CompletionOptions(self, candidates))
        elif completed:
            self.post_message(self.CompletionOptions(self, []))
        else:
            # Exactly one match, already typed in full - move on.
            self.screen.focus_next()


class WalmoverApp(App):
    """TUI application for copying images by aspect ratio."""

    TITLE = "Walmover"
    SUB_TITLE = "Copy images by aspect ratio"

    CSS = """
    Screen {
        layout: vertical;
    }

    #main-container {
        height: 100%;
        padding: 1;
    }

    #config-section {
        height: auto;
        margin-bottom: 1;
    }

    .config-row {
        height: auto;
        margin-bottom: 1;
    }

    .config-label {
        width: 15;
        padding-right: 1;
    }

    .config-input {
        width: 1fr;
    }

    .path-indicator {
        width: 3;
        content-align: center middle;
        text-style: bold;
    }

    .path-empty {
        color: $text-muted;
    }

    .path-ok {
        color: $success;
    }

    .path-new {
        color: $warning;
    }

    .path-bad {
        color: $error;
    }

    #ratio-select {
        width: 30;
    }

    #hint-label {
        height: auto;
        color: $text-muted;
    }

    #results-section {
        height: 1fr;
        border: solid green;
        margin-bottom: 1;
    }

    #results-table {
        height: 100%;
    }

    #progress-section {
        height: auto;
        margin-bottom: 1;
    }

    #progress-bar {
        width: 100%;
    }

    #status-label {
        height: auto;
        margin-top: 1;
        color: $text-muted;
    }

    #stats-label {
        height: auto;
        color: $success;
    }

    #button-section {
        height: auto;
        dock: bottom;
    }

    Button {
        margin-right: 1;
    }

    #start-button {
        background: $success;
    }

    #cancel-button {
        background: $warning;
    }

    #quit-button {
        background: $error;
    }

    .disabled {
        opacity: 0.5;
    }
    """

    BINDINGS = [
        Binding("ctrl+r", "start", "Run"),
        Binding("ctrl+t", "cancel", "Stop"),
        Binding("ctrl+q", "quit", "Quit"),
    ]

    def __init__(self):
        super().__init__()
        self.src_dir: Path | None = None
        self.dest_dir: Path | None = None
        self.processing = False
        self.cancelled = False
        self.current_ratio: tuple[int, int] = ASPECT_RATIOS["Desktop (16:9)"]
        self.overwrite = False
        self.dry_run = False
        self.config = load_config()
        self.stats = self.empty_stats()

    @staticmethod
    def empty_stats() -> dict[str, int]:
        return {
            "total": 0,
            "copied": 0,
            "skipped": 0,
            "failed": 0,
            "overwritten": 0,
            "unmatched": 0,
        }

    def compose(self) -> ComposeResult:
        """Create the UI layout."""
        yield Header()

        with Container(id="main-container"):
            # Configuration section
            with Vertical(id="config-section"):
                with Horizontal(classes="config-row"):
                    yield Label("Source:", classes="config-label")
                    yield PathInput(
                        placeholder="Enter source directory path",
                        id="src-input",
                        classes="config-input",
                        suggester=DirectorySuggester(),
                    )
                    yield Static("·", id="src-indicator", classes="path-indicator")

                with Horizontal(classes="config-row"):
                    yield Label("Destination:", classes="config-label")
                    yield PathInput(
                        placeholder="Enter destination directory path",
                        id="dest-input",
                        classes="config-input",
                        suggester=DirectorySuggester(),
                    )
                    yield Static("·", id="dest-indicator", classes="path-indicator")

                with Horizontal(classes="config-row"):
                    yield Label("Aspect Ratio:", classes="config-label")
                    yield Select(
                        [(name, name) for name in ASPECT_RATIOS.keys()],
                        value="Desktop (16:9)",
                        allow_blank=False,
                        id="ratio-select",
                    )
                    yield Checkbox("Overwrite existing", id="overwrite-checkbox")
                    yield Checkbox("Dry run", id="dryrun-checkbox")

                yield Static(TAB_HINT, id="hint-label")

            # Results section
            with Container(id="results-section"):
                yield DataTable(id="results-table")

            # Progress section
            with Vertical(id="progress-section"):
                yield ProgressBar(id="progress-bar", total=100, show_eta=False)
                yield Static("Ready", id="status-label")
                yield Static("", id="stats-label")

            # Button section
            with Horizontal(id="button-section"):
                yield Button("Start", id="start-button", variant="success")
                yield Button(
                    "Cancel", id="cancel-button", variant="warning", disabled=True
                )
                yield Button("Quit", id="quit-button", variant="error")

        yield Footer()

    def on_mount(self) -> None:
        """Initialize the app on mount."""
        table = self.query_one("#results-table", DataTable)
        table.add_columns("Status", "Filename", "Dimensions")
        table.cursor_type = "row"

        self.restore_config()
        self.refresh_indicators()
        self.query_one("#src-input", PathInput).focus()

    def restore_config(self) -> None:
        """Repopulate the form from the saved config."""
        src = self.config.get("src")
        dest = self.config.get("dest")
        ratio = self.config.get("ratio")

        if isinstance(src, str):
            self.query_one("#src-input", PathInput).value = src
        if isinstance(dest, str):
            self.query_one("#dest-input", PathInput).value = dest
        if ratio in ASPECT_RATIOS:
            self.query_one("#ratio-select", Select).value = ratio

        self.query_one("#overwrite-checkbox", Checkbox).value = bool(
            self.config.get("overwrite", False)
        )
        self.query_one("#dryrun-checkbox", Checkbox).value = bool(
            self.config.get("dry_run", False)
        )

    def store_config(self) -> None:
        """Remember the current form values for the next run."""
        save_config(
            {
                "src": self.query_one("#src-input", PathInput).value,
                "dest": self.query_one("#dest-input", PathInput).value,
                "ratio": self.query_one("#ratio-select", Select).value,
                "overwrite": self.query_one("#overwrite-checkbox", Checkbox).value,
                "dry_run": self.query_one("#dryrun-checkbox", Checkbox).value,
            }
        )

    def on_unmount(self) -> None:
        """Persist settings on exit."""
        try:
            self.store_config()
        except NoMatches:
            # Widgets already torn down - nothing worth saving.
            pass

    # --- Path validation feedback ---
    def refresh_indicators(self) -> None:
        """Update the ✓/✗ markers and the Start button's enabled state."""
        src_value = self.query_one("#src-input", PathInput).value
        dest_value = self.query_one("#dest-input", PathInput).value

        src_glyph, src_class, src_note = path_state(src_value, allow_create=False)
        dest_glyph, dest_class, dest_note = path_state(dest_value, allow_create=True)

        self.set_indicator("#src-indicator", src_glyph, src_class)
        self.set_indicator("#dest-indicator", dest_glyph, dest_class)

        notes = []
        if src_note:
            notes.append(f"Source: {src_note}")
        if dest_note:
            notes.append(f"Destination: {dest_note}")
        self.set_hint("  |  ".join(notes) if notes else TAB_HINT)

        if not self.processing:
            ready = src_class == "path-ok" and dest_class in ("path-ok", "path-new")
            self.query_one("#start-button", Button).disabled = not ready

    def set_indicator(self, selector: str, glyph: str, css_class: str) -> None:
        indicator = self.query_one(selector, Static)
        indicator.set_classes(f"path-indicator {css_class}")
        indicator.update(glyph)

    def set_hint(self, message: str) -> None:
        self.query_one("#hint-label", Static).update(message)

    def on_input_changed(self, event: Input.Changed) -> None:
        """Re-validate whenever a path changes."""
        if event.input.id in ("src-input", "dest-input"):
            self.refresh_indicators()

    def on_path_input_completion_options(
        self, event: PathInput.CompletionOptions
    ) -> None:
        """Show the candidate directories when Tab completion is ambiguous."""
        if not event.options:
            self.refresh_indicators()
            return

        names = [Path(option.rstrip(os.sep)).name for option in event.options]
        shown = names[:MAX_COMPLETION_HINTS]
        more = len(names) - len(shown)
        text = "  ".join(shown)
        if more:
            text += f"  … (+{more} more)"
        self.set_hint(text)

    def on_input_submitted(self, event: Input.Submitted) -> None:
        """Enter moves down the form, and starts the run from the last field."""
        if event.input.id == "src-input":
            self.query_one("#dest-input", PathInput).focus()
        elif event.input.id == "dest-input":
            self.action_start()

    def on_button_pressed(self, event: Button.Pressed) -> None:
        """Handle button press events."""
        button_id = event.button.id

        if button_id == "start-button":
            self.action_start()
        elif button_id == "cancel-button":
            self.action_cancel()
        elif button_id == "quit-button":
            self.action_quit()

    def action_start(self) -> None:
        """Start processing images."""
        if self.processing:
            return

        # Get input values
        src_input = self.query_one("#src-input", PathInput)
        dest_input = self.query_one("#dest-input", PathInput)

        src_path = Path(src_input.value.strip()).expanduser()
        dest_path = Path(dest_input.value.strip()).expanduser()

        # Get settings
        ratio_name = self.query_one("#ratio-select", Select).value
        self.current_ratio = ASPECT_RATIOS.get(ratio_name, (16, 9))
        self.overwrite = self.query_one("#overwrite-checkbox", Checkbox).value
        self.dry_run = self.query_one("#dryrun-checkbox", Checkbox).value

        # Validate paths
        if not src_path.is_dir():
            self.update_status(f"Error: Source '{src_path}' is not a valid directory")
            return

        if not dest_path.exists() and not self.dry_run:
            try:
                dest_path.mkdir(parents=True, exist_ok=True)
            except Exception as e:
                self.update_status(f"Error creating destination: {e}")
                return

        self.src_dir = src_path
        self.dest_dir = dest_path
        self.store_config()

        # Reset state
        self.cancelled = False
        self.stats = self.empty_stats()

        # Clear results table
        table = self.query_one("#results-table", DataTable)
        table.clear()

        # Update UI state
        self.set_processing(True)

        # Start processing in background
        self.process_images()

    def action_cancel(self) -> None:
        """Cancel the current processing operation."""
        if self.processing:
            self.cancelled = True
            self.update_status("Cancelling...")

    def action_quit(self) -> None:
        """Quit the application."""
        if self.processing:
            self.notify(
                "Processing in progress. Cancel first or wait.", severity="warning"
            )
            return
        self.exit()

    def set_processing(self, processing: bool) -> None:
        """Update UI state based on processing status."""
        self.processing = processing

        self.query_one("#start-button", Button).disabled = processing
        self.query_one("#cancel-button", Button).disabled = not processing
        self.query_one("#quit-button", Button).disabled = processing

        for selector, widget_type in (
            ("#src-input", PathInput),
            ("#dest-input", PathInput),
            ("#ratio-select", Select),
            ("#overwrite-checkbox", Checkbox),
            ("#dryrun-checkbox", Checkbox),
        ):
            self.query_one(selector, widget_type).disabled = processing

        if not processing:
            self.refresh_indicators()

    def update_status(self, message: str) -> None:
        """Update the status label."""
        status_label = self.query_one("#status-label", Static)
        status_label.update(message)

    def update_stats(self) -> None:
        """Update the statistics display."""
        stats_label = self.query_one("#stats-label", Static)
        prefix = "DRY RUN | " if self.dry_run else ""
        stats_text = (
            f"{prefix}"
            f"Total: {self.stats['total']} | "
            f"Copied: {self.stats['copied']} | "
            f"Overwritten: {self.stats['overwritten']} | "
            f"Skipped: {self.stats['skipped']} | "
            f"No match: {self.stats['unmatched']} | "
            f"Failed: {self.stats['failed']}"
        )
        stats_label.update(stats_text)

    def start_progress(self, total: int) -> None:
        """Reset the progress bar for a run of `total` files."""
        progress_bar = self.query_one("#progress-bar", ProgressBar)
        progress_bar.update(total=max(total, 1), progress=0)

    def update_progress(self, value: float) -> None:
        """Update the progress bar."""
        progress_bar = self.query_one("#progress-bar", ProgressBar)
        progress_bar.update(progress=value)

    def add_result(self, status: str, filename: str, dimensions: str) -> None:
        """Add a result row to the table."""
        styles = {
            "COPIED": "green",
            "OVERWROTE": "yellow",
            "SKIPPED": "dim",
            "FAILED": "red",
        }
        style = styles.get(status.removeprefix("WOULD ").strip(), "")
        table = self.query_one("#results-table", DataTable)
        table.add_row(Text(status, style=style), filename, dimensions)
        # Scroll to the bottom to show latest
        table.scroll_end()

    @work(thread=True)
    def process_images(self) -> None:
        """Process images in a background thread."""
        try:
            image_files = sorted(
                (f for f in self.src_dir.iterdir() if is_valid_image(f)),
                key=lambda path: path.name.lower(),
            )
            total_files = len(image_files)
            self.stats["total"] = total_files
            self.call_from_thread(self.start_progress, total_files)

            if total_files == 0:
                self.call_from_thread(self.update_status, "No valid image files found")
                self.call_from_thread(self.update_progress, 1)
                self.call_from_thread(self.set_processing, False)
                return

            last_ui_update = 0.0

            for idx, file_path in enumerate(image_files):
                # Check for cancellation
                if self.cancelled:
                    self.call_from_thread(self.on_cancelled)
                    return

                try:
                    with Image.open(file_path) as img:
                        width, height = img.size
                except Exception as e:
                    self.stats["failed"] += 1
                    self.call_from_thread(
                        self.add_result, "FAILED", file_path.name, f"Error: {e}"
                    )
                    continue

                if has_aspect_ratio(width, height, ratio=self.current_ratio):
                    dest_path = self.dest_dir / file_path.name
                    exists = dest_path.exists()
                    should_copy = not exists or self.overwrite

                    if should_copy:
                        status = "OVERWROTE" if exists else "COPIED"
                        try:
                            if not self.dry_run:
                                shutil.copy(file_path, dest_path)
                            if exists:
                                self.stats["overwritten"] += 1
                            else:
                                self.stats["copied"] += 1
                            self.call_from_thread(
                                self.add_result,
                                f"WOULD {status}" if self.dry_run else status,
                                file_path.name,
                                f"{width}x{height}",
                            )
                        except Exception as e:
                            self.stats["failed"] += 1
                            self.call_from_thread(
                                self.add_result,
                                "FAILED",
                                file_path.name,
                                f"Copy error: {e}",
                            )
                    else:
                        self.stats["skipped"] += 1
                        self.call_from_thread(
                            self.add_result,
                            "SKIPPED",
                            file_path.name,
                            f"{width}x{height} (exists)",
                        )
                else:
                    self.stats["unmatched"] += 1

                # Update progress, throttled so huge directories stay responsive
                now = time.monotonic()
                if now - last_ui_update >= UI_REFRESH_INTERVAL or idx + 1 == total_files:
                    last_ui_update = now
                    self.call_from_thread(self.update_progress, idx + 1)
                    self.call_from_thread(
                        self.update_status,
                        f"Processing ({idx + 1}/{total_files}): {file_path.name}",
                    )
                    self.call_from_thread(self.update_stats)

            # Processing complete
            self.call_from_thread(self.on_complete)

        except Exception as e:
            self.call_from_thread(self.update_status, f"Error: {e}")
            self.call_from_thread(self.set_processing, False)

    def on_complete(self) -> None:
        """Called when processing completes successfully."""
        prefix = "Dry run complete" if self.dry_run else "Processing complete"
        self.update_status(f"{prefix}!")
        self.update_stats()
        self.update_progress(self.stats["total"])
        self.set_processing(False)
        verb = "Would copy" if self.dry_run else "Copied"
        self.notify(
            f"Done! {verb}: {self.stats['copied']}, "
            f"Overwritten: {self.stats['overwritten']}, "
            f"Skipped: {self.stats['skipped']}",
            severity="information",
        )

    def on_cancelled(self) -> None:
        """Called when processing is cancelled."""
        processed = (
            self.stats["copied"]
            + self.stats["overwritten"]
            + self.stats["skipped"]
            + self.stats["unmatched"]
        )
        self.update_status(
            f"Cancelled - Processed {processed} of {self.stats['total']} files"
        )
        self.update_stats()
        self.set_processing(False)
        self.notify("Processing cancelled", severity="warning")


def main():
    """Entry point for the TUI application."""
    app = WalmoverApp()
    app.run()


if __name__ == "__main__":
    main()
