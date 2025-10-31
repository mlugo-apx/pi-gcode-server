#!/bin/bash
# Universal USB Gadget Refresh Script
# Auto-detects the USB gadget configuration method and applies appropriate refresh

set -e

LOG_FILE="/var/log/usb_gadget_refresh.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "=== USB Gadget Refresh Started ==="

# First, always sync the filesystem
log "Step 1: Syncing filesystem to flush all pending writes..."
sync
sleep 1

# Detect configuration method
if [ -d "/sys/kernel/config/usb_gadget" ] && [ "$(ls -A /sys/kernel/config/usb_gadget 2>/dev/null)" ]; then
    # ConfigFS method
    log "Detected: ConfigFS USB gadget"

    GADGETS=$(ls /sys/kernel/config/usb_gadget/)
    GADGET_NAME=$(echo "$GADGETS" | head -1)
    GADGET_PATH="/sys/kernel/config/usb_gadget/$GADGET_NAME"

    log "Using gadget: $GADGET_NAME"

    UDC=$(cat "$GADGET_PATH/UDC" 2>/dev/null || echo "")

    if [ -z "$UDC" ]; then
        log "WARNING: Gadget not bound to UDC, skipping unbind/rebind"
    else
        log "Step 2: Unbinding from UDC: $UDC"
        echo "" > "$GADGET_PATH/UDC"
        sleep 1

        log "Step 3: Re-binding to UDC: $UDC"
        echo "$UDC" > "$GADGET_PATH/UDC"
        sleep 1
    fi

elif lsmod | grep -q "g_mass_storage"; then
    # Module method
    log "Detected: g_mass_storage kernel module"

    MODULE_FILE=$(cat /sys/module/g_mass_storage/parameters/file 2>/dev/null || echo "")
    RO_PARAM=$(cat /sys/module/g_mass_storage/parameters/ro 2>/dev/null || echo "N")

    log "Backing file: $MODULE_FILE"

    if [ -z "$MODULE_FILE" ]; then
        log "ERROR: Cannot determine module parameters"
        exit 1
    fi

    log "Step 2: Removing g_mass_storage module..."
    modprobe -r g_mass_storage
    sleep 2

    log "Step 3: Re-inserting g_mass_storage module..."
    modprobe g_mass_storage file="$MODULE_FILE" ro="$RO_PARAM" removable=1 stall=0
    sleep 2

else
    log "ERROR: No recognized USB gadget configuration found"
    log "Please run diagnose_usb_gadget.sh to identify your setup"
    exit 1
fi

log "=== USB Gadget Refresh Complete ==="
log "The 3D printer should now see the updated files without rebooting"
