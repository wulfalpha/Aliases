#!/usr/bin/env python
import argparse
import os
import sys
import json
from pathlib import Path
from PyQt5.QtCore import QUrl, QSize, Qt, QSettings
from PyQt5.QtGui import QIcon, QKeySequence
from PyQt5.QtWebEngineWidgets import QWebEngineView, QWebEngineProfile, QWebEnginePage
from PyQt5.QtWidgets import (
    QApplication,
    QMainWindow,
    QDesktopWidget,
    QMessageBox,
    QSizePolicy,
    QProgressBar,
    QStatusBar,
    QShortcut,
    QMenu,
    QAction,
    QToolBar,
    QInputDialog,
    QLineEdit,
)

# Default configuration
DEFAULT_CONFIG = {
    "url": "https://search.brave.com",
    "user_agent": None,  # Uses system default if None
    "size": [0.8, 0.8],  # Percentage of screen size [width, height]
    "zoom_factor": 1.0,
    "enable_dev_tools": False,
    "enable_navigation": False,
    "enable_js": True,
    "enable_cookies": True,
    "config_dir": os.path.expanduser("~/.config/pane"),
}


class PaneWebEnginePage(QWebEnginePage):
    def __init__(self, profile, parent=None):
        super().__init__(profile, parent)
        self.base_url = None

    def acceptNavigationRequest(self, url, nav_type, is_main_frame):
        # Store base URL for future navigation checks
        if self.base_url is None and is_main_frame:
            self.base_url = url.toString().split("/")[2]  # domain

        # Allow navigation within same domain if navigation is enabled
        if self.parent().navigation_enabled:
            return True
        else:
            # Only allow navigation to the same domain
            if is_main_frame and nav_type != QWebEnginePage.NavigationTypeLinkClicked:
                return True
            elif is_main_frame and url.toString().split("/")[2] != self.base_url:
                # Open external links in system browser
                QDesktopServices.openUrl(url)
                return False
            return True


class PaneWebEngineView(QWebEngineView):
    def __init__(self, config):
        super().__init__()
        self.config = config
        self.navigation_enabled = config.get("enable_navigation", False)
        
        # Set up custom profile
        self.profile = QWebEngineProfile("PaneProfile", self)
        
        # Configure custom user agent if specified
        if config.get("user_agent"):
            self.profile.setHttpUserAgent(config.get("user_agent"))
        
        # Configure cookie settings
        self.profile.setPersistentCookiesPolicy(
            QWebEngineProfile.PersistentCookiesPolicy.AllowPersistentCookies 
            if config.get("enable_cookies") else 
            QWebEngineProfile.PersistentCookiesPolicy.NoPersistentCookies
        )
        
        # Set up custom page with navigation control
        self.page = PaneWebEnginePage(self.profile, self)
        self.setPage(self.page)
        
        # Set JavaScript enabled/disabled
        self.settings().setAttribute(
            QWebEngineSettings.JavascriptEnabled, 
            config.get("enable_js", True)
        )
        
        # Set zoom factor
        self.setZoomFactor(config.get("zoom_factor", 1.0))
        
        # Connect signals
        self.loadStarted.connect(self.on_load_started)
        self.loadProgress.connect(self.on_load_progress)
        self.loadFinished.connect(self.on_load_finished)

    def load_url(self, url):
        if not url.startswith(("http://", "https://")):
            url = "https://" + url
            
        if QUrl.fromUserInput(url).isValid():
            self.load(QUrl(url))
        else:
            QMessageBox.critical(self.parent(), "Error", f"Invalid URL: {url}")

    def on_load_started(self):
        if self.parent():
            self.parent().progress_bar.show()

    def on_load_progress(self, p):
        if self.parent():
            self.parent().progress_bar.setValue(p)
            self.parent().statusBar().showMessage(f"Loading... {p}%")

    def on_load_finished(self, success):
        if self.parent():
            self.parent().progress_bar.hide()
            if success:
                title = self.title()
                if title:
                    self.parent().setWindowTitle(f"{title} - Pane")
                self.parent().statusBar().showMessage("Ready", 3000)
            else:
                self.parent().statusBar().showMessage("Failed to load page", 3000)

    def createWindow(self, window_type):
        # Handle new windows by opening them in the system browser
        from PyQt5.QtGui import QDesktopServices
        page = self.page()
        if page:
            url = page.requestedUrl()
            if url.isValid():
                QDesktopServices.openUrl(url)
        return None


