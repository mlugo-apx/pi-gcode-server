#!/bin/bash
# Test script to verify the GCode sync system

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Testing GCode Sync System ===${NC}"
echo

# Create test file
TEST_FILE="$HOME/Desktop/test_$(date +%s).gcode"
echo -e "${YELLOW}Step 1: Creating test gcode file${NC}"
cat > "$TEST_FILE" << 'EOF'
; Test GCode File
; Generated for sync testing
G28 ; Home all axes
G1 X50 Y50 Z10 F3000 ; Move to position
G1 X100 Y100 ; Move again
M104 S200 ; Set hotend temp
M140 S60 ; Set bed temp
; End of test file
EOF

echo "Created: $TEST_FILE"
ls -lh "$TEST_FILE"
echo

# Test manual sync
echo -e "${YELLOW}Step 2: Testing manual rsync${NC}"
if rsync -avz "$TEST_FILE" milugo@192.168.1.6:/mnt/usb_share/; then
    echo -e "${GREEN}✓ File synced successfully${NC}"
else
    echo -e "${RED}✗ Failed to sync file${NC}"
    exit 1
fi
echo

# Verify on Pi
echo -e "${YELLOW}Step 3: Verifying file on Pi${NC}"
if ssh milugo@192.168.1.6 "test -f /mnt/usb_share/$(basename "$TEST_FILE") && ls -lh /mnt/usb_share/$(basename "$TEST_FILE")"; then
    echo -e "${GREEN}✓ File exists on Pi${NC}"
else
    echo -e "${RED}✗ File not found on Pi${NC}"
    exit 1
fi
echo

# Test USB gadget refresh
echo -e "${YELLOW}Step 4: Testing USB gadget refresh${NC}"
if ssh milugo@192.168.1.6 "sudo /usr/local/bin/refresh_usb_gadget.sh" 2>&1 | grep -q "Complete"; then
    echo -e "${GREEN}✓ USB gadget refreshed successfully${NC}"
else
    echo -e "${RED}✗ USB gadget refresh failed${NC}"
    exit 1
fi
echo

# Cleanup
echo -e "${YELLOW}Step 5: Cleaning up test files${NC}"
rm "$TEST_FILE"
ssh milugo@192.168.1.6 "rm /mnt/usb_share/$(basename "$TEST_FILE")"
echo -e "${GREEN}✓ Cleanup complete${NC}"
echo

echo -e "${GREEN}=== All Tests Passed! ===${NC}"
echo
echo "Your system is ready to use!"
echo
echo "Next steps:"
echo "1. Run the monitor:  ./run_monitor.sh"
echo "2. Or install as service:"
echo "   sudo cp gcode-monitor.service /etc/systemd/system/"
echo "   sudo systemctl daemon-reload"
echo "   sudo systemctl enable gcode-monitor.service"
echo "   sudo systemctl start gcode-monitor.service"
echo
echo "When a .gcode file is saved to ~/Desktop, it will:"
echo "  → Automatically sync to Pi at 192.168.1.6:/mnt/usb_share/"
echo "  → Trigger USB gadget refresh"
echo "  → Appear on your 3D printer WITHOUT rebooting!"
