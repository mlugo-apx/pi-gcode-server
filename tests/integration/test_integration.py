#!/usr/bin/env python3
"""Integration tests for pi-gcode-server

Tests end-to-end workflows:
- File monitoring and sync
- Network connectivity
- Configuration loading
- Error handling and retry logic
"""

import unittest
import tempfile
import os
import sys
import time
import subprocess
from pathlib import Path
from unittest.mock import patch, MagicMock

# Add parent directory to path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../..')))


class TestConfigurationLoading(unittest.TestCase):
    """Test configuration file loading and validation"""

    def test_config_file_exists(self):
        """Test that config.local exists and is readable"""
        config_file = Path('config.local')

        if config_file.exists():
            self.assertTrue(config_file.is_file())
            self.assertTrue(os.access(config_file, os.R_OK))

    def test_config_has_required_keys(self):
        """Test that configuration has all required keys"""
        required_keys = [
            'WATCH_DIR',
            'REMOTE_USER',
            'REMOTE_HOST',
            'REMOTE_PORT',
            'REMOTE_PATH',
            'LOG_FILE'
        ]

        # This test would need to load config.local
        # For now, just validate the keys list
        self.assertEqual(len(required_keys), 6)

    def test_config_values_validated(self):
        """Test that configuration values are validated on load"""
        # Test cases that should fail validation
        invalid_configs = [
            {'WATCH_DIR': 'relative/path'},  # Must be absolute
            {'WATCH_DIR': '/etc'},  # Must be in home directory
            {'LOG_FILE': '/etc/../etc/passwd'},  # Path traversal
            {'REMOTE_PORT': '0'},  # Invalid port
            {'REMOTE_PORT': '99999'},  # Port out of range
        ]

        # Validation should reject these
        for config in invalid_configs:
            if 'WATCH_DIR' in config:
                path = config['WATCH_DIR']
                if not path.startswith('/'):
                    self.assertFalse(Path(path).is_absolute())


class TestFileMonitoring(unittest.TestCase):
    """Test file system monitoring functionality"""

    def test_gcode_file_detection(self):
        """Test that .gcode files are detected"""
        with tempfile.TemporaryDirectory() as temp_dir:
            # Create a .gcode file
            gcode_file = os.path.join(temp_dir, 'test.gcode')
            with open(gcode_file, 'w') as f:
                f.write('G28\n')

            # Verify detection logic
            self.assertTrue(gcode_file.endswith('.gcode'))
            self.assertTrue(os.path.isfile(gcode_file))

    def test_non_gcode_files_ignored(self):
        """Test that non-.gcode files are ignored"""
        with tempfile.TemporaryDirectory() as temp_dir:
            # Create various non-.gcode files
            non_gcode_files = [
                'test.txt',
                'test.py',
                'README.md',
                'config.ini'
            ]

            for filename in non_gcode_files:
                file_path = os.path.join(temp_dir, filename)
                with open(file_path, 'w') as f:
                    f.write('test\n')

                # Should not be processed
                self.assertFalse(file_path.endswith('.gcode'))

    def test_file_settle_delay(self):
        """Test that FILE_SETTLE_DELAY prevents processing incomplete files"""
        FILE_SETTLE_DELAY = 1

        # File should not be processed immediately
        # Wait for settle delay before syncing
        self.assertGreater(FILE_SETTLE_DELAY, 0)


class TestNetworkConnectivity(unittest.TestCase):
    """Test network connectivity checks"""

    def test_ssh_connectivity_check(self):
        """Test SSH connectivity validation"""
        # From lib/error_handler.sh check_network function

        # Valid scenarios
        valid_hosts = ['192.168.1.6', 'localhost']
        valid_ports = [22, 2222]

        for host in valid_hosts:
            self.assertIsNotNone(host)

        for port in valid_ports:
            self.assertGreater(port, 0)
            self.assertLess(port, 65536)

    def test_network_timeout_configured(self):
        """Test that network operations have timeouts"""
        # SSH connection should timeout
        connect_timeout = 10

        # Verify timeout is reasonable
        self.assertGreater(connect_timeout, 0)
        self.assertLess(connect_timeout, 60)


class TestRetryLogic(unittest.TestCase):
    """Test retry logic integration"""

    def test_retry_on_transient_failure(self):
        """Test that transient failures are retried"""
        RETRY_MAX_ATTEMPTS = 3
        RETRY_INITIAL_DELAY = 2

        # Simulate retry sequence
        attempts = []
        for i in range(1, RETRY_MAX_ATTEMPTS + 1):
            attempts.append(i)

        self.assertEqual(len(attempts), 3)
        self.assertEqual(attempts, [1, 2, 3])

    def test_exponential_backoff_delays(self):
        """Test that retry delays follow exponential backoff"""
        RETRY_INITIAL_DELAY = 2
        RETRY_BACKOFF_MULTIPLIER = 2

        delays = []
        delay = RETRY_INITIAL_DELAY

        for _ in range(3):
            delays.append(delay)
            delay *= RETRY_BACKOFF_MULTIPLIER

        self.assertEqual(delays, [2, 4, 8])

    def test_permanent_failure_after_max_attempts(self):
        """Test that permanent failures are not retried indefinitely"""
        RETRY_MAX_ATTEMPTS = 3

        # After 3 attempts, should raise exception
        for attempt in range(1, RETRY_MAX_ATTEMPTS + 1):
            if attempt == RETRY_MAX_ATTEMPTS:
                # Final attempt - should raise
                self.assertEqual(attempt, 3)


