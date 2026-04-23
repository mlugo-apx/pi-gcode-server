#!/bin/bash
# resize_usb_image.sh - Resize the USB gadget disk image (/piusb.bin)
#
# Grows the FAT32 image used by the USB mass storage gadget.
# Must be run on the Raspberry Pi with sudo.
#
# Usage:
#   sudo ./resize_usb_image.sh [SIZE_IN_MB]
#
# Examples:
#   sudo ./resize_usb_image.sh          # Default: grow to 4096 MB (4 GB)
#   sudo ./resize_usb_image.sh 8192     # Grow to 8 GB
#
# What it does:
#   1. Unbinds the USB gadget (printer temporarily disconnects)
#   2. Unmounts /mnt/usb_share
#   3. Creates a new larger image, formats it, copies existing files
#   4. Replaces the old image and remounts
#   5. Rebinds the USB gadget
#
# The printer will briefly disconnect during this process (~30-60 seconds).

set -euo pipefail

# Configuration
IMAGE_PATH="/piusb.bin"
MOUNT_POINT="/mnt/usb_share"
DEFAULT_SIZE_MB=4096
LOG_FILE="/var/log/usb_gadget_refresh.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo -e "$msg" | tee -a "$LOG_FILE"
}

die() {
    log "${RED}ERROR: $1${NC}"
    exit 1
}

# Parse arguments
NEW_SIZE_MB="${1:-$DEFAULT_SIZE_MB}"

# Validate size is numeric
if ! [[ "$NEW_SIZE_MB" =~ ^[0-9]+$ ]]; then
    die "Size must be a number in MB (got: $NEW_SIZE_MB)"
fi

# Minimum 512 MB, maximum 32 GB (SD card constraint)
if [ "$NEW_SIZE_MB" -lt 512 ]; then
    die "Minimum image size is 512 MB"
fi
if [ "$NEW_SIZE_MB" -gt 32768 ]; then
    die "Maximum image size is 32768 MB (32 GB)"
fi

# Must be root
if [ "$EUID" -ne 0 ]; then
    die "This script must be run with sudo"
fi

# Check current image exists
if [ ! -f "$IMAGE_PATH" ]; then
    die "Image not found: $IMAGE_PATH"
fi

CURRENT_SIZE_MB=$(( $(stat -c %s "$IMAGE_PATH") / 1024 / 1024 ))
log "Current image size: ${CURRENT_SIZE_MB} MB"
log "Requested size: ${NEW_SIZE_MB} MB"

if [ "$NEW_SIZE_MB" -le "$CURRENT_SIZE_MB" ]; then
    die "New size ($NEW_SIZE_MB MB) must be larger than current size ($CURRENT_SIZE_MB MB)"
fi

# Check available disk space (need new image + old image simultaneously)
AVAIL_MB=$(df -BM --output=avail / | tail -1 | tr -d ' M')
NEEDED_MB=$(( NEW_SIZE_MB + 100 ))  # new image + buffer
if [ "$AVAIL_MB" -lt "$NEEDED_MB" ]; then
    die "Not enough disk space. Available: ${AVAIL_MB} MB, Need: ${NEEDED_MB} MB"
fi

log "${GREEN}=== USB Image Resize: ${CURRENT_SIZE_MB} MB -> ${NEW_SIZE_MB} MB ===${NC}"
echo ""
echo -e "${YELLOW}This will briefly disconnect the USB drive from the printer.${NC}"
echo -e "${YELLOW}All existing files will be preserved.${NC}"
echo ""
read -rp "Continue? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    log "Resize cancelled by user"
    exit 0
fi

# Create temporary working directory
WORK_DIR=$(mktemp -d /tmp/usb_resize.XXXXXX)
trap 'rm -rf "$WORK_DIR"' EXIT

OLD_MOUNT="$WORK_DIR/old"
NEW_MOUNT="$WORK_DIR/new"
NEW_IMAGE="$WORK_DIR/piusb_new.bin"
mkdir -p "$OLD_MOUNT" "$NEW_MOUNT"

