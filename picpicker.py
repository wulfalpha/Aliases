#!/usr/bin/env python3
import shutil
import argparse
from pathlib import Path
import logging
import sys
from typing import Set, Dict, Tuple
import time


def setup_logging(verbose: bool) -> None:
    """Configure logging based on verbosity level."""
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(
        level=level,
        format="%(asctime)s - %(levelname)s - %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S"
    )


def get_image_extensions() -> Set[str]:
    """Return a set of common image file extensions."""
    return {
        ".jpg", ".jpeg", ".png", ".gif", ".bmp", ".tiff", ".tif", ".webp", 
        ".svg", ".heic", ".heif", ".raw", ".cr2", ".nef", ".arw", ".dng"
    }


def check_path_safety(path: Path) -> Tuple[bool, str]:
    """
    Check if a path contains potentially problematic characters or patterns.
    
    Args:
        path: The path to check
        
    Returns:
        Tuple of (is_safe, warning_message)
    """
    path_str = str(path)
    warnings = []
    
    # Check for spaces in the path
    if ' ' in path_str:
        warnings.append("spaces")
        
    # Check for other potentially problematic characters
    problematic_chars = ['$', '&', '#', '!', '?', '*', '\\', '"', "'", '`', '|', ';', '<', '>']
    found_chars = [c for c in problematic_chars if c in path_str]
    if found_chars:
        warnings.append(f"special characters ({', '.join(found_chars)})")
    
    # Check for leading/trailing whitespace
    if path.name != path.name.strip():
        warnings.append("leading or trailing whitespace")
    
    if warnings:
        warning_msg = f"Path contains {' and '.join(warnings)}: {path_str}"
        return False, warning_msg
    
    return True, ""


def process_images(
    source_dir: str, 
    dest_dir: str, 
    recursive: bool = False, 
    move: bool = False,
    dry_run: bool = False,
    follow_symlinks: bool = False
) -> Tuple[int, Dict[str, int]]:
    """
    Process (copy or move) image files from source directory to destination directory.

    Args:
        source_dir: Directory containing images to process
        dest_dir: Directory where images will be copied/moved to
        recursive: Whether to search subdirectories recursively
        move: If True, move files instead of copying them
        dry_run: If True, don't actually copy/move files, just simulate
        follow_symlinks: If True, follow symbolic links when searching for files

    Returns:
        Tuple of (count of processed files, dict of statistics)
                where statistics include counts of processed, renamed, errors, skipped,
                and problematic_names (files with spaces or special characters).
    """
    # Initialize paths and check for potential issues
    source_path = Path(source_dir)
    dest_dir_path = Path(dest_dir)
    
    # Check source directory name safety
    source_safe, source_warning = check_path_safety(source_path)
    if not source_safe:
        logging.warning(f"Source directory warning: {source_warning}")
    
    # Check destination directory name safety
    dest_safe, dest_warning = check_path_safety(dest_dir_path)
    if not dest_safe:
        logging.warning(f"Destination directory warning: {dest_warning}")
        
    # Create the destination directory if it doesn't exist and this isn't a dry run
    if not dry_run:
        try:
            dest_dir_path.mkdir(parents=True, exist_ok=True)
        except PermissionError:
            logging.error(f"Permission denied when creating destination directory '{dest_dir}'")
            return 0, {"errors": 1}
        except Exception as e:
            logging.error(f"Failed to create destination directory '{dest_dir}': {e}")
            return 0, {"errors": 1}
    if not source_path.exists():
        logging.error(f"Source directory '{source_dir}' does not exist")
        return 0, {"errors": 1}

    if not source_path.is_dir():
        logging.error(f"'{source_dir}' is not a directory")
        return 0, {"errors": 1}

    image_extensions = get_image_extensions()
    stats = {"processed": 0, "renamed": 0, "errors": 0, "skipped": 0, "problematic_names": 0}
    start_time = time.time()
    total_bytes = 0

    # Determine which glob pattern to use based on recursive flag
    glob_pattern = "**/*" if recursive else "*"

    # Get count of files for progress reporting
    files_to_process = []
    for file_path in source_path.glob(glob_pattern):
        # Handle symlinks based on the follow_symlinks flag
        if file_path.is_symlink() and not follow_symlinks:
            logging.debug(f"Skipping symlink: {file_path}")
            stats["skipped"] += 1
            continue
            
        if file_path.is_file() and file_path.suffix.lower() in image_extensions:
            files_to_process.append(file_path)

    if not files_to_process:
        logging.info(f"No image files found in {source_dir}")
        return 0, stats

    total_files = len(files_to_process)
    logging.info(f"Found {total_files} image files to process")

    # Loop through all files in the source directory
    for i, file_path in enumerate(files_to_process, 1):
        if i % 10 == 0 or i == total_files:  # Progress update every 10 files or on the last file
            progress_pct = (i / total_files) * 100
            elapsed = time.time() - start_time
            if elapsed > 0 and i > 1:
                files_per_sec = i / elapsed
                est_remaining = (total_files - i) / files_per_sec if files_per_sec > 0 else 0
                logging.info(f"Progress: {i}/{total_files} ({progress_pct:.1f}%) - Est. remaining: {est_remaining:.0f}s")
        
        # Check if file name has potential issues
        file_safe, file_warning = check_path_safety(file_path)
        if not file_safe:
            logging.warning(f"File name warning: {file_warning}")
            stats["problematic_names"] += 1

        # Build the destination path
        dest_path = dest_dir_path / file_path.name

        # Handle filename conflicts
        if not dry_run and dest_path.exists():
            base_name = file_path.stem
            suffix = file_path.suffix
            counter = 1
            while dest_path.exists():
                new_name = f"{base_name}_{counter}{suffix}"
                dest_path = dest_dir_path / new_name
                counter += 1

            logging.warning(f"Renamed '{file_path.name}' to '{dest_path.name}' to avoid overwrite")
            stats["renamed"] += 1

        try:
            operation = "Moving" if move else "Copying"
            if dry_run:
                operation = f"Would {operation.lower()}"
            
            file_size = file_path.stat().st_size
            total_bytes += file_size
            
            if not dry_run:
                # Copy or move the file to the destination directory
                if move:
                    shutil.move(str(file_path), str(dest_path))
                else:
                    shutil.copy2(str(file_path), str(dest_path))
            
            logging.info(f"{operation}: {file_path.name} → {dest_path} ({file_size / 1024:.1f} KB)")
            stats["processed"] += 1
        except PermissionError:
            logging.error(f"Permission denied for {file_path}")
            stats["errors"] += 1
        except FileNotFoundError:
            logging.error(f"File not found: {file_path}")
            stats["errors"] += 1
        except Exception as e:
            logging.error(f"Failed to process {file_path}: {e}")
            stats["errors"] += 1

    # Calculate and display summary
    elapsed_time = time.time() - start_time
    operation = "moved" if move else "copied"
    if dry_run:
        operation = f"would be {operation}"
    
    # Convert to MB for display
    total_mb = total_bytes / (1024 * 1024)
    
    logging.info(f"Operation complete: {stats['processed']} images {operation} to {dest_dir} ({total_mb:.2f} MB)")
    if elapsed_time > 0:
        mb_per_sec = total_mb / elapsed_time
        logging.info(f"Performance: {mb_per_sec:.2f} MB/s over {elapsed_time:.1f} seconds")
    
    if stats["errors"] > 0:
        logging.warning(f"Encountered {stats['errors']} errors during processing")
    if stats["renamed"] > 0:
        logging.info(f"Renamed {stats['renamed']} files to avoid conflicts")
    if stats["skipped"] > 0:
        logging.info(f"Skipped {stats['skipped']} files (symlinks)")
    if stats["problematic_names"] > 0:
        logging.warning(f"Processed {stats['problematic_names']} files with problematic names (spaces/special characters)"
                       f"\nThese may cause issues in some environments or scripts")
        
    return stats["processed"], stats


