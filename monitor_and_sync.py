#!/usr/bin/python3
"""
GCode File Monitor and Sync Script
Monitors ~/Desktop for new .gcode files and syncs them to the Pi2W
"""

import os
import sys
import time
import subprocess
import logging
from pathlib import Path
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

# Configuration
WATCH_DIR = os.path.expanduser("~/Desktop")
REMOTE_USER = "milugo"
REMOTE_HOST = "192.168.1.6"
REMOTE_PORT = "22"
REMOTE_PATH = "/mnt/usb_share"
LOG_FILE = os.path.expanduser("~/.gcode_sync.log")

# Note: Changed from localhost:9702 to direct connection 192.168.1.6:22

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler(sys.stdout)
    ]
)

class GCodeHandler(FileSystemEventHandler):
    """Handler for .gcode file events"""

    def __init__(self):
        self.syncing = set()  # Track files currently being synced

    def on_created(self, event):
        """Called when a file is created"""
        if not event.is_directory and event.src_path.endswith('.gcode'):
            self.sync_file(event.src_path)

    def on_moved(self, event):
        """Called when a file is moved into the directory"""
        if not event.is_directory and event.dest_path.endswith('.gcode'):
            self.sync_file(event.dest_path)

    def on_modified(self, event):
        """Called when a file is modified (handles saves from some editors)"""
        if not event.is_directory and event.src_path.endswith('.gcode'):
            # Only sync if not already syncing
            if event.src_path not in self.syncing:
                self.sync_file(event.src_path)

    def sync_file(self, file_path):
        """Sync a file to the remote server"""
        if file_path in self.syncing:
            return

        self.syncing.add(file_path)
        try:
            # Wait a moment to ensure file is fully written
            time.sleep(1)

            if not os.path.exists(file_path):
                logging.warning(f"File no longer exists: {file_path}")
                return

            logging.info(f"Syncing file: {file_path}")

            # Build rsync command
            rsync_cmd = [
                "rsync",
                "-avz",
                "-e", f"ssh -p {REMOTE_PORT}",
                file_path,
                f"{REMOTE_USER}@{REMOTE_HOST}:{REMOTE_PATH}/"
            ]

            # Execute rsync
            result = subprocess.run(
                rsync_cmd,
                capture_output=True,
                text=True,
                check=True
            )

            logging.info(f"Successfully synced: {os.path.basename(file_path)}")

            # Trigger USB gadget refresh
            self.refresh_usb_gadget()

        except subprocess.CalledProcessError as e:
            logging.error(f"Failed to sync {file_path}: {e}")
            logging.error(f"STDERR: {e.stderr}")
        except Exception as e:
            logging.error(f"Unexpected error syncing {file_path}: {e}")
        finally:
            self.syncing.discard(file_path)

    def refresh_usb_gadget(self):
        """Trigger USB gadget refresh on the Pi"""
        try:
            ssh_cmd = [
                "ssh",
                "-p", REMOTE_PORT,
                f"{REMOTE_USER}@{REMOTE_HOST}",
                "sudo /usr/local/bin/refresh_usb_gadget.sh"
            ]
            subprocess.run(ssh_cmd, check=True, capture_output=True)
            logging.info("USB gadget refreshed successfully")
        except subprocess.CalledProcessError as e:
            logging.error(f"Failed to refresh USB gadget: {e}")


def main():
    """Main function"""
    # Check if watchdog is installed
    try:
        import watchdog
    except ImportError:
        logging.error("watchdog module not found. Installing...")
        subprocess.run([sys.executable, "-m", "pip", "install", "watchdog"], check=True)
        logging.info("Please restart the script")
        sys.exit(1)

    # Create watch directory if it doesn't exist
    os.makedirs(WATCH_DIR, exist_ok=True)

    logging.info(f"Starting gcode file monitor on {WATCH_DIR}")
    logging.info(f"Will sync to {REMOTE_USER}@{REMOTE_HOST}:{REMOTE_PORT}:{REMOTE_PATH}")

    # Setup file system observer
    event_handler = GCodeHandler()
    observer = Observer()
    observer.schedule(event_handler, WATCH_DIR, recursive=False)

    # Start monitoring
    observer.start()
    logging.info("Monitoring for new .gcode files... (Press Ctrl+C to stop)")

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        logging.info("Stopping monitor...")
        observer.stop()

    observer.join()
    logging.info("Monitor stopped")


if __name__ == "__main__":
    main()