class Pane(QMainWindow):
    def __init__(self, config):
        super(Pane, self).__init__()
        
        self.config = config
        self.init_window()
        self.init_browser()
        self.init_ui()
        self.init_shortcuts()
        
        # Load URL
        self.browser.load_url(self.config.get("url"))
        
        # Restore window state if available
        self.restore_state()
        
        self.show()
    
    def init_window(self):
        # Set up window size based on config (percentage of screen)
        screen_size = QDesktopWidget().availableGeometry().size()
        width_factor, height_factor = self.config.get("size", [0.8, 0.8])
        window_size = QSize(
            int(screen_size.width() * width_factor), 
            int(screen_size.height() * height_factor)
        )
        self.setMinimumSize(QSize(400, 300))
        self.resize(window_size)
        
        # Center window
        self.setGeometry(
            QStyle.alignedRect(
                Qt.LeftToRight,
                Qt.AlignCenter,
                self.size(),
                QDesktopWidget().availableGeometry()
            )
        )
        
        # Set window icon
        icon_path = self.config.get("icon")
        if icon_path and os.path.exists(icon_path):
            self.setWindowIcon(QIcon(icon_path))
        else:
            self.setWindowIcon(QIcon.fromTheme("application-x-executable"))
            
        # Set window title
        self.setWindowTitle(f"Pane - {self.config.get('url')}")
    
    def init_browser(self):
        # Create browser view
        self.browser = PaneWebEngineView(self.config)
        self.browser.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
        self.setCentralWidget(self.browser)
    
    def init_ui(self):
        # Create toolbar if navigation is enabled
        if self.config.get("enable_navigation", False):
            self.toolbar = QToolBar("Navigation")
            self.toolbar.setMovable(False)
            self.addToolBar(self.toolbar)
            
            # Add navigation actions
            self.back_action = QAction(QIcon.fromTheme("go-previous"), "Back", self)
            self.back_action.triggered.connect(self.browser.back)
            self.toolbar.addAction(self.back_action)
            
            self.forward_action = QAction(QIcon.fromTheme("go-next"), "Forward", self)
            self.forward_action.triggered.connect(self.browser.forward)
            self.toolbar.addAction(self.forward_action)
            
            self.refresh_action = QAction(QIcon.fromTheme("view-refresh"), "Refresh", self)
            self.refresh_action.triggered.connect(self.browser.reload)
            self.toolbar.addAction(self.refresh_action)
            
            self.home_action = QAction(QIcon.fromTheme("go-home"), "Home", self)
            self.home_action.triggered.connect(lambda: self.browser.load_url(self.config.get("url")))
            self.toolbar.addAction(self.home_action)
            
            # URL input
            self.url_input = QLineEdit()
            self.url_input.returnPressed.connect(
                lambda: self.browser.load_url(self.url_input.text())
            )
            self.toolbar.addWidget(self.url_input)
            
            # Update URL input when page changes
            self.browser.urlChanged.connect(
                lambda url: self.url_input.setText(url.toString())
            )
        
        # Set up status bar
        self.progress_bar = QProgressBar(self)
        self.progress_bar.setMaximumWidth(120)
        self.progress_bar.hide()
        
        self.statusbar = QStatusBar(self)
        self.statusbar.addPermanentWidget(self.progress_bar)
        self.setStatusBar(self.statusbar)
    
    def init_shortcuts(self):
        # Add keyboard shortcuts
        QShortcut(QKeySequence.Refresh, self, self.browser.reload)
        QShortcut(QKeySequence.ZoomIn, self, lambda: self.zoom(0.1))
        QShortcut(QKeySequence.ZoomOut, self, lambda: self.zoom(-0.1))
        QShortcut(QKeySequence("Ctrl+0"), self, lambda: self.browser.setZoomFactor(1))
        
        # Add F11 for fullscreen toggle
        self.fullscreen_shortcut = QShortcut(QKeySequence("F11"), self)
        self.fullscreen_shortcut.activated.connect(self.toggle_fullscreen)
        
        # Add Ctrl+Q for exit
        self.exit_shortcut = QShortcut(QKeySequence("Ctrl+Q"), self)
        self.exit_shortcut.activated.connect(self.close)
        
        # Add F12 for dev tools if enabled
        if self.config.get("enable_dev_tools", False):
            self.dev_tools_shortcut = QShortcut(QKeySequence("F12"), self)
            self.dev_tools_shortcut.activated.connect(self.toggle_dev_tools)
    
    def zoom(self, factor):
        current = self.browser.zoomFactor()
        self.browser.setZoomFactor(max(0.25, min(5.0, current + factor)))
        
    def toggle_fullscreen(self):
        if self.isFullScreen():
            self.showNormal()
        else:
            self.showFullScreen()
    
    def toggle_dev_tools(self):
        page = self.browser.page()
        if page:
            page.triggerAction(QWebEnginePage.InspectElement)
    
    def save_state(self):
        settings = QSettings(
            os.path.join(self.config.get("config_dir"), "window_state.ini"), 
            QSettings.IniFormat
        )
        settings.setValue("geometry", self.saveGeometry())
        settings.setValue("windowState", self.saveState())
        settings.setValue("zoomFactor", self.browser.zoomFactor())
    
    def restore_state(self):
        settings = QSettings(
            os.path.join(self.config.get("config_dir"), "window_state.ini"), 
            QSettings.IniFormat
        )
        if settings.contains("geometry"):
            self.restoreGeometry(settings.value("geometry"))
        if settings.contains("windowState"):
            self.restoreState(settings.value("windowState"))
        if settings.contains("zoomFactor"):
            self.browser.setZoomFactor(float(settings.value("zoomFactor")))
    
    def closeEvent(self, event):
        self.save_state()
        event.accept()


