#!/bin/bash
# USB Gadget Refresh Script - Module Reload Method
# For Pi configured with g_mass_storage kernel module
# This removes and re-inserts the module to force re-enumeration

set -e

LOG_FILE="/var/log/usb_gadget_refresh.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Check if g_mass_storage is loaded
if ! lsmod | grep -q "g_mass_storage"; then
    log "ERROR: g_mass_storage module is not loaded"
    exit 1
fi

log "Starting USB gadget refresh (module reload method)..."

# Get current module parameters
MODULE_PARAMS=$(cat /sys/module/g_mass_storage/parameters/file 2>/dev/null || echo "")
RO_PARAM=$(cat /sys/module/g_mass_storage/parameters/ro 2>/dev/null || echo "N")

log "Current backing file: $MODULE_PARAMS"
log "Read-only mode: $RO_PARAM"

# Sync filesystem
log "Syncing filesystem..."
sync
sleep 1

# Remove the module
log "Removing g_mass_storage module..."
modprobe -r g_mass_storage
sleep 2

# Re-insert the module with same parameters
log "Re-inserting g_mass_storage module..."
if [ -n "$MODULE_PARAMS" ]; then
    modprobe g_mass_storage file="$MODULE_PARAMS" ro="$RO_PARAM" removable=1 stall=0
else
    log "ERROR: Could not determine module parameters"
    exit 1
fi

sleep 2

log "USB gadget refresh complete!"
log "The host (3D printer) should now see the updated files"
