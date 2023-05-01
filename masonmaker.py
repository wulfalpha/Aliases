#!/usr/bin/env python3
import argparse
import os
import sys
import time

parser = argparse.ArgumentParser(description='Create a Bash script to run a Java .jar file')
parser.add_argument('jar_file', type=str, help='Path to the Java .jar file')
args = parser.parse_args()

# Ask the user for a file name for the new Bash script
while True:
    script_name = input('Enter a file name for the new Bash script (without the .sh extension): ')
    if not script_name:
        print('Please enter a file name.')
    elif not script_name.isidentifier():
        print('The file name must be a valid identifier (no spaces or special characters).')
    else:
        script_file = script_name + '.sh'
        break

# Create a spinner while the script is being created
spinner = '|/-\\'
i = 0
print('Creating Bash script... ', end='')
while True:
    print(spinner[i % len(spinner)], end='\r')
    sys.stdout.flush()
    i += 1
    time.sleep(0.1)
    try:
        with open(script_file, 'w') as f:
            f.write('#!/bin/bash\n')
            f.write(f'java -jar {args.jar_file}\n')
    except PermissionError:
        continue
    else:
        break

# Set file permissions on the new Bash script
os.chmod(script_file, 0o755)

print(f'Bash script created: {script_file}')