def main():
    # Set up argparse to handle command-line arguments
    parser = argparse.ArgumentParser(
        description="Process (copy or move) images from a source directory to a destination directory",
        epilog="Example: %(prog)s ~/Downloads -d ~/Pictures/vacation-pics -r --move"
    )
    parser.add_argument("source_dir", help="The source directory containing the images")
    parser.add_argument(
        "-d", "--dest_dir",
        help="The destination directory for the images (default: ~/Pictures/img-catch)"
    )
    parser.add_argument(
        "-r", "--recursive",
        action="store_true",
        help="Search subdirectories recursively for images"
    )
    parser.add_argument(
        "-m", "--move",
        action="store_true",
        help="Move files instead of copying them (default is to copy)"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Simulate the operation without actually moving or copying files"
    )
    parser.add_argument(
        "--follow-symlinks",
        action="store_true",
        help="Follow symbolic links when searching for files"
    )
    parser.add_argument(
        "-v", "--verbose",
        action="store_true",
        help="Enable verbose output"
    )
    args = parser.parse_args()

    # Setup logging based on verbosity flag
    setup_logging(args.verbose)

    # Set the destination directory to the default img-catch directory in Pictures if no directory is provided
    pictures_dir = Path.home() / "Pictures" / "img-catch"
    dest_dir = args.dest_dir or str(pictures_dir)

    try:
        # Call the process_images function with the user-provided arguments
        processed, stats = process_images(
            args.source_dir, 
            dest_dir, 
            args.recursive, 
            args.move, 
            args.dry_run,
            args.follow_symlinks
        )
        
        # Return appropriate exit code
        if stats["errors"] > 0:
            sys.exit(1)
        sys.exit(0)
    except KeyboardInterrupt:
        logging.info("Operation interrupted by user")
        sys.exit(130)  # Standard exit code for interrupt
    except Exception as e:
        logging.error(f"Unexpected error: {e}")
        if args.verbose:
            import traceback
            traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
