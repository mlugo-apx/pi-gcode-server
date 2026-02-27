#!/usr/bin/python3
"""
GCode File Monitor and Sync Script
Monitors configured directory for new .gcode files and syncs them to the Pi
"""

import os
import sys
import time
import subprocess
import shlex
import logging
from logging.handlers import RotatingFileHandler
import threading
import re
import shutil
from pathlib import Path
from functools import wraps
from typing import Dict, Any, Optional, Callable, Tuple, List
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler, FileSystemEvent

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



def send_notification(title: str, body: str, urgency: str = "normal") -> None:
    """Send desktop notification using notify-send with graceful fallback.

    Args:
        title: Notification title
        body: Notification body text
        urgency: Notification urgency (low, normal, critical)
    """
    try:
        subprocess.run(
            ["notify-send", "--urgency=%s" % urgency, title, body],
            timeout=5,
            capture_output=True
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass  # notify-send not available or timed out — not critical


def parse_rsync_stats(stdout: Optional[str]) -> Dict[str, Any]:
    """Parse rsync --stats output into a dictionary of values."""
    stats: Dict[str, Any] = {}

    if not stdout:
        return stats

    patterns_int = {
        "total_bytes_sent": r"Total bytes sent:\s*([\d,]+)",
        "total_bytes_received": r"Total bytes received:\s*([\d,]+)",
        "literal_data": r"Literal data:\s*([\d,]+)",
        "matched_data": r"Matched data:\s*([\d,]+)",
        "total_file_size": r"Total file size:\s*([\d,]+)",
        "total_transferred_file_size": r"Total transferred file size:\s*([\d,]+)",
    }

    for key, pattern in patterns_int.items():
        match = re.search(pattern, stdout, re.MULTILINE)
        if match:
            value = match.group(1).replace(',', '')
            try:
                stats[key] = int(value)
            except ValueError:
                logging.debug("Unable to parse integer for %s from %s", key, value)

    speedup_match = re.search(r"speedup is\s+([\d.]+)", stdout)
    if speedup_match:
        try:
            stats["speedup"] = float(speedup_match.group(1))
        except ValueError:
            logging.debug("Unable to parse speedup from %s", speedup_match.group(1))

    return stats

def retry_on_failure(max_attempts: int = RETRY_MAX_ATTEMPTS, initial_delay: float = RETRY_INITIAL_DELAY,
                     backoff_multiplier: float = RETRY_BACKOFF_MULTIPLIER) -> Callable:
    """
    Decorator to retry function on transient failures with exponential backoff.

    Args:
        max_attempts: Maximum number of retry attempts
        initial_delay: Initial delay between retries (seconds)
        backoff_multiplier: Multiplier for exponential backoff

    Returns:
        Decorated function that will retry on subprocess.CalledProcessError
        or subprocess.TimeoutExpired. On success, returns a tuple of
        (result, attempts_used).
    """
    def decorator(func: Callable) -> Callable:
        @wraps(func)
        def wrapper(*args: Any, **kwargs: Any) -> Tuple[Any, int]:
            attempt = 1
            delay = initial_delay

            while attempt <= max_attempts:
                try:
                    result = func(*args, **kwargs)
                    return result, attempt
                except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
                    if attempt == max_attempts:
                        # Final attempt failed, re-raise
                        raise

                    # Log retry attempt
                    logging.warning("Attempt %d/%d failed: %s", attempt, max_attempts, type(e).__name__)
                    logging.warning("Retrying in %ss...", delay)

                    time.sleep(delay)
                    delay *= backoff_multiplier
                    attempt += 1

        return wrapper
    return decorator

def load_config() -> Dict[str, str]:
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
    # Support comma-separated directories for multi-dir monitoring
    watch_dir_entries = [d.strip() for d in config['WATCH_DIR'].split(',') if d.strip()]
    if not watch_dir_entries:
        print("ERROR: WATCH_DIR must not be empty", file=sys.stderr)
        sys.exit(1)

    user_home = Path.home()

    for wd_entry in watch_dir_entries:
        try:
            watch_dir = Path(wd_entry).resolve()
        except Exception as e:
            print(f"ERROR: Invalid WATCH_DIR path: {wd_entry}: {e}", file=sys.stderr)
            sys.exit(1)

        if not watch_dir.is_absolute():
            print(f"ERROR: WATCH_DIR must be an absolute path (got: {wd_entry})", file=sys.stderr)
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
    for wd_entry in watch_dir_entries:
        if path_traversal.search(wd_entry):
            print("ERROR: WATCH_DIR contains path traversal sequence (..)", file=sys.stderr)
            sys.exit(1)

    if path_traversal.search(config['LOG_FILE']):
        print("ERROR: LOG_FILE contains path traversal sequence (..)", file=sys.stderr)
        sys.exit(1)

    return config

# Load configuration
config = load_config()
WATCH_DIRS = [d.strip() for d in config['WATCH_DIR'].split(',') if d.strip()]
WATCH_DIR = WATCH_DIRS[0]  # Backward compatibility: first dir
REMOTE_USER = config['REMOTE_USER']
REMOTE_HOST = config['REMOTE_HOST']
REMOTE_PORT = config['REMOTE_PORT']
REMOTE_PATH = config['REMOTE_PATH']
LOG_FILE = config['LOG_FILE']
DELETE_AFTER_SYNC = config.get('DELETE_AFTER_SYNC', 'false').lower() == 'true'

# Ensure log directory exists with secure permissions before configuring logging
log_path = Path(LOG_FILE)
log_dir = log_path.parent
if not log_dir.exists():
    log_dir.mkdir(parents=True, mode=0o700, exist_ok=True)

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        RotatingFileHandler(LOG_FILE, maxBytes=10*1024*1024, backupCount=5),
        logging.StreamHandler(sys.stdout)
    ]
)

