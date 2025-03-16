#!/usr/bin/env python
"""A program to make site-specific browsers for the pane browser."""
import argparse
import os
import sys
import json
import shutil
import subprocess
from pathlib import Path
import requests
from urllib.parse import urlparse, urljoin
from bs4 import BeautifulSoup

# Define paths
HOME = Path.home()
DESKTOP_PATH = HOME / ".local" / "share" / "applications"
ICON_PATH = HOME / ".local" / "share" / "icons" / "pane"
CONFIG_PATH = HOME / ".config" / "pane"
DESKTOP_FILE_EXT = ".desktop"

# Ensure directories exist
DESKTOP_PATH.mkdir(parents=True, exist_ok=True)
ICON_PATH.mkdir(parents=True, exist_ok=True)
CONFIG_PATH.mkdir(parents=True, exist_ok=True)

def greeting():
    """Prints a greeting message."""
    print("╔════════════════════════════════════════╗")
    print("║ Welcome to Window Maker for Pane       ║")
    print("║ Create minimal site-specific browsers  ║")
    print("╚════════════════════════════════════════╝")


def is_valid_url(url):
    """Checks if the given URL is valid."""
    if not url:
        return False
    
    # Add https:// if no scheme is present
    if not url.startswith(('http://', 'https://')):
        url = 'https://' + url
        
    parsed_url = urlparse(url)
    return bool(parsed_url.scheme) and bool(parsed_url.netloc)


def find_best_icon(url, name):
    """Finds the best icon from the website: favicon.ico, apple-touch-icon, or any icon in the page."""
    if not is_valid_url(url):
        print("Invalid URL for icon retrieval")
        return None
        
    # Ensure URL has scheme
    if not url.startswith(('http://', 'https://')):
        url = 'https://' + url
        
    try:
        # Parse the base URL
        parsed_url = urlparse(url)
        base_url = f"{parsed_url.scheme}://{parsed_url.netloc}"
        
        # Try to get the page content
        headers = {
            "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"
        }
        response = requests.get(url, headers=headers, timeout=10)
        response.raise_for_status()
        
        # Create a set to store potential icon URLs
        icon_urls = []
        
        # Try to parse the HTML and find link tags with rel="icon" or rel="apple-touch-icon"
        soup = BeautifulSoup(response.text, 'html.parser')
        
        # Look for apple-touch-icon first (usually higher quality)
        for link in soup.find_all('link', rel=lambda r: r and ('apple-touch-icon' in r.lower())):
            if 'href' in link.attrs:
                href = link['href']
                icon_urls.append(urljoin(base_url, href))
        
        # Then look for other icons
        for link in soup.find_all('link', rel=lambda r: r and ('icon' in r.lower() and 'apple-touch-icon' not in r.lower())):
            if 'href' in link.attrs:
                href = link['href']
                icon_urls.append(urljoin(base_url, href))
        
        # Add favicon.ico as fallback
        icon_urls.append(urljoin(base_url, "favicon.ico"))
        
        # Try each icon URL until one works
        for icon_url in icon_urls:
            try:
                icon_response = requests.get(icon_url, headers=headers, timeout=5)
                if icon_response.status_code == 200 and len(icon_response.content) > 100:
                    # Determine file extension from Content-Type or URL
                    content_type = icon_response.headers.get('Content-Type', '')
                    
                    if 'png' in content_type.lower():
                        ext = '.png'
                    elif 'ico' in content_type.lower() or icon_url.endswith('.ico'):
                        ext = '.ico'
                    elif 'svg' in content_type.lower():
                        ext = '.svg'
                    else:
                        ext = '.png'  # Default to PNG
                    
                    # Create the icon file path
                    icon_file = os.path.join(ICON_PATH, f"{name}{ext}")
                    
                    # Write the icon content to file
                    with open(icon_file, "wb") as f:
                        f.write(icon_response.content)
                    
                    print(f"✓ Icon downloaded successfully from {icon_url}")
                    return icon_file
            except Exception as e:
                continue
        
        print("ⓘ Could not find a suitable icon")
        return None
        
    except requests.exceptions.RequestException as e:
        print(f"ⓘ Failed to download icon: {e}")
        return None


