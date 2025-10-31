#!/bin/bash
# Install the GCode monitor as a systemd service

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing gcode-monitor.service..."
cp "$SCRIPT_DIR/gcode-monitor.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable gcode-monitor.service
systemctl start gcode-monitor.service

echo "✓ Service installed and started"
echo
echo "Check status:"
systemctl status gcode-monitor.service --no-pager
echo
echo "View logs: journalctl -u gcode-monitor.service -f"
