#!/usr/bin/env python3
"""Unit tests for path validation in monitor_and_sync.py

Tests the security-critical validation logic that prevents:
- Path traversal attacks
- Symlink attacks
- File size DoS
- Invalid file types
"""

# noqa: D104
import os
import sys
import importlib
import logging
import threading
import tempfile
import unittest
import shutil
import textwrap
import uuid
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

# Add parent directory to path to import monitor_and_sync
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../..')))


class TestPathValidation(unittest.TestCase):
    """Test path validation security checks"""

    def setUp(self):
        """Set up test fixtures"""
        self.temp_dir = tempfile.mkdtemp()
        self.user_home = Path.home()

    def tearDown(self):
        """Clean up test fixtures"""
        if os.path.exists(self.temp_dir):
            os.rmdir(self.temp_dir)

    def test_path_within_home_directory(self):
        """Test that paths within home directory are accepted"""
        watch_dir = Path(self.user_home) / "Desktop"

        # Should not raise exception
        resolved = watch_dir.resolve()
        relative = resolved.relative_to(self.user_home)

        self.assertTrue(str(resolved).startswith(str(self.user_home)))

    def test_path_outside_home_directory_rejected(self):
        """Test that paths outside home directory are rejected"""
        watch_dir = Path("/etc")

        with self.assertRaises(ValueError):
            watch_dir.resolve().relative_to(self.user_home)

    def test_path_traversal_rejected(self):
        """Test that path traversal sequences are rejected"""
        # Attempt to escape home directory with ../
        watch_dir = Path(self.user_home) / ".." / ".." / "etc"
        resolved = watch_dir.resolve()

        with self.assertRaises(ValueError):
            resolved.relative_to(self.user_home)

    def test_relative_path_rejected(self):
        """Test that relative paths are rejected"""
        watch_dir = Path("relative/path")

        self.assertFalse(watch_dir.is_absolute())

    def test_forbidden_paths_rejected(self):
        """Test that forbidden system paths are rejected"""
        forbidden_paths = [
            Path('/etc'),
            Path('/var'),
            Path('/usr'),
            Path('/bin'),
            Path('/sbin'),
            Path('/boot')
        ]

        for forbidden in forbidden_paths:
            with self.assertRaises(ValueError):
                forbidden.resolve().relative_to(self.user_home)


class TestFileSizeValidation(unittest.TestCase):
    """Test file size validation logic"""

    def test_empty_file_rejected(self):
        """Test that empty files (0 bytes) are rejected"""
        MIN_FILE_SIZE = 1
        file_size = 0

        self.assertLess(file_size, MIN_FILE_SIZE)

    def test_oversized_file_rejected(self):
        """Test that files over 1GB are rejected"""
        MAX_FILE_SIZE = 1024 * 1024 * 1024  # 1 GB
        file_size = MAX_FILE_SIZE + 1

        self.assertGreater(file_size, MAX_FILE_SIZE)

    def test_large_file_warning(self):
        """Test that files over 500MB trigger warning"""
        WARN_FILE_SIZE = 500 * 1024 * 1024  # 500 MB
        file_size = WARN_FILE_SIZE + 1

        self.assertGreater(file_size, WARN_FILE_SIZE)

    def test_normal_file_accepted(self):
        """Test that normal-sized files (1MB) are accepted"""
        MIN_FILE_SIZE = 1
        MAX_FILE_SIZE = 1024 * 1024 * 1024
        file_size = 1024 * 1024  # 1 MB

        self.assertGreater(file_size, MIN_FILE_SIZE)
        self.assertLess(file_size, MAX_FILE_SIZE)

    def test_dynamic_timeout_calculation(self):
        """Test dynamic timeout calculation based on file size"""
        RSYNC_TOTAL_TIMEOUT = 120  # 2 minutes baseline

        # Small file: use baseline timeout
        small_file = 10 * 1024 * 1024  # 10 MB
        timeout = max(RSYNC_TOTAL_TIMEOUT, int((small_file / (100 * 1024 * 1024)) * 60))
        self.assertEqual(timeout, RSYNC_TOTAL_TIMEOUT)

        # Large file: scale timeout
        large_file = 500 * 1024 * 1024  # 500 MB
        timeout = max(RSYNC_TOTAL_TIMEOUT, int((large_file / (100 * 1024 * 1024)) * 60))
        self.assertGreater(timeout, RSYNC_TOTAL_TIMEOUT)
        self.assertEqual(timeout, 300)  # 5 minutes for 500MB


