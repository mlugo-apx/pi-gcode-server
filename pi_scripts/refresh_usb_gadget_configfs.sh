#!/bin/bash
# USB Gadget Refresh Script - ConfigFS Method
# For Pi configured with configfs/libcomposite
# This unbinds and rebinds the USB gadget to force the host to re-enumerate

set -e

GADGET_NAME="pi_usb"  # Common name, adjust if different
GADGET_PATH="/sys/kernel/config/usb_gadget/$GADGET_NAME"
LOG_FILE="/var/log/usb_gadget_refresh.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

if [ ! -d "$GADGET_PATH" ]; then
    # Try to find the actual gadget name
    GADGETS=$(ls /sys/kernel/config/usb_gadget/ 2>/dev/null)
    if [ -z "$GADGETS" ]; then
        log "ERROR: No USB gadgets found in configfs"
        exit 1
    fi
    # Use the first gadget found
    GADGET_NAME=$(echo "$GADGETS" | head -1)
    GADGET_PATH="/sys/kernel/config/usb_gadget/$GADGET_NAME"
    log "Using gadget: $GADGET_NAME"
fi

log "Starting USB gadget refresh..."

# Get current UDC
UDC=$(cat "$GADGET_PATH/UDC" 2>/dev/null || echo "")

if [ -z "$UDC" ]; then
    log "ERROR: Gadget not bound to any UDC"
    exit 1
fi

log "Current UDC: $UDC"

# Sync filesystem to ensure all writes are flushed
log "Syncing filesystem..."
sync
sleep 1

# Unbind the gadget from UDC
log "Unbinding gadget from UDC..."
echo "" > "$GADGET_PATH/UDC"
sleep 1

# Re-bind the gadget to UDC
log "Re-binding gadget to UDC..."
echo "$UDC" > "$GADGET_PATH/UDC"
sleep 1

log "USB gadget refresh complete!"
log "The host (3D printer) should now see the updated files"
