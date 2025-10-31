#!/usr/bin/python3
"""
GCode File Monitor and Sync Script
Monitors configured directory for new .gcode files and syncs them to the Pi
"""

import os
import sys
import time
import subprocess
import logging
import threading
from pathlib import Path
from functools import wraps
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

# Determine script directory
SCRIPT_DIR = Path(__file__).parent.resolve()

# Configuration constants
FILE_SETTLE_DELAY = 1           # Seconds to wait for file write completion
RSYNC_TIMEOUT = 60              # Rsync network timeout (seconds)
RSYNC_TOTAL_TIMEOUT = 120       # Maximum time for entire rsync operation (2 minutes)
USB_REFRESH_TIMEOUT = 30        # USB gadget refresh timeout (seconds)

# File size limits (GCode files are typically 1-100 MB, rarely >500 MB)
MAX_FILE_SIZE = 1024 * 1024 * 1024      # 1 GB (hard limit)
WARN_FILE_SIZE = 500 * 1024 * 1024      # 500 MB (warn but allow)
MIN_FILE_SIZE = 1                        # Reject empty files

# Retry configuration for transient failures
RETRY_MAX_ATTEMPTS = 3                   # Maximum retry attempts
RETRY_INITIAL_DELAY = 2                  # Initial retry delay (seconds)
RETRY_BACKOFF_MULTIPLIER = 2             # Exponential backoff multiplier

def retry_on_failure(max_attempts=RETRY_MAX_ATTEMPTS, initial_delay=RETRY_INITIAL_DELAY,
                     backoff_multiplier=RETRY_BACKOFF_MULTIPLIER):
    """
    Decorator to retry function on transient failures with exponential backoff.

    Args:
        max_attempts: Maximum number of retry attempts
        initial_delay: Initial delay between retries (seconds)
        backoff_multiplier: Multiplier for exponential backoff

    Returns:
        Decorated function that will retry on subprocess.CalledProcessError
        or subprocess.TimeoutExpired
    """
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            attempt = 1
            delay = initial_delay

            while attempt <= max_attempts:
                try:
                    return func(*args, **kwargs)
                except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
                    if attempt == max_attempts:
                        # Final attempt failed, re-raise
                        raise

                    # Log retry attempt
                    logging.warning(f"Attempt {attempt}/{max_attempts} failed: {type(e).__name__}")
                    logging.warning(f"Retrying in {delay}s...")

                    time.sleep(delay)
                    delay *= backoff_multiplier
                    attempt += 1

        return wrapper
    return decorator