def load_config(args):
    """Load configuration from args and config file"""
    config = DEFAULT_CONFIG.copy()
    
    # Create config directory if it doesn't exist
    config_dir = os.path.expanduser("~/.config/pane")
    os.makedirs(config_dir, exist_ok=True)
    
    # Check if a named profile was specified
    profile_name = args.profile
    
    # Load profile config if available
    if profile_name:
        profile_path = os.path.join(config_dir, f"{profile_name}.json")
        if os.path.exists(profile_path):
            try:
                with open(profile_path, "r") as f:
                    profile_config = json.load(f)
                    config.update(profile_config)
            except (json.JSONDecodeError, IOError) as e:
                print(f"Error loading profile {profile_name}: {e}")
    
    # Command line arguments override config file
    if args.link:
        config["url"] = args.link
    if args.icon:
        config["icon"] = args.icon
    if args.user_agent:
        config["user_agent"] = args.user_agent
    if args.zoom_factor:
        config["zoom_factor"] = float(args.zoom_factor)
    if args.navigation is not None:
        config["enable_navigation"] = args.navigation
    if args.dev_tools is not None:
        config["enable_dev_tools"] = args.dev_tools
    if args.javascript is not None:
        config["enable_js"] = args.javascript
    if args.cookies is not None:
        config["enable_cookies"] = args.cookies
    
    config["config_dir"] = config_dir
    return config


def create_profile(config_dir, name, url, icon=None):
    """Create a new profile configuration"""
    profile_config = DEFAULT_CONFIG.copy()
    profile_config["url"] = url
    if icon:
        profile_config["icon"] = icon
    
    profile_path = os.path.join(config_dir, f"{name}.json")
    with open(profile_path, "w") as f:
        json.dump(profile_config, f, indent=2)
    
    print(f"Created profile {name} for {url}")


def list_profiles(config_dir):
    """List all available profiles"""
    profiles = []
    if os.path.exists(config_dir):
        for file in os.listdir(config_dir):
            if file.endswith(".json"):
                profile_name = os.path.splitext(file)[0]
                profile_path = os.path.join(config_dir, file)
                try:
                    with open(profile_path, "r") as f:
                        config = json.load(f)
                        url = config.get("url", "unknown")
                        profiles.append((profile_name, url))
                except:
                    profiles.append((profile_name, "error reading config"))
    
    return profiles


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Site-Specific Browser")
    parser.add_argument("-l", "--link", help="URL to open")
    parser.add_argument("-i", "--icon", help="Path to app icon")
    parser.add_argument("-u", "--user-agent", help="Custom user agent string")
    parser.add_argument("-z", "--zoom-factor", type=float, help="Initial zoom factor (default: 1.0)")
    parser.add_argument("-n", "--navigation", action="store_true", help="Enable navigation controls")
    parser.add_argument("-d", "--dev-tools", action="store_true", help="Enable developer tools (F12)")
    parser.add_argument("-j", "--javascript", action="store_true", help="Enable JavaScript")
    parser.add_argument("-c", "--cookies", action="store_true", help="Enable persistent cookies")
    parser.add_argument("-p", "--profile", help="Use named profile")
    
    # Profile management
    profile_group = parser.add_argument_group("Profile Management")
    profile_group.add_argument("--create-profile", metavar="NAME", help="Create a new profile")
    profile_group.add_argument("--profile-url", metavar="URL", help="URL for the new profile")
    profile_group.add_argument("--profile-icon", metavar="PATH", help="Icon for the new profile")
    profile_group.add_argument("--list-profiles", action="store_true", help="List all profiles")
    
    args = parser.parse_args()
    
    # Handle profile management commands
    config_dir = os.path.expanduser("~/.config/pane")
    
    if args.list_profiles:
        profiles = list_profiles(config_dir)
        if profiles:
            print("Available profiles:")
            for name, url in profiles:
                print(f"  {name} - {url}")
        else:
            print("No profiles found")
        sys.exit(0)
    
    if args.create_profile:
        if not args.profile_url:
            print("Error: --profile-url is required when creating a profile")
            sys.exit(1)
        create_profile(config_dir, args.create_profile, args.profile_url, args.profile_icon)
        sys.exit(0)
    
    # Load config and run application
    config = load_config(args)
    
    app = QApplication(sys.argv)
    app.setApplicationName("Pane")
    app.setQuitOnLastWindowClosed(True)
    
    from PyQt5.QtWidgets import QStyle
    from PyQt5.QtWebEngineWidgets import QWebEngineSettings
    from PyQt5.QtGui import QDesktopServices
    
    window = Pane(config)
    sys.exit(app.exec_())
