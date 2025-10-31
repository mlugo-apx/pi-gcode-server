#!/bin/bash
# Deployment script for security-hardened gcode-monitor service
# Run this script to deploy all changes to the running service

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== GCode Monitor Deployment ===${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}This script requires sudo privileges${NC}"
    echo "Re-running with sudo..."
    exec sudo bash "$0" "$@"
fi

# Step 1: Reload systemd configuration
echo -e "${YELLOW}[1/3] Reloading systemd daemon...${NC}"
systemctl daemon-reload
echo -e "${GREEN}✓ Systemd daemon reloaded${NC}"
echo ""

# Step 2: Restart service with new security hardening
echo -e "${YELLOW}[2/3] Restarting gcode-monitor service...${NC}"
systemctl restart gcode-monitor.service
sleep 2
echo -e "${GREEN}✓ Service restarted${NC}"
echo ""

# Step 3: Verify service status
echo -e "${YELLOW}[3/3] Verifying service status...${NC}"
if systemctl is-active --quiet gcode-monitor.service; then
    echo -e "${GREEN}✓ Service is running${NC}"
    echo ""
    systemctl status gcode-monitor.service --no-pager -l
    echo ""
    echo -e "${GREEN}=== Deployment Complete ===${NC}"
    echo ""
    echo "Monitor logs with:"
    echo "  tail -f ~/.gcode_sync.log"
    echo ""
    echo "Or check service logs:"
    echo "  journalctl -u gcode-monitor.service -f"
else
    echo -e "${RED}✗ Service failed to start${NC}"
    echo ""
    echo "Check logs with:"
    echo "  journalctl -u gcode-monitor.service -xe"
    exit 1
fi