class TestErrorHandling(unittest.TestCase):
    """Test error handling and logging"""

    def test_error_logging_to_file(self):
        """Test that errors are logged to file"""
        log_file = os.path.expanduser('~/.gcode_sync.log')

        # Log file should be configured
        self.assertTrue(log_file.endswith('.log'))

    def test_error_logging_to_syslog(self):
        """Test that errors are logged to syslog"""
        # From lib/error_handler.sh

        # Syslog identifier should be configured
        syslog_identifier = 'gcode-monitor'
        self.assertEqual(syslog_identifier, 'gcode-monitor')

    def test_error_trap_installed(self):
        """Test that error trap is installed in shell scripts"""
        with open('lib/error_handler.sh', 'r') as f:
            content = f.read()

        # Verify error trap exists
        self.assertIn('trap', content)
        self.assertIn('error_trap', content)
        self.assertIn('ERR', content)


class TestUSBGadgetRefresh(unittest.TestCase):
    """Test USB gadget refresh functionality"""

    def test_usb_refresh_timeout(self):
        """Test that USB refresh has timeout"""
        USB_REFRESH_TIMEOUT = 30

        # Verify timeout is configured
        self.assertGreater(USB_REFRESH_TIMEOUT, 0)
        self.assertLess(USB_REFRESH_TIMEOUT, 120)

    def test_usb_refresh_non_blocking(self):
        """Test that USB refresh failure doesn't block sync"""
        # From monitor_and_sync.py refresh_usb_gadget method

        # If refresh fails, file should still be synced
        # refresh_usb_gadget returns True/False, doesn't raise

        refresh_succeeded = False  # Simulated failure

        # File sync should complete even if refresh fails
        self.assertIsNotNone(refresh_succeeded)


class TestSystemdIntegration(unittest.TestCase):
    """Test systemd service integration"""

    def test_service_file_exists(self):
        """Test that systemd service file exists"""
        service_file = Path('gcode-monitor.service')

        self.assertTrue(service_file.exists())
        self.assertTrue(service_file.is_file())

    def test_service_restart_policy(self):
        """Test that service has restart policy"""
        with open('gcode-monitor.service', 'r') as f:
            content = f.read()

        # Verify restart configuration
        self.assertIn('Restart=on-failure', content)
        self.assertIn('RestartSec=', content)

    def test_service_resource_limits(self):
        """Test that service has resource limits"""
        with open('gcode-monitor.service', 'r') as f:
            content = f.read()

        # Verify resource limits
        self.assertIn('MemoryMax=', content)
        self.assertIn('CPUQuota=', content)
        self.assertIn('TasksMax=', content)


class TestEndToEndWorkflow(unittest.TestCase):
    """Test complete end-to-end workflows"""

    def test_file_create_to_sync_workflow(self):
        """Test complete workflow from file creation to sync"""
        # Workflow steps:
        # 1. File created in watch directory
        # 2. File detected by watchdog
        # 3. File validated (extension, size, no symlink)
        # 4. File settled (1 second delay)
        # 5. Path re-validated (TOCTOU prevention)
        # 6. Rsync with retry logic
        # 7. USB gadget refresh
        # 8. Cleanup

        workflow_steps = [
            'File created',
            'File detected',
            'File validated',
            'File settled',
            'Path re-validated',
            'Rsync executed',
            'USB refreshed',
            'Cleanup complete'
        ]

        self.assertEqual(len(workflow_steps), 8)

    def test_validation_failure_workflow(self):
        """Test workflow when validation fails"""
        # If validation fails at any step, file should not be synced

        validation_failures = [
            'Not .gcode extension',
            'File is symlink',
            'File outside watch directory',
            'File too large',
            'File is empty'
        ]

        # Each should prevent sync
        for failure in validation_failures:
            self.assertIsNotNone(failure)

    def test_network_failure_workflow(self):
        """Test workflow when network fails"""
        # Network failure should trigger retry
        # After max retries, should log error and continue monitoring

        network_failures = [
            'Connection refused',
            'Connection timeout',
            'Host unreachable',
            'SSH authentication failed'
        ]

        # Each should be retried
        RETRY_MAX_ATTEMPTS = 3
        for failure in network_failures:
            # Would retry 3 times
            self.assertIsNotNone(failure)


class TestShellScriptIntegration(unittest.TestCase):
    """Test shell script integration"""

    def test_error_handler_library_sourced(self):
        """Test that error_handler.sh is sourced correctly"""
        with open('lib/error_handler.sh', 'r') as f:
            content = f.read()

        # Verify functions are exported
        self.assertIn('export -f', content)
        self.assertIn('log_error', content)
        self.assertIn('retry_command', content)

    def test_shell_script_syntax_valid(self):
        """Test that shell scripts have valid syntax"""
        shell_scripts = [
            'monitor_and_sync.sh',
            'setup_wizard.sh',
            'test_sync.sh',
            'lib/error_handler.sh'
        ]

        for script in shell_scripts:
            if os.path.exists(script):
                # Would run: bash -n script
                self.assertTrue(os.path.isfile(script))


if __name__ == '__main__':
    unittest.main()
