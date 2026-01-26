#!/bin/bash
# Uninstall gcode-monitor service for testing

set -e

echo "=== Uninstalling gcode-monitor service ==="

# Stop service
echo "Stopping service..."
sudo systemctl stop gcode-monitor.service || true

# Disable service
echo "Disabling service..."
sudo systemctl disable gcode-monitor.service || true

# Remove service file
echo "Removing service file..."
sudo rm -f /etc/systemd/system/gcode-monitor.service

# Reload systemd
echo "Reloading systemd..."
sudo systemctl daemon-reload

# Reset failed state
sudo systemctl reset-failed || true

echo "✓ Service uninstalled successfully"
echo
echo "To verify: systemctl status gcode-monitor.service"
echo "Expected: Unit gcode-monitor.service could not be found."