def load_config():
    """Load configuration from config.local"""
    config_file = SCRIPT_DIR / 'config.local'

    if not config_file.exists():
        print(f"ERROR: Configuration file not found: {config_file}", file=sys.stderr)
        print("", file=sys.stderr)
        print("Please run the setup wizard first:", file=sys.stderr)
        print("  ./setup_wizard.sh", file=sys.stderr)
        print("", file=sys.stderr)
        print("Or manually create config.local from config.example:", file=sys.stderr)
        print("  cp config.example config.local", file=sys.stderr)
        print("  nano config.local", file=sys.stderr)
        sys.exit(1)

    config = {}
    with open(config_file, 'r') as f:
        for line in f:
            line = line.strip()
            # Skip comments and empty lines
            if line.startswith('#') or not line or '=' not in line:
                continue
            # Parse KEY="VALUE" or KEY=VALUE
            key, value = line.split('=', 1)
            key = key.strip()
            value = value.strip().strip('"').strip("'")
            # Expand shell variables like $HOME
            value = os.path.expandvars(value)
            value = os.path.expanduser(value)
            config[key] = value

    # Validate required variables
    required = ['WATCH_DIR', 'REMOTE_USER', 'REMOTE_HOST', 'REMOTE_PORT', 'REMOTE_PATH', 'LOG_FILE']
    for key in required:
        if key not in config:
            print(f"ERROR: Required variable {key} is not set in {config_file}", file=sys.stderr)
            sys.exit(1)

    # Validate config values to prevent injection attacks
    import re

    # Port must be numeric
    if not config['REMOTE_PORT'].isdigit():
        print(f"ERROR: REMOTE_PORT must be numeric (got: {config['REMOTE_PORT']})", file=sys.stderr)
        sys.exit(1)

    port = int(config['REMOTE_PORT'])
    if port < 1 or port > 65535:
        print(f"ERROR: REMOTE_PORT must be between 1 and 65535 (got: {port})", file=sys.stderr)
        sys.exit(1)

    # Host, user, and path must not contain dangerous characters
    dangerous_chars = re.compile(r'[$`;\|&<>(){}]')

    if dangerous_chars.search(config['REMOTE_HOST']):
        print("ERROR: REMOTE_HOST contains invalid characters", file=sys.stderr)
        sys.exit(1)

    if dangerous_chars.search(config['REMOTE_USER']):
        print("ERROR: REMOTE_USER contains invalid characters", file=sys.stderr)
        sys.exit(1)

    if dangerous_chars.search(config['REMOTE_PATH']):
        print("ERROR: REMOTE_PATH contains invalid characters", file=sys.stderr)
        sys.exit(1)

    # Validate WATCH_DIR and LOG_FILE paths (defense in depth)
    from pathlib import Path

    # Validate WATCH_DIR is absolute and within user home
    try:
        watch_dir = Path(config['WATCH_DIR']).resolve()
    except Exception as e:
        print(f"ERROR: Invalid WATCH_DIR path: {config['WATCH_DIR']}: {e}", file=sys.stderr)
        sys.exit(1)

    user_home = Path.home()

    if not watch_dir.is_absolute():
        print(f"ERROR: WATCH_DIR must be an absolute path (got: {config['WATCH_DIR']})", file=sys.stderr)
        sys.exit(1)

    # Ensure WATCH_DIR is within user's home directory
    try:
        watch_dir.relative_to(user_home)
    except ValueError:
        print(f"ERROR: WATCH_DIR must be within user home directory ({user_home})", file=sys.stderr)
        print(f"  Got: {watch_dir}", file=sys.stderr)
        sys.exit(1)

    # Validate LOG_FILE path
    try:
        log_file = Path(config['LOG_FILE']).resolve()
    except Exception as e:
        print(f"ERROR: Invalid LOG_FILE path: {config['LOG_FILE']}: {e}", file=sys.stderr)
        sys.exit(1)

    # Prevent writing to system directories
    forbidden_paths = [Path('/etc'), Path('/var'), Path('/usr'), Path('/bin'), Path('/sbin'), Path('/boot')]

    for forbidden in forbidden_paths:
        try:
            log_file.relative_to(forbidden)
            print(f"ERROR: LOG_FILE cannot be in system directory ({forbidden})", file=sys.stderr)
            print(f"  Got: {log_file}", file=sys.stderr)
            sys.exit(1)
        except ValueError:
            pass  # Not in this forbidden path, continue checking

    # LOG_FILE should be within user home for safety
    try:
        log_file.relative_to(user_home)
    except ValueError:
        print(f"ERROR: LOG_FILE must be within user home directory ({user_home})", file=sys.stderr)
        print(f"  Got: {log_file}", file=sys.stderr)
        sys.exit(1)

    # Check for path traversal sequences
    path_traversal = re.compile(r'\.\.')
    if path_traversal.search(config['WATCH_DIR']):
        print("ERROR: WATCH_DIR contains path traversal sequence (..)", file=sys.stderr)
        sys.exit(1)

    if path_traversal.search(config['LOG_FILE']):
        print("ERROR: LOG_FILE contains path traversal sequence (..)", file=sys.stderr)
        sys.exit(1)

    return config