class GCodeHandler(FileSystemEventHandler):
    """Handler for .gcode file events"""

    def __init__(self) -> None:
        self.syncing = set()  # Track files currently being synced
        self.syncing_lock = threading.Lock()  # Prevent race conditions

    def on_created(self, event: FileSystemEvent) -> None:
        """Called when a file is created"""
        if not event.is_directory and event.src_path.endswith('.gcode'):
            self.sync_file(event.src_path)

    def on_moved(self, event: FileSystemEvent) -> None:
        """Called when a file is moved into the directory"""
        if not event.is_directory and event.dest_path.endswith('.gcode'):
            self.sync_file(event.dest_path)

    def on_modified(self, event: FileSystemEvent) -> None:
        """Called when a file is modified (handles saves from some editors)"""
        if not event.is_directory and event.src_path.endswith('.gcode'):
            self.sync_file(event.src_path)

    def sync_file(self, file_path: str) -> None:
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
            # Check file is within any configured watch directory
            in_watch_dir = any(
                abs_file_path.startswith(os.path.abspath(wd) + os.sep)
                for wd in WATCH_DIRS
            )

            if not in_watch_dir:
                logging.error("Security: File outside watch directory: %s", file_path)
                logging.error("  File path: %s", abs_file_path)
                logging.error("  Watch dirs: %s", WATCH_DIRS)
                return

            # Security: Check it's a regular file (not symlink, directory, device, etc.)
            if not os.path.exists(abs_file_path):
                logging.warning("File no longer exists: %s", file_path)
                return

            if os.path.islink(abs_file_path):
                logging.error("Security: Refusing to sync symlink: %s", file_path)
                return

            if not os.path.isfile(abs_file_path):
                logging.warning("Skipping non-regular file: %s", file_path)
                return

            # Security: Validate file extension (defense in depth)
            if not abs_file_path.endswith('.gcode'):
                logging.warning("Skipping non-gcode file: %s", file_path)
                return

            # Validate file size to prevent DoS
            try:
                file_size = os.path.getsize(abs_file_path)
            except OSError as e:
                logging.error("Cannot determine file size: %s: %s", file_path, e)
                return

            if file_size < MIN_FILE_SIZE:
                logging.warning("Skipping empty file: %s", file_path)
                return

            if file_size > MAX_FILE_SIZE:
                logging.error("File too large: %s (%.2f MB)", file_path, file_size / (1024*1024))
                logging.error("Maximum allowed size: %.2f MB", MAX_FILE_SIZE / (1024*1024))
                return

            if file_size > WARN_FILE_SIZE:
                logging.warning("Large file detected: %s (%.2f MB)", file_path, file_size / (1024*1024))
                logging.warning("This may take several minutes to sync")

            logging.info("Syncing file: %s (%.2f MB)", abs_file_path, file_size / (1024*1024))

            # SECURITY: Re-validate immediately before rsync to prevent TOCTOU race condition
            # This closes the window where file could be replaced with symlink after validation
            if os.path.islink(abs_file_path):
                logging.error("Security: File became symlink after validation: %s", file_path)
                return

            if not os.path.isfile(abs_file_path):
                logging.error("Security: File changed type after validation: %s", file_path)
                return

            if not abs_file_path.endswith('.gcode'):
                logging.error("Security: File extension changed after validation: %s", file_path)
                return

            # Calculate dynamic timeout based on file size
            # Baseline: 2 minutes for small files, add 1 minute per 100 MB for large files
            timeout_seconds = max(RSYNC_TOTAL_TIMEOUT, int((file_size / (100 * 1024 * 1024)) * 60))

            logging.debug("Using timeout: %ds for %.2f MB file", timeout_seconds, file_size / (1024*1024))

            # Check remote disk space before syncing
            if not self.check_remote_disk_space(file_size):
                return

            # Build rsync command with timeouts
            rsync_cmd = [
                "rsync",
                "--stats",
                "--protect-args",
                "-avz",
                "--timeout=%d" % RSYNC_TIMEOUT,
                "-e", "ssh -p %s -o StrictHostKeyChecking=yes -o ConnectTimeout=10 -o ServerAliveInterval=5 -o ServerAliveCountMax=3" % REMOTE_PORT,
                abs_file_path,
                "%s@%s:%s" % (REMOTE_USER, REMOTE_HOST, shlex.quote(REMOTE_PATH if REMOTE_PATH.endswith('/') else REMOTE_PATH + '/'))
            ]

            # Execute rsync with retry logic (handles transient network failures)
            # Execute rsync immediately after re-validation (minimize TOCTOU window)
            sync_start = time.monotonic()
            result, attempts_used = self._execute_rsync_with_retry(rsync_cmd, timeout_seconds)
            duration = max(time.monotonic() - sync_start, 1e-6)
            mb_size = file_size / (1024 * 1024)
            transfer_rate = mb_size / duration if duration > 0 else float('inf')

            logging.info("Successfully synced: %s", os.path.basename(abs_file_path))
            send_notification("GCode Synced", "Successfully synced: %s" % os.path.basename(abs_file_path))

            # Delete local file after successful sync if configured
            if DELETE_AFTER_SYNC:
                try:
                    os.remove(abs_file_path)
                    logging.info("Deleted local file after sync: %s", os.path.basename(abs_file_path))
                except OSError as e:
                    logging.warning("Failed to delete local file after sync: %s: %s", abs_file_path, e)

            # Trigger USB gadget refresh
            usb_refresh_success = self.refresh_usb_gadget()

            stats = parse_rsync_stats(getattr(result, "stdout", ""))
            total_bytes_sent = stats.get("total_bytes_sent")
            total_bytes_received = stats.get("total_bytes_received")
            literal_data = stats.get("literal_data")
            matched_data = stats.get("matched_data")
            speedup_value = stats.get("speedup")

            refresh_status = "ok" if usb_refresh_success else "failed"
            rate_display = "inf" if transfer_rate == float('inf') else "%.2f" % transfer_rate
            bytes_sent_display = total_bytes_sent if total_bytes_sent is not None else "n/a"
            bytes_received_display = total_bytes_received if total_bytes_received is not None else "n/a"
            literal_display = literal_data if literal_data is not None else "n/a"
            matched_display = matched_data if matched_data is not None else "n/a"
            speedup_display = "%.2f" % speedup_value if speedup_value is not None else "n/a"

            summary_block = "\n".join([
                "==================== Sync Summary ====================",
                " File           : %s" % os.path.basename(abs_file_path),
                " Size           : %.2f MB" % mb_size,
                " Duration       : %.2f s" % duration,
                " Average Rate   : %s MB/s" % rate_display,
                " Attempts       : %s" % attempts_used,
                " USB Refresh    : %s" % refresh_status,
                " Bytes Sent     : %s" % bytes_sent_display,
                " Bytes Received : %s" % bytes_received_display,
                " Literal Data   : %s" % literal_display,
                " Matched Data   : %s" % matched_display,
                " Speedup        : %s" % speedup_display,
                "======================================================"
            ])
            logging.info(summary_block)

        except subprocess.TimeoutExpired:
            logging.error("Timeout syncing %s - transfer took longer than 2 minutes", file_path)
            send_notification("GCode Sync Failed", "Timeout syncing %s" % os.path.basename(file_path), "critical")
        except subprocess.CalledProcessError as e:
            logging.error("Failed to sync %s: %s", file_path, e)
            logging.error("STDERR: %s", e.stderr)
            send_notification("GCode Sync Failed", "Failed to sync %s" % os.path.basename(file_path), "critical")
        except Exception as e:
            logging.error("Unexpected error syncing %s: %s", file_path, e)
            send_notification("GCode Sync Error", "Unexpected error syncing %s" % os.path.basename(file_path), "critical")
        finally:
            with self.syncing_lock:
                self.syncing.discard(file_path)


    def check_remote_disk_space(self, file_size: int) -> bool:
        """Check if remote Pi has enough disk space for the file.

        Args:
            file_size: Size of the file to sync in bytes

        Returns:
            True if enough space (or check fails — non-blocking), False if insufficient
        """
        try:
            ssh_cmd = [
                "ssh",
                "-p", REMOTE_PORT,
                "-o", "StrictHostKeyChecking=yes",
                "-o", "ConnectTimeout=10",
                "%s@%s" % (REMOTE_USER, REMOTE_HOST),
                "df -B1 --output=avail %s | tail -1" % shlex.quote(REMOTE_PATH)
            ]
            result = subprocess.run(
                ssh_cmd,
                capture_output=True,
                text=True,
                check=True,
                timeout=15
            )
            avail_bytes = int(result.stdout.strip())
            if avail_bytes < file_size * 2:  # Require 2x file size as buffer
                logging.error("Insufficient disk space on Pi: %d bytes available, need %d",
                              avail_bytes, file_size * 2)
                return False
            logging.debug("Remote disk space OK: %d bytes available", avail_bytes)
            return True
        except Exception as e:
            logging.warning("Could not check remote disk space: %s (proceeding anyway)", e)
            return True  # Non-blocking: proceed on check failure

    @retry_on_failure()
    def _execute_rsync_with_retry(self, rsync_cmd: List[str], timeout_seconds: int) -> subprocess.CompletedProcess:
        """Execute rsync command with retry logic for transient failures.

        Args:
            rsync_cmd: List of command arguments for rsync
            timeout_seconds: Timeout in seconds for the operation

        Returns:
            Tuple[subprocess.CompletedProcess, int]: Result of the rsync operation and
            the attempt count (1-based) required for success.

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

    @retry_on_failure(max_attempts=3, initial_delay=2, backoff_multiplier=2)
    def _execute_usb_refresh_with_retry(self) -> bool:
        """Execute USB refresh with subprocess (called by retry decorator).

        Returns:
            bool: True if refresh succeeded

        Raises:
            subprocess.CalledProcessError: If refresh fails (triggers retry)
            subprocess.TimeoutExpired: If refresh times out (triggers retry)
        """
        ssh_cmd = [
            "ssh",
            "-p", REMOTE_PORT,
            "-o", "StrictHostKeyChecking=yes",
            "-o", "ConnectTimeout=10",
            "-o", "ServerAliveInterval=5",
            "-o", "ServerAliveCountMax=3",
            "%s@%s" % (REMOTE_USER, REMOTE_HOST),
            "sudo /usr/local/bin/refresh_usb_gadget.sh"
        ]

        result = subprocess.run(
            ssh_cmd,
            check=True,
            capture_output=True,
            text=True,
            timeout=USB_REFRESH_TIMEOUT
        )
        logging.info("USB gadget refreshed successfully")
        if result.stdout:
            logging.debug("Refresh output: %s", result.stdout.strip())
        return True

    def refresh_usb_gadget(self) -> bool:
        """Trigger USB gadget refresh on the Pi with retry logic.

        Returns:
            bool: True if refresh succeeded, False otherwise
        """
        try:
            result, attempts = self._execute_usb_refresh_with_retry()
            if attempts > 1:
                logging.info("USB refresh succeeded after %d attempts", attempts)
            return result

        except subprocess.TimeoutExpired:
            logging.error("USB gadget refresh timed out after all retries")
            logging.warning("File was synced but printer may not see it until Pi reboot")
            return False

        except subprocess.CalledProcessError as e:
            logging.error("USB gadget refresh failed after all retries (exit code %d)", e.returncode)
            if e.stderr:
                logging.error("Error details: %s", e.stderr.strip())
            logging.warning("File was synced but printer may not see it until Pi reboot")
            logging.info("To manually refresh: ssh %s@%s 'sudo /usr/local/bin/refresh_usb_gadget.sh'", REMOTE_USER, REMOTE_HOST)
            return False

        except Exception as e:
            logging.error("Unexpected error during USB gadget refresh: %s: %s", type(e).__name__, e)
            logging.warning("File was synced but printer may not see it")
            return False


def main() -> None:
    """Main function"""
    # Check if watchdog is installed
    try:
        import watchdog
    except ImportError:
        logging.warning("watchdog module not found. Installing...")
        req_file = SCRIPT_DIR / "requirements.txt"
        uv_exe = shutil.which("uv")
        try:
            if uv_exe:
                logging.info("Using uv to install Python dependencies")
                if req_file.exists():
                    subprocess.run([uv_exe, "pip", "install", "-r", str(req_file)], check=True)
                else:
                    subprocess.run([uv_exe, "pip", "install", "watchdog==3.0.0"], check=True)
            else:
                logging.info("Using pip to install Python dependencies")
                if req_file.exists():
                    subprocess.run([sys.executable, "-m", "pip", "install", "-r", str(req_file)], check=True)
                else:
                    subprocess.run([sys.executable, "-m", "pip", "install", "watchdog==3.0.0"], check=True)

            logging.info("Installation successful. Reloading module...")
            # Dynamic import after installation
            import watchdog
            logging.info("watchdog module loaded successfully. Continuing...")
        except subprocess.CalledProcessError as e:
            logging.error("Failed to install watchdog: %s", e)
            logging.error("Please install manually: pip install -r requirements.txt")
            sys.exit(1)

    # Create watch directories if they don't exist
    for watch_dir in WATCH_DIRS:
        os.makedirs(watch_dir, exist_ok=True)

    logging.info("Starting gcode file monitor on %s", WATCH_DIRS)
    logging.info("Will sync to %s@%s:%s:%s", REMOTE_USER, REMOTE_HOST, REMOTE_PORT, REMOTE_PATH)

    # Setup file system observer for each watch directory
    event_handler = GCodeHandler()
    observer = Observer()
    for watch_dir in WATCH_DIRS:
        observer.schedule(event_handler, watch_dir, recursive=False)
        logging.info("Watching directory: %s", watch_dir)

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
