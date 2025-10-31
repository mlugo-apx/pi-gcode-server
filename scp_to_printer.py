#!/usr/bin/python3
"""
⚠️ DEPRECATED LEGACY SCRIPT ⚠️

This script is DEPRECATED and should NOT be used in production.
Use monitor_and_sync.py instead, which has:
- Proper configuration management (config.local)
- Secure subprocess handling (no shell=True)
- Input validation
- Better error handling
- Automatic file monitoring

This script is kept only for reference/backwards compatibility.
"""
import sys
import subprocess
import shlex
import glob
import re

def validate_config(port, remote_user, remote_host, remote_path):
    """Validate configuration to prevent injection attacks."""
    # Port must be numeric
    if not port.isdigit():
        raise ValueError(f"Port must be numeric, got: {port}")

    port_int = int(port)
    if port_int < 1 or port_int > 65535:
        raise ValueError(f"Port must be between 1-65535, got: {port_int}")

    # Check for dangerous characters
    dangerous = re.compile(r'[$`;\|&<>(){}]')

    if dangerous.search(remote_user):
        raise ValueError("remote_user contains invalid characters")
    if dangerous.search(remote_host):
        raise ValueError("remote_host contains invalid characters")
    if dangerous.search(remote_path):
        raise ValueError("remote_path contains invalid characters")

def scp_files(file_paths):
    # Hard-coded configurations (LEGACY - use config.local in monitor_and_sync.py instead)
    port = "9702"
    remote_user = "milugo"
    remote_host = "localhost"
    remote_path = "/mnt/usb_share"

    # Validate configuration
    try:
        validate_config(port, remote_user, remote_host, remote_path)
    except ValueError as e:
        print(f"Configuration error: {e}")
        sys.exit(1)

    for file_path in file_paths:
        # Use array-based subprocess call (NO shell=True)
        scp_command = [
            "scp",
            "-P", port,
            "-o", "StrictHostKeyChecking=yes",
            file_path,
            f"{remote_user}@{remote_host}:{remote_path}"
        ]

        # Running the SCP command
        try:
            subprocess.run(scp_command, check=True, shell=False)
            print(f"File '{file_path}' successfully transferred.")
        except subprocess.CalledProcessError as e:
            print(f"Error transferring file '{file_path}': {e}")

def ssh_and_commands():
    # Hard-coded configurations (LEGACY - use config.local in monitor_and_sync.py instead)
    port = "9702"
    remote_user = "milugo"
    remote_host = "localhost"

    # Validate configuration
    try:
        validate_config(port, remote_user, remote_host, "/tmp")  # dummy path for validation
    except ValueError as e:
        print(f"Configuration error: {e}")
        sys.exit(1)

    # Check if usbhid module is built-in (NO shell=True)
    try:
        result = subprocess.run(["lsmod"], capture_output=True, text=True, check=True)
        is_builtin = "usbhid" in result.stdout
    except subprocess.CalledProcessError as e:
        print(f"Error checking lsmod: {e}")
        is_builtin = True  # Assume built-in to avoid unnecessary reboot

    if not is_builtin:
        # Use array-based SSH command (NO shell=True)
        ssh_command = [
            "ssh",
            "-p", port,
            "-o", "StrictHostKeyChecking=yes",
            f"{remote_user}@{remote_host}",
            "sudo reboot"
        ]

        # Running the SSH command
        try:
            subprocess.run(ssh_command, check=True, shell=False)
            print("Reboot command sent successfully.")
        except subprocess.CalledProcessError as e:
            print(f"Error executing SSH command: {e}")
    else:
        print("USB-PI has been reloaded")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python script.py <file_path1> [<file_path2> ...]")
    else:
        file_paths = []
        for arg in sys.argv[1:]:
            file_paths.extend(glob.glob(arg))  # Handle wildcards and expand paths
        if not file_paths:
            print("No matching files found.")
        else:
            scp_files(file_paths)
            ssh_and_commands()
