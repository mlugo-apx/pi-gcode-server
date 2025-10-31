#!/bin/bash
# Quick script to run the GCode file monitor

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== GCode File Monitor ===${NC}"
echo
echo "This script will monitor ~/Desktop for .gcode files"
echo "and automatically sync them to your Pi at 192.168.1.6"
echo

# Check if inotify-tools is installed
if ! command -v inotifywait &> /dev/null; then
    echo -e "${YELLOW}Warning: inotifywait not found${NC}"
    echo "The bash monitor requires inotify-tools."
    echo
    echo "Please install it with:"
    echo "  sudo apt-get update && sudo apt-get install -y inotify-tools"
    echo
    echo "Alternatively, you can use the Python version if watchdog is installed:"
    echo "  pip install watchdog"
    echo "  $SCRIPT_DIR/monitor_and_sync.py"
    echo
    exit 1
fi

# Check SSH connection
echo "Testing SSH connection to Pi..."
if ! ssh -o ConnectTimeout=5 milugo@192.168.1.6 "echo 'Connected'" &>/dev/null; then
    echo -e "${YELLOW}Warning: Could not connect to Pi at 192.168.1.6${NC}"
    echo "Please ensure:"
    echo "  1. The Pi is powered on and connected to the network"
    echo "  2. SSH keys are set up for passwordless login"
    echo "  3. The Pi is accessible at 192.168.1.6"
    echo
    read -p "Continue anyway? [y/N]: " continue_anyway
    if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
        exit 1
    fi
else
    echo -e "${GREEN}✓ Connected to Pi${NC}"
fi
echo

echo -e "${GREEN}Starting file monitor...${NC}"
echo "Watching: ~/Desktop/*.gcode"
echo "Target: milugo@192.168.1.6:/mnt/usb_share/"
echo "Logs: ~/.gcode_sync.log"
echo
echo "Press Ctrl+C to stop"
echo
echo "---"
echo

exec "$SCRIPT_DIR/monitor_and_sync.sh"
