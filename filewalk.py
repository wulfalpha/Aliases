#!/usr/bin/env python3
import argparse
import json
import logging
import subprocess
from pathlib import Path

# Constants
ERR_JSON_DECODE = "Error decoding JSON in {}."
ERR_FILE_NOT_FOUND = "File {} not found."
DEFAULT_CONFIG = "config.json"

# Logger setup
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def validate_config(config):
    if "default_directory" not in config:
        raise KeyError(
            "Invalid configuration. 'default_directory' not found in config file."
        )
    if not isinstance(config["default_directory"], str):
        raise TypeError("Invalid type: 'default_directory' should be a string.")

    if "file_associations" not in config:
        raise KeyError(
            "Invalid configuration. 'file_associations' not found in config file."
        )
    if not (isinstance(config["file_associations"], dict)):
        raise TypeError("Invalid type: 'file_associations' should be a dictionary.")


def load_config(config_file):
    try:
        with open(config_file, "r") as f:
            return json.load(f)
    except FileNotFoundError:
        raise FileNotFoundError(ERR_FILE_NOT_FOUND.format(config_file))
    except json.JSONDecodeError as e:
        logger.error(ERR_JSON_DECODE.format(config_file))
        logger.error(e)
        exit(1)


def open_file_with_program(program, file_path, total_files, index):
    try:
        progress = (index / total_files) * 100
        command = [program, str(file_path)]

        print(f"Executing: {command}")  # Add this line

        logger.info(
            f"Opening {file_path.name} with {program} [{index}/{total_files}] [{int(progress)}%]"
        )
        with subprocess.Popen(
            command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        ) as proc:
            proc.wait()
    except OSError as e:
        logger.error(f"Error while opening {file_path.name} with {program}: {str(e)}")


def traverse_and_process_files(start_dir: Path, program_methods, allowed_extensions):
    files = sorted(file for file in start_dir.glob("**/*") if file.is_file())
    total_files = len(files)
    # print total number of files
    print(f"Total files found: {total_files}")

    for index, file in enumerate(files, start=1):
        # print each file path
        print(f"Processing: {file}. Type: {file.suffix[1:]}")
        # rest of your code...
        if file.suffix[1:] in allowed_extensions:
            logger.info("Processing file in directory: " + str(file.parent))
            open_file_with_program(
                program_methods[file.suffix[1:]], file, total_files, index
            )
    logger.info("Exit..")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Process files in subdirectories")
    parser.add_argument(
        "-c", "--config", default=DEFAULT_CONFIG, help="Path to JSON config file"
    )
    args = parser.parse_args()
    try:
        config = load_config(args.config)
        validate_config(config)
        traverse_and_process_files(
            Path(config["default_directory"]),
            config["file_associations"],
            config["file_associations"].keys(),
        )
    except (FileNotFoundError, json.JSONDecodeError, KeyError, TypeError) as e:
        logger.error(e)
        exit(1)
