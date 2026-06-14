#!/bin/bash
# cleanup_old_gcode.sh - Delete .gcode files older than a threshold
#
# Runs on the Raspberry Pi to prevent the USB gadget image from filling up.
# Designed to be called via cron.
#
# Usage:
#   sudo ./cleanup_old_gcode.sh              # Delete files older than 14 days
#   sudo ./cleanup_old_gcode.sh 7            # Delete files older than 7 days
#   sudo ./cleanup_old_gcode.sh --dry-run    # Show what would be deleted
#   sudo ./cleanup_old_gcode.sh 7 --dry-run  # Combine both
#
# Cron setup (run daily at 3 AM):
#   sudo crontab -e
#   0 3 * * * /usr/local/bin/cleanup_old_gcode.sh >> /var/log/gcode_cleanup.log 2>&1

set -euo pipefail

# Configuration
MOUNT_POINT="/mnt/usb_share"
DEFAULT_MAX_AGE_DAYS=14
LOG_FILE="/var/log/gcode_cleanup.log"
REFRESH_SCRIPT="/usr/local/bin/refresh_usb_gadget.sh"

# Parse arguments
MAX_AGE_DAYS="$DEFAULT_MAX_AGE_DAYS"
DRY_RUN=false

for arg in "$@"; do
    case "$arg" in
        --dry-run)
            DRY_RUN=true
            ;;
        --help|-h)
            echo "Usage: $0 [MAX_AGE_DAYS] [--dry-run]"
            echo ""
            echo "Delete .gcode files older than MAX_AGE_DAYS from $MOUNT_POINT"
            echo ""
            echo "  MAX_AGE_DAYS   Days before a file is considered old (default: 14)"
            echo "  --dry-run      Show what would be deleted without deleting"
            echo ""
            echo "Cron setup (daily at 3 AM):"
            echo "  sudo crontab -e"
            echo "  0 3 * * * /usr/local/bin/cleanup_old_gcode.sh >> /var/log/gcode_cleanup.log 2>&1"
            exit 0
            ;;
        *)
            if [[ "$arg" =~ ^[0-9]+$ ]]; then
                MAX_AGE_DAYS="$arg"
            else
                echo "Unknown argument: $arg" >&2
                exit 1
            fi
            ;;
    esac
done

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Validate mount point exists and is mounted
if [ ! -d "$MOUNT_POINT" ]; then
    log "ERROR: Mount point not found: $MOUNT_POINT"
    exit 1
fi

if ! mount | grep -q "$MOUNT_POINT"; then
    log "ERROR: $MOUNT_POINT is not mounted"
    exit 1
fi

# Find old .gcode files.
# NULL-delimited (-print0 + mapfile -d '') so filenames containing spaces,
# parentheses, etc. are handled correctly. The previous version piped the
# list through `xargs du`, which split on whitespace and, under
# `set -euo pipefail`, aborted the whole script before any file was deleted.
mapfile -d '' -t OLD_FILES < <(find "$MOUNT_POINT" -maxdepth 1 -name "*.gcode" -type f -mtime +"$MAX_AGE_DAYS" -print0 2>/dev/null)

if [ "${#OLD_FILES[@]}" -eq 0 ]; then
    log "No .gcode files older than $MAX_AGE_DAYS days found. Nothing to do."
    exit 0
fi

FILE_COUNT="${#OLD_FILES[@]}"
TOTAL_BYTES=0
for file in "${OLD_FILES[@]}"; do
    TOTAL_BYTES=$(( TOTAL_BYTES + $(stat -c %s "$file" 2>/dev/null || echo 0) ))
done
TOTAL_SIZE="$(( TOTAL_BYTES / 1048576 )) MB"

if [ "$DRY_RUN" = true ]; then
    log "[DRY-RUN] Would delete $FILE_COUNT file(s) ($TOTAL_SIZE) older than $MAX_AGE_DAYS days:"
    for file in "${OLD_FILES[@]}"; do
        AGE_DAYS=$(( ( $(date +%s) - $(stat -c %Y "$file") ) / 86400 ))
        log "  [DRY-RUN] $(basename "$file") (${AGE_DAYS} days old, $(du -h "$file" | cut -f1))"
    done
    exit 0
fi

log "=== GCode Cleanup: deleting $FILE_COUNT file(s) ($TOTAL_SIZE) older than $MAX_AGE_DAYS days ==="

DELETED=0
FAILED=0

for file in "${OLD_FILES[@]}"; do
    BASENAME=$(basename "$file")
    AGE_DAYS=$(( ( $(date +%s) - $(stat -c %Y "$file") ) / 86400 ))
    FILE_SIZE=$(du -h "$file" | cut -f1)

    if rm "$file"; then
        log "  Deleted: $BASENAME (${AGE_DAYS} days old, $FILE_SIZE)"
        DELETED=$(( DELETED + 1 ))
    else
        log "  FAILED to delete: $BASENAME"
        FAILED=$(( FAILED + 1 ))
    fi
done

log "Deleted $DELETED file(s), $FAILED failure(s)"

# Sync filesystem
sync

# Refresh USB gadget so printer sees the changes
if [ -x "$REFRESH_SCRIPT" ]; then
    log "Refreshing USB gadget..."
    if "$REFRESH_SCRIPT" >> "$LOG_FILE" 2>&1; then
        log "USB gadget refreshed"
    else
        log "WARNING: USB gadget refresh failed (printer may need replug)"
    fi
else
    log "WARNING: Refresh script not found at $REFRESH_SCRIPT"
fi

# Report disk usage
USED=$(df -h "$MOUNT_POINT" | tail -1 | awk '{print $3}')
AVAIL=$(df -h "$MOUNT_POINT" | tail -1 | awk '{print $4}')
USE_PCT=$(df -h "$MOUNT_POINT" | tail -1 | awk '{print $5}')
log "Disk usage after cleanup: ${USED} used, ${AVAIL} available ($USE_PCT)"
log "=== Cleanup complete ==="