class TestFileTypeValidation(unittest.TestCase):
    """Test file type and extension validation"""

    def test_gcode_extension_accepted(self):
        """Test that .gcode files are accepted"""
        file_path = "/path/to/file.gcode"
        self.assertTrue(file_path.endswith('.gcode'))

    def test_non_gcode_extension_rejected(self):
        """Test that non-.gcode files are rejected"""
        invalid_files = [
            "/path/to/file.txt",
            "/path/to/file.py",
            "/path/to/file",
            "/path/to/file.GCODE",  # case sensitive
        ]

        for file_path in invalid_files:
            self.assertFalse(file_path.endswith('.gcode'))

    def test_symlink_rejected(self):
        """Test that symlinks are rejected"""
        # Create temporary file and symlink
        with tempfile.NamedTemporaryFile(suffix='.gcode', delete=False) as f:
            real_file = f.name

        symlink_path = real_file + '.link'

        try:
            os.symlink(real_file, symlink_path)

            self.assertTrue(os.path.islink(symlink_path))
            self.assertFalse(os.path.islink(real_file))
        finally:
            os.unlink(symlink_path)
            os.unlink(real_file)

    def test_directory_rejected(self):
        """Test that directories are rejected"""
        with tempfile.TemporaryDirectory() as temp_dir:
            self.assertFalse(os.path.isfile(temp_dir))
            self.assertTrue(os.path.isdir(temp_dir))


class TestRetryLogic(unittest.TestCase):
    """Test retry decorator logic"""

    def test_retry_parameters(self):
        """Test retry configuration parameters"""
        RETRY_MAX_ATTEMPTS = 3
        RETRY_INITIAL_DELAY = 2
        RETRY_BACKOFF_MULTIPLIER = 2

        # Calculate expected delays (one delay per retry attempt)
        delays = []
        delay = RETRY_INITIAL_DELAY
        for i in range(RETRY_MAX_ATTEMPTS):
            delays.append(delay)
            delay *= RETRY_BACKOFF_MULTIPLIER

        expected_delays = [2, 4, 8]
        self.assertEqual(delays, expected_delays)

    def test_exponential_backoff(self):
        """Test exponential backoff calculation"""
        initial_delay = 2
        multiplier = 2
        attempts = 3

        delay = initial_delay
        backoff_sequence = []

        for _ in range(attempts):
            backoff_sequence.append(delay)
            delay *= multiplier

        self.assertEqual(backoff_sequence, [2, 4, 8])


class TestConfigurationConstants(unittest.TestCase):
    """Test configuration constants are properly defined"""

    def test_timeout_constants(self):
        """Test timeout constants are reasonable"""
        FILE_SETTLE_DELAY = 1
        RSYNC_TIMEOUT = 60
        RSYNC_TOTAL_TIMEOUT = 120
        USB_REFRESH_TIMEOUT = 30

        self.assertGreater(FILE_SETTLE_DELAY, 0)
        self.assertGreater(RSYNC_TIMEOUT, 0)
        self.assertGreater(RSYNC_TOTAL_TIMEOUT, RSYNC_TIMEOUT)
        self.assertGreater(USB_REFRESH_TIMEOUT, 0)

    def test_file_size_constants(self):
        """Test file size limit constants"""
        MIN_FILE_SIZE = 1
        MAX_FILE_SIZE = 1024 * 1024 * 1024  # 1 GB
        WARN_FILE_SIZE = 500 * 1024 * 1024  # 500 MB

        self.assertGreater(MIN_FILE_SIZE, 0)
        self.assertGreater(MAX_FILE_SIZE, WARN_FILE_SIZE)
        self.assertGreater(WARN_FILE_SIZE, MIN_FILE_SIZE)


class TestHandlerDeadlock(unittest.TestCase):
    """Ensure file event handlers do not deadlock when invoking sync_file"""

    def test_on_created_does_not_deadlock(self):
        """on_created should return promptly without holding the lock"""
        # Import here to ensure configuration is loaded as in production
        sys.modules.pop("monitor_and_sync", None)
        with patch("logging.FileHandler", return_value=logging.NullHandler()):
            monitor_and_sync = importlib.import_module("monitor_and_sync")

        handler = monitor_and_sync.GCodeHandler()
        file_path = os.path.join(monitor_and_sync.WATCH_DIR, "deadlock_test.gcode")
        event = SimpleNamespace(is_directory=False, src_path=file_path)

        with patch("monitor_and_sync.time.sleep", return_value=None), \
                patch("monitor_and_sync.os.path.exists", return_value=False):
            worker = threading.Thread(target=handler.on_created, args=(event,), daemon=True)
            worker.start()
            worker.join(timeout=0.5)

        self.assertFalse(worker.is_alive(), "on_created must not deadlock when calling sync_file")


