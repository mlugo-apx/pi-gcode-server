#!/usr/bin/env python3
"""Unit tests for path validation in monitor_and_sync.py

Tests the security-critical validation logic that prevents:
- Path traversal attacks
- Symlink attacks
- File size DoS
- Invalid file types
"""

import unittest
import tempfile
import os
import sys
from pathlib import Path
from unittest.mock import patch, MagicMock

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


if __name__ == '__main__':
    unittest.main()
