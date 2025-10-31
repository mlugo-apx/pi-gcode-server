#!/bin/bash
# Quick setup script for GCode auto-sync system

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== GCode Auto-Sync Setup ===${NC}"
echo

# Step 1: Choose monitor type
echo -e "${YELLOW}Step 1: Choose file monitor type${NC}"
echo "1) Bash monitor (simple, uses inotify-tools)"
echo "2) Python monitor (recommended, more robust)"
read -p "Enter choice [1-2]: " monitor_choice

if [ "$monitor_choice" = "1" ]; then
    MONITOR_SCRIPT="$SCRIPT_DIR/monitor_and_sync.sh"
    echo "Installing inotify-tools..."
    sudo apt-get update && sudo apt-get install -y inotify-tools
elif [ "$monitor_choice" = "2" ]; then
    MONITOR_SCRIPT="$SCRIPT_DIR/monitor_and_sync.py"
    echo "Installing Python watchdog..."
    pip install watchdog
else
    echo -e "${RED}Invalid choice${NC}"
    exit 1
fi

chmod +x "$MONITOR_SCRIPT"
echo -e "${GREEN}✓ Monitor script ready: $MONITOR_SCRIPT${NC}"
echo

# Step 2: Test SSH connection
echo -e "${YELLOW}Step 2: Testing SSH connection to Pi${NC}"
read -p "Use port forwarding (localhost:9702)? [Y/n]: " use_forwarding

if [[ "$use_forwarding" =~ ^[Nn]$ ]]; then
    read -p "Enter Pi hostname or IP [192.168.1.6]: " pi_host
    pi_host=${pi_host:-192.168.1.6}
    pi_port=22
else
    pi_host="localhost"
    pi_port=9702
fi

if ssh -p "$pi_port" -o ConnectTimeout=5 milugo@"$pi_host" "echo 'SSH connection successful'" 2>/dev/null; then
    echo -e "${GREEN}✓ SSH connection works${NC}"
else
    echo -e "${RED}✗ SSH connection failed${NC}"
    echo "Please check your SSH settings and try again"
    exit 1
fi
echo

# Step 3: Run diagnostic on Pi
echo -e "${YELLOW}Step 3: Running diagnostic on Pi${NC}"
read -p "Run USB gadget diagnostic? [Y/n]: " run_diagnostic

if [[ ! "$run_diagnostic" =~ ^[Nn]$ ]]; then
    echo "Running diagnostic..."
    ssh -p "$pi_port" milugo@"$pi_host" 'bash -s' < "$SCRIPT_DIR/pi_scripts/diagnose_usb_gadget.sh" | tee diagnostic_output.txt
    echo
    echo -e "${GREEN}✓ Diagnostic complete. Output saved to diagnostic_output.txt${NC}"
    echo
fi

# Step 4: Install refresh script on Pi
echo -e "${YELLOW}Step 4: Install USB gadget refresh script on Pi${NC}"
read -p "Install refresh script on Pi? [Y/n]: " install_refresh

if [[ ! "$install_refresh" =~ ^[Nn]$ ]]; then
    echo "Copying refresh script to Pi..."
    scp -P "$pi_port" "$SCRIPT_DIR/pi_scripts/refresh_usb_gadget.sh" milugo@"$pi_host":/tmp/

    echo "Installing on Pi (requires sudo)..."
    ssh -p "$pi_port" milugo@"$pi_host" << 'ENDSSH'
sudo mv /tmp/refresh_usb_gadget.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/refresh_usb_gadget.sh
sudo chown root:root /usr/local/bin/refresh_usb_gadget.sh
echo "Refresh script installed at /usr/local/bin/refresh_usb_gadget.sh"
ENDSSH

    echo -e "${GREEN}✓ Refresh script installed on Pi${NC}"
    echo
    echo "Testing refresh script..."
    if ssh -p "$pi_port" milugo@"$pi_host" "sudo /usr/local/bin/refresh_usb_gadget.sh" 2>&1 | grep -q "Complete"; then
        echo -e "${GREEN}✓ Refresh script works!${NC}"
    else
        echo -e "${YELLOW}⚠ Refresh script may need adjustment based on your USB gadget config${NC}"
    fi
    echo
fi

# Step 5: Configure sudoers
echo -e "${YELLOW}Step 5: Configure passwordless sudo for refresh script${NC}"
read -p "Add sudoers entry for refresh script? [Y/n]: " config_sudo

if [[ ! "$config_sudo" =~ ^[Nn]$ ]]; then
    ssh -p "$pi_port" milugo@"$pi_host" << 'ENDSSH'
if sudo grep -q "refresh_usb_gadget" /etc/sudoers; then
    echo "Sudoers entry already exists"
else
    echo "Adding sudoers entry..."
    echo "milugo ALL=(ALL) NOPASSWD: /usr/local/bin/refresh_usb_gadget.sh" | sudo EDITOR='tee -a' visudo -f /etc/sudoers.d/usb_gadget_refresh
    sudo chmod 0440 /etc/sudoers.d/usb_gadget_refresh
    echo "Sudoers entry added"
fi
ENDSSH
    echo -e "${GREEN}✓ Sudoers configured${NC}"
    echo
fi

# Step 6: Test the monitor
echo -e "${YELLOW}Step 6: Test the file monitor${NC}"
read -p "Start monitor in test mode? [Y/n]: " test_monitor

if [[ ! "$test_monitor" =~ ^[Nn]$ ]]; then
    echo "Starting monitor in test mode (Ctrl+C to stop)..."
    echo "Try saving a .gcode file to ~/Desktop to test"
    "$MONITOR_SCRIPT"
fi
echo

# Step 7: Install as service
echo -e "${YELLOW}Step 7: Install as systemd service${NC}"
read -p "Install as systemd service for automatic startup? [y/N]: " install_service

if [[ "$install_service" =~ ^[Yy]$ ]]; then
    # Update service file with correct script path
    sed "s|ExecStart=.*|ExecStart=$MONITOR_SCRIPT|" "$SCRIPT_DIR/gcode-monitor.service" > /tmp/gcode-monitor.service

    sudo cp /tmp/gcode-monitor.service /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable gcode-monitor.service
    sudo systemctl start gcode-monitor.service

    echo -e "${GREEN}✓ Service installed and started${NC}"
    echo
    echo "Check status with: sudo systemctl status gcode-monitor.service"
    echo "View logs with: journalctl -u gcode-monitor.service -f"
fi

echo
echo -e "${GREEN}=== Setup Complete ===${NC}"
echo
echo "Next steps:"
echo "1. Download a .gcode file to ~/Desktop"
echo "2. Check logs: tail -f ~/.gcode_sync.log"
echo "3. Verify file appears on 3D printer"
echo
echo "For more information, see README.md"