def create_pane_profile(name, url, icon=None, custom_settings=None):
    """Creates a profile configuration for Pane."""
    profile_config = {
        "url": url,
        "size": [0.8, 0.8],
        "zoom_factor": 1.0,
        "enable_navigation": False,
        "enable_dev_tools": False,
        "enable_js": True,
        "enable_cookies": True
    }
    
    # Add icon if provided
    if icon:
        profile_config["icon"] = icon
        
    # Update with any custom settings
    if custom_settings:
        profile_config.update(custom_settings)
    
    # Write profile configuration to file
    profile_path = os.path.join(CONFIG_PATH, f"{name}.json")
    with open(profile_path, "w") as f:
        json.dump(profile_config, f, indent=2)
    
    print(f"✓ Created pane profile: {profile_path}")
    return profile_path


def create_desktop_file(name, url=None, category=None, icon=None, path=None, profile=None, with_navigation=False):
    """Creates a .desktop file with the given parameters."""
    # Format name for file (remove spaces, lowercase)
    safe_name = name.lower().replace(" ", "-")
    desktop_file_path = os.path.join(DESKTOP_PATH, f"{safe_name}{DESKTOP_FILE_EXT}")
    
    if os.path.exists(desktop_file_path):
        print(f"ⓘ A .desktop file with the name '{safe_name}' already exists.")
        overwrite = input("Do you want to overwrite it? (y/n): ")
        if overwrite.lower() != "y":
            print("ⓘ Skipping .desktop file creation.")
            return

    try:
        with open(desktop_file_path, "w", encoding="utf-8") as fb:
            fb.write("[Desktop Entry]\n")
            fb.write("Version=1.0\n")
            fb.write(f"Name={name}\n")
            fb.write("Comment=Pane minimal site-specific browser\n")

            # Build the Exec command
            exec_cmd = "pane"
            
            if profile:
                # Using profile
                exec_cmd += f" -p {profile}"
            elif url:
                # Using direct URL
                if not is_valid_url(url):
                    # Try adding https:// prefix if needed
                    fixed_url = 'https://' + url if not url.startswith(('http://', 'https://')) else url
                    if not is_valid_url(fixed_url):
                        raise ValueError(f"Invalid URL: {url}")
                    url = fixed_url
                exec_cmd += f" -l '{url}'"
                
            # Add navigation flag if requested
            if with_navigation:
                exec_cmd += " -n"
                
            # Add icon parameter if provided
            if icon:
                exec_cmd += f" -i '{icon}'"
                
            fb.write(f"Exec={exec_cmd}\n")
            
            # Add icon to desktop file
            if icon:
                fb.write(f"Icon={icon}\n")

            # Add working directory if provided
            if path:
                if not os.path.exists(path):
                    raise FileNotFoundError(f"Path does not exist: {path}")
                fb.write(f"Path={path}\n")

            fb.write("Terminal=false\n")
            fb.write("Type=Application\n")

            if category:
                fb.write(f"Categories={category};\n")
            else:
                fb.write("Categories=Network;WebBrowser;Utility;\n")

            fb.write("StartupNotify=false\n")
            fb.write("StartupWMClass=pane\n")

        print(f"✓ {safe_name}{DESKTOP_FILE_EXT} file created at {DESKTOP_PATH}")
        return desktop_file_path
    except (ValueError, FileNotFoundError) as e:
        print(f"✗ Failed to create .desktop file: {str(e)}")
    except Exception as e:
        print(f"✗ An unexpected error occurred: {str(e)}")
        