# Load configuration
config = load_config()
WATCH_DIR = config['WATCH_DIR']
REMOTE_USER = config['REMOTE_USER']
REMOTE_HOST = config['REMOTE_HOST']
REMOTE_PORT = config['REMOTE_PORT']
REMOTE_PATH = config['REMOTE_PATH']
LOG_FILE = config['LOG_FILE']

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
        self.syncing_lock = threading.Lock()  # Prevent race conditions

    def on_created(self, event):
        """Called when a file is created"""
        if not event.is_directory and event.src_path.endswith('.gcode'):
            # Thread-safe check before syncing
            with self.syncing_lock:
                if event.src_path not in self.syncing:
                    self.sync_file(event.src_path)

    def on_moved(self, event):
        """Called when a file is moved into the directory"""
        if not event.is_directory and event.dest_path.endswith('.gcode'):
            # Thread-safe check before syncing
            with self.syncing_lock:
                if event.dest_path not in self.syncing:
                    self.sync_file(event.dest_path)

    def on_modified(self, event):
        """Called when a file is modified (handles saves from some editors)"""
        if not event.is_directory and event.src_path.endswith('.gcode'):
            # Only sync if not already syncing (thread-safe check)
            with self.syncing_lock:
                if event.src_path not in self.syncing:
                    self.sync_file(event.src_path)

    def sync_file(self, file_path):
        """Sync a file to the remote server"""
        # Thread-safe check and add
        with self.syncing_lock:
            if file_path in self.syncing:
                return
            self.syncing.add(file_path)

        try:
            # Wait a moment to ensure file is fully written
            time.sleep(FILE_SETTLE_DELAY)

            # Security: Validate file path is within watch directory
            abs_file_path = os.path.abspath(file_path)
            abs_watch_dir = os.path.abspath(WATCH_DIR)

            if not abs_file_path.startswith(abs_watch_dir + os.sep):
                logging.error(f"Security: File outside watch directory: {file_path}")
                logging.error(f"  File path: {abs_file_path}")
                logging.error(f"  Watch dir: {abs_watch_dir}")
                return

            # Security: Check it's a regular file (not symlink, directory, device, etc.)
            if not os.path.exists(abs_file_path):
                logging.warning(f"File no longer exists: {file_path}")
                return

            if os.path.islink(abs_file_path):
                logging.error(f"Security: Refusing to sync symlink: {file_path}")
                return

            if not os.path.isfile(abs_file_path):
                logging.warning(f"Skipping non-regular file: {file_path}")
                return

            # Security: Validate file extension (defense in depth)
            if not abs_file_path.endswith('.gcode'):
                logging.warning(f"Skipping non-gcode file: {file_path}")
                return

            # Validate file size to prevent DoS
            try:
                file_size = os.path.getsize(abs_file_path)
            except OSError as e:
                logging.error(f"Cannot determine file size: {file_path}: {e}")
                return

            if file_size < MIN_FILE_SIZE:
                logging.warning(f"Skipping empty file: {file_path}")
                return

            if file_size > MAX_FILE_SIZE:
                logging.error(f"File too large: {file_path} ({file_size / (1024*1024):.2f} MB)")
                logging.error(f"Maximum allowed size: {MAX_FILE_SIZE / (1024*1024):.2f} MB")
                return

            if file_size > WARN_FILE_SIZE:
                logging.warning(f"Large file detected: {file_path} ({file_size / (1024*1024):.2f} MB)")
                logging.warning("This may take several minutes to sync")

            logging.info(f"Syncing file: {abs_file_path} ({file_size / (1024*1024):.2f} MB)")

            # SECURITY: Re-validate immediately before rsync to prevent TOCTOU race condition
            # This closes the window where file could be replaced with symlink after validation
            if os.path.islink(abs_file_path):
                logging.error(f"Security: File became symlink after validation: {file_path}")
                return

            if not os.path.isfile(abs_file_path):
                logging.error(f"Security: File changed type after validation: {file_path}")
                return

            if not abs_file_path.endswith('.gcode'):
                logging.error(f"Security: File extension changed after validation: {file_path}")
                return

            # Calculate dynamic timeout based on file size
            # Baseline: 2 minutes for small files, add 1 minute per 100 MB for large files
            timeout_seconds = max(RSYNC_TOTAL_TIMEOUT, int((file_size / (100 * 1024 * 1024)) * 60))

            logging.debug(f"Using timeout: {timeout_seconds}s for {file_size / (1024*1024):.2f} MB file")

            # Build rsync command with timeouts
            rsync_cmd = [
                "rsync",
                "-avz",
                f"--timeout={RSYNC_TIMEOUT}",
                "-e", f"ssh -p {REMOTE_PORT} -o StrictHostKeyChecking=yes -o ConnectTimeout=10 -o ServerAliveInterval=5 -o ServerAliveCountMax=3",
                abs_file_path,
                f"{REMOTE_USER}@{REMOTE_HOST}:{REMOTE_PATH}/"
            ]

            # Execute rsync with retry logic (handles transient network failures)
            # Execute rsync immediately after re-validation (minimize TOCTOU window)
            result = self._execute_rsync_with_retry(rsync_cmd, timeout_seconds)

            logging.info(f"Successfully synced: {os.path.basename(abs_file_path)}")

            # Trigger USB gadget refresh
            self.refresh_usb_gadget()

        except subprocess.TimeoutExpired:
            logging.error(f"Timeout syncing {file_path} - transfer took longer than 2 minutes")
        except subprocess.CalledProcessError as e:
            logging.error(f"Failed to sync {file_path}: {e}")
            logging.error(f"STDERR: {e.stderr}")
        except Exception as e:
            logging.error(f"Unexpected error syncing {file_path}: {e}")
        finally:
            with self.syncing_lock:
                self.syncing.discard(file_path)

    @retry_on_failure()
    def _execute_rsync_with_retry(self, rsync_cmd, timeout_seconds):
        """Execute rsync command with retry logic for transient failures.

        Args:
            rsync_cmd: List of command arguments for rsync
            timeout_seconds: Timeout in seconds for the operation

        Returns:
            subprocess.CompletedProcess: Result of the rsync operation

        Raises:
            subprocess.CalledProcessError: If rsync fails after all retries
            subprocess.TimeoutExpired: If rsync times out after all retries
        """
        return subprocess.run(
            rsync_cmd,
            capture_output=True,
            text=True,
            check=True,
            timeout=timeout_seconds
        )

    def refresh_usb_gadget(self):
        """Trigger USB gadget refresh on the Pi.

        Returns:
            bool: True if refresh succeeded, False otherwise

        Raises:
            subprocess.CalledProcessError: If refresh fails critically
        """
        ssh_cmd = [
            "ssh",
            "-p", REMOTE_PORT,
            "-o", "StrictHostKeyChecking=yes",
            "-o", "ConnectTimeout=10",
            "-o", "ServerAliveInterval=5",
            "-o", "ServerAliveCountMax=3",
            f"{REMOTE_USER}@{REMOTE_HOST}",
            "sudo /usr/local/bin/refresh_usb_gadget.sh"
        ]

        try:
            result = subprocess.run(
                ssh_cmd,
                check=True,
                capture_output=True,
                text=True,
                timeout=USB_REFRESH_TIMEOUT
            )
            logging.info("USB gadget refreshed successfully")
            if result.stdout:
                logging.debug(f"Refresh output: {result.stdout.strip()}")
            return True

        except subprocess.TimeoutExpired:
            logging.error("USB gadget refresh timed out after 30 seconds")
            logging.warning("File was synced but printer may not see it until Pi reboot")
            return False

        except subprocess.CalledProcessError as e:
            logging.error(f"USB gadget refresh failed with exit code {e.returncode}")
            if e.stderr:
                logging.error(f"Error details: {e.stderr.strip()}")
            logging.warning("File was synced but printer may not see it until Pi reboot")
            logging.info(f"To manually refresh: ssh {REMOTE_USER}@{REMOTE_HOST} 'sudo /usr/local/bin/refresh_usb_gadget.sh'")
            return False

        except Exception as e:
            logging.error(f"Unexpected error during USB gadget refresh: {type(e).__name__}: {e}")
            logging.warning("File was synced but printer may not see it")
            return False


def main():
    """Main function"""
    # Check if watchdog is installed
    try:
        import watchdog
    except ImportError:
        logging.error("watchdog module not found. Installing...")
        req_file = SCRIPT_DIR / "requirements.txt"
        if req_file.exists():
            subprocess.run([sys.executable, "-m", "pip", "install", "-r", str(req_file)], check=True)
        else:
            subprocess.run([sys.executable, "-m", "pip", "install", "watchdog==3.0.0"], check=True)
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
