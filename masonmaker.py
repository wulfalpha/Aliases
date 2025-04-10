#!/usr/bin/env python3
import argparse
import os
import sys
import time
import re
import platform


def display_spinner(seconds, script_type):
    """Display a spinner for the specified number of seconds."""
    spinner = "|/-\\"
    end_time = time.time() + seconds
    i = 0

    while time.time() < end_time:
        print(f"Creating {script_type} script... {spinner[i % len(spinner)]}", end="\r")
        sys.stdout.flush()
        i += 1
        time.sleep(0.1)

    print(f"Creating {script_type} script... Done!      ")


def is_valid_filename(filename):
    """Check if the filename is valid for a script."""
    return bool(re.match(r"^[a-zA-Z0-9][a-zA-Z0-9._-]*$", filename))


def get_os_type():
    """Determine the operating system type."""
    system = platform.system().lower()
    if system == "windows":
        return "windows"
    elif system == "darwin":
        return "mac"
    else:
        return "linux"


def main():
    parser = argparse.ArgumentParser(
        description="Create a script to run a Java .jar file"
    )
    parser.add_argument("jar_file", type=str, help="Path to the Java .jar file")
    parser.add_argument(
        "--type",
        choices=["bat", "ps1", "sh"],
        help="Specify script type (bat/ps1 for Windows, sh for Linux/Mac)",
    )
    args = parser.parse_args()

    # Validate JAR file
    if not os.path.isfile(args.jar_file):
        print(f"Error: JAR file '{args.jar_file}' does not exist.", file=sys.stderr)
        return 1

    # Determine OS and script type
    os_type = get_os_type()

    if args.type:
        script_type = args.type
    else:
        if os_type == "windows":
            script_type = input("Choose script type for Windows (bat/ps1): ").lower()
            while script_type not in ["bat", "ps1"]:
                script_type = input("Please enter 'bat' or 'ps1': ").lower()
        else:
            script_type = "sh"

    if script_type == "bat":
        script_desc = "Batch"
        extension = ".bat"
    elif script_type == "ps1":
        script_desc = "PowerShell"
        extension = ".ps1"
    else:
        script_desc = "Bash"
        extension = ".sh"

    # Ask the user for a file name for the script
    while True:
        script_name = input(
            f"Enter a file name for the new {script_desc} script (without the {extension} extension): "
        )
        if not script_name:
            print("Please enter a file name.")
        elif not is_valid_filename(script_name):
            print("The file name contains invalid characters.")
        else:
            script_file = script_name + extension

            # Check if file already exists
            if os.path.exists(script_file):
                confirm = input(
                    f"File '{script_file}' already exists. Overwrite? (y/n): "
                )
                if confirm.lower() != "y":
                    continue
            break

    try:
        # Create the script based on type
        with open(script_file, "w") as f:
            if script_type == "bat":
                f.write("@echo off\r\n")
                f.write(f'java -jar "{args.jar_file}"\r\n')
                f.write("pause\r\n")
            elif script_type == "ps1":
                f.write(f'java -jar "{args.jar_file}"\r\n')
                f.write('Write-Host "Press any key to continue..."\r\n')
                f.write('$null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")\r\n')
            else:  # sh
                f.write("#!/bin/bash\n")
                f.write(f'java -jar "{args.jar_file}"\n')

        # Show a brief spinner
        display_spinner(0.5, script_desc)

        # Set file permissions for Linux/Mac
        if script_type == "sh":
            os.chmod(script_file, 0o755)

        print(f"{script_desc} script created: {script_file}")

        # Additional instructions for Windows
        if script_type == "ps1":
            print(
                "\nNote: To run PowerShell scripts, you might need to adjust your execution policy."
            )
            print(
                "You can run the script using: powershell -ExecutionPolicy Bypass -File "
                + script_file
            )

        return 0

    except PermissionError:
        print(
            f"Error: Permission denied when creating '{script_file}'.", file=sys.stderr
        )
        return 1
    except IOError as e:
        print(f"Error: Failed to create script: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
