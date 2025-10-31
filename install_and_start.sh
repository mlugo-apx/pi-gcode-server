#!/bin/bash
# Complete installation and startup script
# This will install dependencies, set up the service, and start monitoring

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Load configuration or use defaults
CONFIG_FILE="$SCRIPT_DIR/config.local"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    echo -e "${GREEN}Using configuration from config.local${NC}"
else
    echo -e "${YELLOW}⚠️  config.local not found, using defaults${NC}"
    REMOTE_USER="milugo"
    REMOTE_HOST="192.168.1.6"
    REMOTE_PORT="22"
fi

echo -e "${GREEN}=== GCode Auto-Sync Installation ===${NC}"
echo

# Step 1: Install inotify-tools
echo -e "${YELLOW}Step 1: Installing inotify-tools...${NC}"
if command -v inotifywait &> /dev/null; then
    echo -e "${GREEN}✓ inotify-tools already installed${NC}"
else
    echo "Installing inotify-tools (requires sudo)..."
    sudo apt-get update
    sudo apt-get install -y inotify-tools
    echo -e "${GREEN}✓ inotify-tools installed${NC}"
fi
echo

# Step 2: Verify SSH connection
echo -e "${YELLOW}Step 2: Installing Python dependencies...${NC}"
if command -v uv &> /dev/null; then
    echo "Using uv to install requirements..."
    uv pip install --upgrade -r "$SCRIPT_DIR/requirements.txt"
else
    echo "Using pip to install requirements..."
    python3 -m pip install --upgrade --user -r "$SCRIPT_DIR/requirements.txt"
fi
echo

# Step 3: Verify SSH connection
echo -e "${YELLOW}Step 3: Testing SSH connection to Pi at ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PORT}...${NC}"
if ssh -p "$REMOTE_PORT" -o ConnectTimeout=5 "${REMOTE_USER}@${REMOTE_HOST}" "echo 'Connection successful'" &>/dev/null; then
    echo -e "${GREEN}✓ SSH connection works${NC}"
else
    echo -e "${RED}✗ Cannot connect to Pi at ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PORT}${NC}"
    echo "Please check:"
    echo "  1. Pi is powered on"
    echo "  2. Pi is on the network"
    echo "  3. SSH is enabled on the Pi"
    exit 1
fi
echo

# Step 4: Quick test
echo -e "${YELLOW}Step 4: Running quick test...${NC}"
if "$SCRIPT_DIR/test_sync.sh"; then
    echo -e "${GREEN}✓ Test passed${NC}"
else
    echo -e "${RED}✗ Test failed${NC}"
    exit 1
fi
echo

# Step 5: Install as systemd service
echo -e "${YELLOW}Step 5: Install as systemd service?${NC}"
read -p "Install as systemd service (auto-start on boot)? [Y/n]: " install_service

if [[ ! "$install_service" =~ ^[Nn]$ ]]; then
    echo "Installing systemd service..."
    sudo cp "$SCRIPT_DIR/gcode-monitor.service" /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable gcode-monitor.service
    sudo systemctl start gcode-monitor.service

    echo -e "${GREEN}✓ Service installed and started${NC}"
    echo
    echo "Service status:"
    sudo systemctl status gcode-monitor.service --no-pager -l
    echo
    echo "To view logs: journalctl -u gcode-monitor.service -f"
    echo "To stop: sudo systemctl stop gcode-monitor.service"
else
    echo "Skipping service installation"
    echo
    echo -e "${YELLOW}Starting monitor manually...${NC}"
    echo "Press Ctrl+C to stop"
    echo
    exec "$SCRIPT_DIR/monitor_and_sync.sh"
fi

echo
echo -e "${GREEN}=== Installation Complete! ===${NC}"
echo
echo "Your system is now monitoring ~/Desktop for .gcode files"
echo "When you save a .gcode file, it will automatically:"
echo "  1. Sync to Pi at 192.168.1.6:/mnt/usb_share/"
echo "  2. Refresh the USB gadget"
echo "  3. Appear on your 3D printer in ~3-5 seconds"
echo
echo "Logs: tail -f ~/.gcode_sync.log"