def install_pane_if_needed():
    """Check if pane is installed, offer to install if not."""
    try:
        # Check if pane is in PATH
        subprocess.run(["which", "pane"], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return True
    except subprocess.CalledProcessError:
        print("ⓘ Pane browser is not installed or not in your PATH.")
        install = input("Would you like to install it now? (y/n): ")
        if install.lower() == "y":
            try:
                # Clone the repo and install
                subprocess.run(["git", "clone", "https://github.com/yourusername/pane.git", "/tmp/pane"], check=True)
                os.chdir("/tmp/pane")
                subprocess.run(["pip", "install", "--user", "."], check=True)
                print("✓ Pane browser installed successfully!")
                return True
            except subprocess.CalledProcessError as e:
                print(f"✗ Failed to install pane: {e}")
                return False
        return False


def list_apps():
    """List all pane apps that have been created."""
    print("\nInstalled Pane Apps:")
    print("==================")
    
    # Check desktop files
    desktop_files = []
    for file in os.listdir(DESKTOP_PATH):
        if file.endswith(DESKTOP_FILE_EXT):
            with open(os.path.join(DESKTOP_PATH, file), 'r') as f:
                content = f.read()
                if 'pane' in content:
                    name = None
                    exec_cmd = None
                    for line in content.splitlines():
                        if line.startswith("Name="):
                            name = line[5:]
                        elif line.startswith("Exec="):
                            exec_cmd = line[5:]
                    
                    if name and exec_cmd:
                        desktop_files.append((name, file, exec_cmd))
    
    # Check profiles
    profiles = []
    for file in os.listdir(CONFIG_PATH):
        if file.endswith(".json"):
            try:
                with open(os.path.join(CONFIG_PATH, file), 'r') as f:
                    data = json.load(f)
                    profiles.append((os.path.splitext(file)[0], data.get("url", "Unknown URL")))
            except:
                pass
    
    # Print desktop files
    if desktop_files:
        for name, file, exec_cmd in desktop_files:
            print(f"  • {name} ({file})")
            print(f"    Command: {exec_cmd}")
    else:
        print("  No Pane desktop entries found")
    
    # Print profiles
    print("\nPane Profiles:")
    print("=============")
    if profiles:
        for name, url in profiles:
            print(f"  • {name}: {url}")
    else:
        print("  No Pane profiles found")


def delete_app():
    """Delete a pane app."""
    # Get list of desktop files
    desktop_files = []
    for file in os.listdir(DESKTOP_PATH):
        if file.endswith(DESKTOP_FILE_EXT):
            with open(os.path.join(DESKTOP_PATH, file), 'r') as f:
                content = f.read()
                if 'pane' in content:
                    for line in content.splitlines():
                        if line.startswith("Name="):
                            name = line[5:]
                            desktop_files.append((name, file))
                            break
    
    # Get list of profiles
    profiles = []
    for file in os.listdir(CONFIG_PATH):
        if file.endswith(".json"):
            profiles.append(os.path.splitext(file)[0])
    
    if not desktop_files and not profiles:
        print("No Pane apps found to delete.")
        return
    
    print("\nSelect a Pane app to delete:")
    print("============================")
    
    # Print desktop files
    if desktop_files:
        print("Desktop Entries:")
        for i, (name, file) in enumerate(desktop_files):
            print(f"  {i+1}. {name} ({file})")
    
    # Print profiles
    if profiles:
        print("\nProfiles:")
        offset = len(desktop_files)
        for i, profile in enumerate(profiles):
            print(f"  {i+offset+1}. {profile}")
    
    try:
        choice = int(input("\nEnter number to delete (0 to cancel): "))
        if choice == 0:
            print("Operation cancelled.")
            return
        
        if choice <= len(desktop_files):
            # Delete desktop file
            name, file = desktop_files[choice-1]
            file_path = os.path.join(DESKTOP_PATH, file)
            os.remove(file_path)
            print(f"✓ Deleted desktop entry: {file}")
            
            # Ask if profile should be deleted too
            profile_name = os.path.splitext(file)[0]
            profile_path = os.path.join(CONFIG_PATH, f"{profile_name}.json")
            if os.path.exists(profile_path):
                delete_profile = input(f"Delete associated profile '{profile_name}' too? (y/n): ")
                if delete_profile.lower() == "y":
                    os.remove(profile_path)
                    print(f"✓ Deleted profile: {profile_name}")
        else:
            # Delete profile
            offset = len(desktop_files)
            profile = profiles[choice-offset-1]
            profile_path = os.path.join(CONFIG_PATH, f"{profile}.json")
            os.remove(profile_path)
            print(f"✓ Deleted profile: {profile}")
            
            # Ask if desktop file should be deleted too
            desktop_path = os.path.join(DESKTOP_PATH, f"{profile}{DESKTOP_FILE_EXT}")
            if os.path.exists(desktop_path):
                delete_desktop = input(f"Delete associated desktop entry '{profile}' too? (y/n): ")
                if delete_desktop.lower() == "y":
                    os.remove(desktop_path)
                    print(f"✓ Deleted desktop entry: {profile}")
    except (ValueError, IndexError):
        print("Invalid selection. Please enter a valid number.")
    except Exception as e:
        print(f"Error deleting app: {e}")


def interactive_mode():
    """Run the program in interactive mode."""
    print("\nInteractive Mode")
    print("===============")
    
    name = input("Enter name for the new app: ")
    if not name:
        print("Name is required. Exiting.")
        return
    
    url = input("Enter website URL: ")
    if not url:
        print("URL is required. Exiting.")
        return
    
    # Fix URL if needed
    if not url.startswith(('http://', 'https://')):
        url = 'https://' + url
    
    # Ask about navigation
    with_navigation = input("Include navigation controls? (y/n): ").lower() == 'y'
    
    # Ask about category
    default_categories = ["Network", "WebBrowser", "Utility", "Office", "Development", 
                         "Education", "Game", "Graphics", "AudioVideo", "System"]
    
    print("\nCommon categories:")
    for i, cat in enumerate(default_categories):
        print(f"  {i+1}. {cat}")
    
    cat_choice = input("\nSelect category number or enter custom category (default is Network): ")
    if cat_choice.isdigit() and 1 <= int(cat_choice) <= len(default_categories):
        category = default_categories[int(cat_choice)-1]
    elif cat_choice:
        category = cat_choice
    else:
        category = "Network"
    
    # Try to find an icon
    print(f"\nSearching for an icon from {url}...")
    icon = find_best_icon(url, name.lower().replace(" ", "-"))
    
    if not icon:
        custom_icon = input("No icon found. Would you like to specify a custom icon path? (y/n): ")
        if custom_icon.lower() == 'y':
            icon_path = input("Enter path to icon file: ")
            if os.path.exists(icon_path):
                # Copy icon to the icon directory
                icon_ext = os.path.splitext(icon_path)[1]
                safe_name = name.lower().replace(" ", "-")
                icon = os.path.join(ICON_PATH, f"{safe_name}{icon_ext}")
                shutil.copy(icon_path, icon)
                print(f"✓ Icon copied to {icon}")
            else:
                print("Icon file not found.")
                icon = None
    
    # Create profile
    custom_settings = {
        "enable_navigation": with_navigation
    }
    
    safe_name = name.lower().replace(" ", "-")
    profile_path = create_pane_profile(safe_name, url, icon, custom_settings)
    
    # Create desktop file
    desktop_file = create_desktop_file(
        name=name, 
        profile=safe_name,
        category=category, 
        icon=icon,
        with_navigation=with_navigation
    )
    
    if desktop_file:
        launch = input("\nWould you like to launch the app now? (y/n): ")
        if launch.lower() == 'y':
            try:
                subprocess.Popen(["pane", "-p", safe_name])
                print(f"✓ Launched {name}")
            except Exception as e:
                print(f"Failed to launch: {e}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Window Maker for Pane - Create minimal site-specific browsers",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  makewindow -n "My App" -u example.com -c Network
  makewindow --interactive
  makewindow --list
  makewindow --delete
"""
    )
    
    greeting()
    
    # Main options
    parser.add_argument("-n", "--name", help="Name for your new SSB")
    parser.add_argument("-u", "--url", help="URL for your SSB")
    parser.add_argument("-c", "--category", help="Category for the app", default="Network")
    parser.add_argument("-i", "--icon", help="Path to icon")
    parser.add_argument("-p", "--path", help="Working directory path")
    parser.add_argument("-N", "--navigation", action="store_true", help="Include navigation controls")
    
    # Extra functionality
    parser.add_argument("--list", action="store_true", help="List all created Pane apps")
    parser.add_argument("--delete", action="store_true", help="Delete a Pane app")
    parser.add_argument("--interactive", action="store_true", help="Run in interactive mode")
    
    args = parser.parse_args()
    
    # Check for pane installation
    if not args.list and not args.delete:
        if not install_pane_if_needed():
            print("Pane browser is required. Please install it first.")
            sys.exit(1)
    
    try:
        if args.list:
            list_apps()
        elif args.delete:
            delete_app()
        elif args.interactive:
            interactive_mode()
        elif args.name and args.url:
            # Create profile first
            custom_settings = {
                "enable_navigation": args.navigation
            }
            
            safe_name = args.name.lower().replace(" ", "-")
            
            # Try to find an icon if not provided
            icon = args.icon
            if not icon:
                print(f"Searching for an icon from {args.url}...")
                icon = find_best_icon(args.url, safe_name)
            
            profile_path = create_pane_profile(safe_name, args.url, icon, custom_settings)
            
            # Then create desktop file
            create_desktop_file(
                name=args.name,
                profile=safe_name,
                category=args.category,
                icon=icon,
                path=args.path,
                with_navigation=args.navigation
            )
        else:
            parser.print_help()
    except Exception as e:
        print(f"✗ An unexpected error occurred: {str(e)}")