# Step 1: Unbind USB gadget
log "Step 1/7: Unbinding USB gadget..."
if [ -d "/sys/kernel/config/usb_gadget" ] && [ "$(ls -A /sys/kernel/config/usb_gadget 2>/dev/null)" ]; then
    GADGET_NAME=$(ls /sys/kernel/config/usb_gadget/ | head -1)
    GADGET_PATH="/sys/kernel/config/usb_gadget/$GADGET_NAME"
    UDC=$(cat "$GADGET_PATH/UDC" 2>/dev/null || echo "")
    if [ -n "$UDC" ]; then
        echo "" > "$GADGET_PATH/UDC"
        log "Unbound ConfigFS gadget ($GADGET_NAME) from UDC: $UDC"
    fi
elif lsmod | grep -q "g_mass_storage"; then
    modprobe -r g_mass_storage
    log "Removed g_mass_storage module"
fi
sleep 1

# Step 2: Unmount current image
log "Step 2/7: Unmounting $MOUNT_POINT..."
if mount | grep -q "$MOUNT_POINT"; then
    sync
    umount "$MOUNT_POINT"
    log "Unmounted $MOUNT_POINT"
else
    log "Not currently mounted, skipping"
fi

# Step 3: Create new larger image
log "Step 3/7: Creating new ${NEW_SIZE_MB} MB image..."
dd if=/dev/zero of="$NEW_IMAGE" bs=1M count="$NEW_SIZE_MB" status=progress
log "Image created"

# Step 4: Format new image
log "Step 4/7: Formatting new image as FAT32..."
mkfs.vfat -F 32 -n GCODE "$NEW_IMAGE"
log "Formatted"

# Step 5: Copy files from old to new
log "Step 5/7: Copying existing files..."
mount -o loop,ro "$IMAGE_PATH" "$OLD_MOUNT"
mount -o loop "$NEW_IMAGE" "$NEW_MOUNT"

FILE_COUNT=$(find "$OLD_MOUNT" -type f | wc -l)
if [ "$FILE_COUNT" -gt 0 ]; then
    cp -a "$OLD_MOUNT"/. "$NEW_MOUNT"/
    log "Copied $FILE_COUNT files"
else
    log "No files to copy (image was empty)"
fi

sync
umount "$NEW_MOUNT"
umount "$OLD_MOUNT"

# Step 6: Replace old image with new
log "Step 6/7: Replacing image..."
BACKUP_PATH="${IMAGE_PATH}.backup_$(date +%Y%m%d_%H%M%S)"
mv "$IMAGE_PATH" "$BACKUP_PATH"
mv "$NEW_IMAGE" "$IMAGE_PATH"
log "Old image backed up to: $BACKUP_PATH"

# Mount the new image
mount "$MOUNT_POINT"
log "Mounted new image at $MOUNT_POINT"

# Step 7: Rebind USB gadget
log "Step 7/7: Rebinding USB gadget..."
if [ -n "${UDC:-}" ]; then
    echo "$UDC" > "$GADGET_PATH/UDC"
    log "Rebound ConfigFS gadget to UDC: $UDC"
elif [ -f "/etc/modprobe.d/g_mass_storage.conf" ]; then
    modprobe g_mass_storage
    log "Reloaded g_mass_storage module"
fi
sleep 2

# Verify
NEW_ACTUAL_MB=$(( $(stat -c %s "$IMAGE_PATH") / 1024 / 1024 ))
USED_MB=$(df -BM --output=used "$MOUNT_POINT" | tail -1 | tr -d ' M')
AVAIL_NEW_MB=$(df -BM --output=avail "$MOUNT_POINT" | tail -1 | tr -d ' M')

log ""
log "${GREEN}=== Resize Complete ===${NC}"
log "  Image size:  ${NEW_ACTUAL_MB} MB"
log "  Used:        ${USED_MB} MB"
log "  Available:   ${AVAIL_NEW_MB} MB"
log "  Backup at:   $BACKUP_PATH"
log ""
log "The printer should reconnect automatically."
log "If not, unplug and replug the USB cable."
log ""
log "${YELLOW}Once verified, you can delete the backup:${NC}"
log "  sudo rm $BACKUP_PATH"
