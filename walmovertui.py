#!/usr/bin/env python3
"""
Walmover TUI - A terminal user interface for copying images by aspect ratio.

Uses the Textual library for cross-platform TUI support.
Install dependencies: pip install textual pillow
"""

import shutil
from pathlib import Path

from PIL import Image
from textual import work
from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.containers import Container, Horizontal, Vertical
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


class WalmoverApp(App):
    """TUI application for copying images by aspect ratio."""

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

    #ratio-select {
        width: 30;
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
        Binding("q", "quit", "Quit"),
        Binding("s", "start", "Start"),
        Binding("c", "cancel", "Cancel"),
        Binding("escape", "quit", "Quit"),
    ]

    def __init__(self):
        super().__init__()
        self.src_dir: Path | None = None
        self.dest_dir: Path | None = None
        self.processing = False
        self.cancelled = False
        self.stats = {
            "total": 0,
            "copied": 0,
            "skipped": 0,
            "failed": 0,
            "overwritten": 0,
        }

    def compose(self) -> ComposeResult:
        """Create the UI layout."""
        yield Header()

        with Container(id="main-container"):
            # Configuration section
            with Vertical(id="config-section"):
                with Horizontal(classes="config-row"):
                    yield Label("Source:", classes="config-label")
                    yield Input(
                        placeholder="Enter source directory path",
                        id="src-input",
                        classes="config-input",
                    )

                with Horizontal(classes="config-row"):
                    yield Label("Destination:", classes="config-label")
                    yield Input(
                        placeholder="Enter destination directory path",
                        id="dest-input",
                        classes="config-input",
                    )

                with Horizontal(classes="config-row"):
                    yield Label("Aspect Ratio:", classes="config-label")
                    yield Select(
                        [(name, name) for name in ASPECT_RATIOS.keys()],
                        value="Desktop (16:9)",
                        id="ratio-select",
                    )
                    yield Checkbox("Overwrite existing", id="overwrite-checkbox")

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
        src_input = self.query_one("#src-input", Input)
        dest_input = self.query_one("#dest-input", Input)

        src_path = Path(src_input.value.strip()).expanduser()
        dest_path = Path(dest_input.value.strip()).expanduser()

        # Validate paths
        if not src_path.is_dir():
            self.update_status(f"Error: Source '{src_path}' is not a valid directory")
            return

        if not dest_path.exists():
            try:
                dest_path.mkdir(parents=True, exist_ok=True)
            except Exception as e:
                self.update_status(f"Error creating destination: {e}")
                return

        self.src_dir = src_path
        self.dest_dir = dest_path

        # Get settings
        ratio_select = self.query_one("#ratio-select", Select)
        ratio_name = ratio_select.value
        self.current_ratio = ASPECT_RATIOS.get(ratio_name, (16, 9))

        overwrite_checkbox = self.query_one("#overwrite-checkbox", Checkbox)
        self.overwrite = overwrite_checkbox.value

        # Reset state
        self.cancelled = False
        self.stats = {
            "total": 0,
            "copied": 0,
            "skipped": 0,
            "failed": 0,
            "overwritten": 0,
        }

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

        start_btn = self.query_one("#start-button", Button)
        cancel_btn = self.query_one("#cancel-button", Button)
        quit_btn = self.query_one("#quit-button", Button)

        start_btn.disabled = processing
        cancel_btn.disabled = not processing
        quit_btn.disabled = processing

        src_input = self.query_one("#src-input", Input)
        dest_input = self.query_one("#dest-input", Input)
        ratio_select = self.query_one("#ratio-select", Select)
        overwrite_checkbox = self.query_one("#overwrite-checkbox", Checkbox)

        src_input.disabled = processing
        dest_input.disabled = processing
        ratio_select.disabled = processing
        overwrite_checkbox.disabled = processing

    def update_status(self, message: str) -> None:
        """Update the status label."""
        status_label = self.query_one("#status-label", Static)
        status_label.update(message)

    def update_stats(self) -> None:
        """Update the statistics display."""
        stats_label = self.query_one("#stats-label", Static)
        stats_text = (
            f"Total: {self.stats['total']} | "
            f"Copied: {self.stats['copied']} | "
            f"Overwritten: {self.stats['overwritten']} | "
            f"Skipped: {self.stats['skipped']} | "
            f"Failed: {self.stats['failed']}"
        )
        stats_label.update(stats_text)

    def update_progress(self, value: float) -> None:
        """Update the progress bar."""
        progress_bar = self.query_one("#progress-bar", ProgressBar)
        progress_bar.update(progress=value)

    def add_result(self, status: str, filename: str, dimensions: str) -> None:
        """Add a result row to the table."""
        table = self.query_one("#results-table", DataTable)
        table.add_row(status, filename, dimensions)
        # Scroll to the bottom to show latest
        table.scroll_end()

    @work(thread=True)
    def process_images(self) -> None:
        """Process images in a background thread."""
        try:
            image_files = [f for f in self.src_dir.iterdir() if is_valid_image(f)]
            total_files = len(image_files)
            self.stats["total"] = total_files

            if total_files == 0:
                self.call_from_thread(self.update_status, "No valid image files found")
                self.call_from_thread(self.update_progress, 100)
                self.call_from_thread(self.set_processing, False)
                return

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
                        try:
                            shutil.copy(file_path, dest_path)
                            if exists:
                                self.stats["overwritten"] += 1
                                status = "OVERWROTE"
                            else:
                                self.stats["copied"] += 1
                                status = "COPIED"
                            self.call_from_thread(
                                self.add_result,
                                status,
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

                # Update progress
                fraction = ((idx + 1) / total_files) * 100
                self.call_from_thread(self.update_progress, fraction)
                self.call_from_thread(
                    self.update_status, f"Processing: {file_path.name}"
                )
                self.call_from_thread(self.update_stats)

            # Processing complete
            self.call_from_thread(self.on_complete)

        except Exception as e:
            self.call_from_thread(self.update_status, f"Error: {e}")
            self.call_from_thread(self.set_processing, False)

    def on_complete(self) -> None:
        """Called when processing completes successfully."""
        self.update_status("Processing complete!")
        self.update_stats()
        self.update_progress(100)
        self.set_processing(False)
        self.notify(
            f"Done! Copied: {self.stats['copied']}, "
            f"Overwritten: {self.stats['overwritten']}, "
            f"Skipped: {self.stats['skipped']}",
            severity="information",
        )

    def on_cancelled(self) -> None:
        """Called when processing is cancelled."""
        processed = (
            self.stats["copied"] + self.stats["overwritten"] + self.stats["skipped"]
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