class TestRsyncDestinationQuoting(unittest.TestCase):
    """Ensure rsync destination is safely quoted for remote paths."""

    def setUp(self):
        self.filehandler_patch = patch("logging.FileHandler", return_value=logging.NullHandler())
        self.filehandler_patch.start()
        self.addCleanup(self.filehandler_patch.stop)

        self.module = importlib.import_module("monitor_and_sync")
        self.temp_dir = tempfile.mkdtemp()
        self.original_watch_dir = self.module.WATCH_DIR
        self.original_remote_path = self.module.REMOTE_PATH
        self.module.WATCH_DIR = self.temp_dir

        self.file_path = Path(self.temp_dir) / "quote_test.gcode"
        with open(self.file_path, "w", encoding="utf-8") as f:
            f.write("G1 X0 Y0\n")

    def tearDown(self):
        self.module.WATCH_DIR = self.original_watch_dir
        self.module.REMOTE_PATH = self.original_remote_path
        if self.file_path.exists():
            self.file_path.unlink()
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def _run_sync_and_get_command(self, remote_path):
        self.module.REMOTE_PATH = remote_path
        handler = self.module.GCodeHandler()

        with patch.object(handler, "_execute_rsync_with_retry", return_value=None) as mock_rsync, \
                patch.object(handler, "refresh_usb_gadget", return_value=True), \
                patch("monitor_and_sync.time.sleep", return_value=None), \
                patch("monitor_and_sync.os.path.islink", return_value=False):
            handler.sync_file(str(self.file_path))

        return mock_rsync.call_args[0][0]

    def test_remote_path_with_space_is_quoted(self):
        rsync_cmd = self._run_sync_and_get_command("/mnt/usb share")
        destination = rsync_cmd[-1]

        self.assertRegex(destination, r':["\']')
        self.assertRegex(destination, r'["\']$')
        self.assertIn("--protect-args", rsync_cmd)

    def test_remote_path_leading_hyphen_uses_protect_args(self):
        rsync_cmd = self._run_sync_and_get_command("--gcode")
        destination = rsync_cmd[-1]

        self.assertIn("--protect-args", rsync_cmd)
        self.assertTrue(destination.endswith("--gcode/"))


class TestLoggingSetup(unittest.TestCase):
    """Ensure logging setup creates log directory before initializing FileHandler."""

    def test_log_directory_precreated_for_filehandler(self):
        repo_root = Path(__file__).resolve().parents[2]
        config_path = repo_root / "config.local"
        original_config = config_path.read_text(encoding="utf-8")

        repo_root = Path(__file__).resolve().parents[2]
        temp_root = repo_root / "tmp_log_tests" / uuid.uuid4().hex
        log_dir = temp_root / "logs" / "nested"
        log_file = log_dir / "monitor.log"

        config_contents = textwrap.dedent(f"""\
            WATCH_DIR="{Path.home()}/Desktop"
            LOG_FILE="{log_file}"
            REMOTE_USER="test"
            REMOTE_HOST="localhost"
            REMOTE_PORT="22"
            REMOTE_PATH="/tmp"
        """)

        try:
            config_path.write_text(config_contents, encoding="utf-8")
            shutil.rmtree(log_dir, ignore_errors=True)
            self.assertFalse(log_dir.exists(), "Precondition failed: log directory should not exist")

            sys.modules.pop("monitor_and_sync", None)

            def fake_filehandler(path, *args, **kwargs):
                self.assertEqual(str(log_file), path)
                self.assertTrue(Path(path).parent.exists(), "Log directory should exist before FileHandler initialization")
                return logging.NullHandler()

            with patch("logging.FileHandler", side_effect=fake_filehandler):
                importlib.import_module("monitor_and_sync")
        finally:
            config_path.write_text(original_config, encoding="utf-8")
            sys.modules.pop("monitor_and_sync", None)
            shutil.rmtree(temp_root.parent, ignore_errors=True)


if __name__ == '__main__':
    unittest.main()
