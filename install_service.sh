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

# Detect local subnet for systemd network restrictions
# Try multiple methods to find the default gateway/subnet
LOCAL_SUBNET=""
if command -v ip >/dev/null 2>&1; then
    # Method 1: Get default route gateway and derive subnet
    DEFAULT_GW=$(ip route | grep default | awk '{print $3}' | head -n1)
    if [ -n "$DEFAULT_GW" ]; then
        # Convert gateway IP to subnet (e.g., 192.168.1.1 -> 192.168.1.0/24)
        LOCAL_SUBNET=$(echo "$DEFAULT_GW" | sed 's/\.[0-9]*$/\.0\/24/')
    fi
fi

# Fallback: If ip command failed, try to detect from primary interface
if [ -z "$LOCAL_SUBNET" ] && command -v ip >/dev/null 2>&1; then
    PRIMARY_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n1)
    if [ -n "$PRIMARY_IP" ]; then
        LOCAL_SUBNET=$(echo "$PRIMARY_IP" | sed 's/\.[0-9]*$/\.0\/24/')
    fi
fi

# Final fallback: Use common private network range
if [ -z "$LOCAL_SUBNET" ]; then
    echo "WARNING: Could not auto-detect local subnet. Using default 192.168.1.0/24"
    echo "         If your network uses a different subnet, edit /etc/systemd/system/gcode-monitor.service"
    echo "         and change the IPAddressAllow line, then run: sudo systemctl daemon-reload"
    LOCAL_SUBNET="192.168.1.0/24"
fi

echo "Generating service file with your configuration..."
echo "  User: $USERNAME"
echo "  Home: $HOME_DIR"
echo "  Project: $PROJECT_DIR"
echo "  Watch Dir: $WATCH_DIR"
echo "  Local Subnet: $LOCAL_SUBNET"
echo

# Generate service file from template
sed -e "s|%USERNAME%|$USERNAME|g" \
    -e "s|%PROJECT_DIR%|$PROJECT_DIR|g" \
    -e "s|%HOME_DIR%|$HOME_DIR|g" \
    -e "s|%WATCH_DIR%|$WATCH_DIR|g" \
    -e "s|%LOCAL_SUBNET%|$LOCAL_SUBNET|g" \
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
