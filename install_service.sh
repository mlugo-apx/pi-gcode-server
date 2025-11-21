#!/bin/bash
# Install the GCode monitor as a systemd service
# This script generates a service file from the template with user-specific paths

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.local"

# Load configuration to get WATCH_DIR
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "ERROR: config.local not found. Please run setup_wizard.sh first."
    exit 1
fi

# Detect username and home directory
USERNAME="${USER}"
HOME_DIR="${HOME}"
PROJECT_DIR="$SCRIPT_DIR"

# Use WATCH_DIR from config, or default to Desktop
WATCH_DIR="${WATCH_DIR:-$HOME/Desktop}"

echo "Generating service file with your configuration..."
echo "  User: $USERNAME"
echo "  Home: $HOME_DIR"
echo "  Project: $PROJECT_DIR"
echo "  Watch Dir: $WATCH_DIR"
echo

# Generate service file from template
sed -e "s|%USERNAME%|$USERNAME|g" \
    -e "s|%PROJECT_DIR%|$PROJECT_DIR|g" \
    -e "s|%HOME_DIR%|$HOME_DIR|g" \
    -e "s|%WATCH_DIR%|$WATCH_DIR|g" \
    "$SCRIPT_DIR/gcode-monitor.service" > /tmp/gcode-monitor.service

echo "Installing gcode-monitor.service..."
sudo cp /tmp/gcode-monitor.service /etc/systemd/system/
rm /tmp/gcode-monitor.service

sudo systemctl daemon-reload
sudo systemctl enable gcode-monitor.service
sudo systemctl start gcode-monitor.service

echo "✓ Service installed and started"
echo
echo "Check status:"
sudo systemctl status gcode-monitor.service --no-pager
echo
echo "View logs: journalctl -u gcode-monitor.service -f"
