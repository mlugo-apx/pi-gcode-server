#!/bin/bash

# Configuration
WATCH_DIR="$HOME/Desktop"
REMOTE_USER="milugo"
REMOTE_HOST="192.168.1.6"
REMOTE_PORT="22"
REMOTE_PATH="/mnt/usb_share"
LOG_FILE="$HOME/.gcode_sync.log"

# Note: Changed from localhost:9702 to direct connection 192.168.1.6:22

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to sync a file
sync_file() {
    local file="$1"
    log_message "Syncing file: $file"

    # Use rsync with SSH
    if rsync -avz -e "ssh -p $REMOTE_PORT" "$file" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}/"; then
        log_message "Successfully synced: $(basename "$file")"

        # Trigger USB gadget refresh on the Pi
        log_message "Refreshing USB gadget..."
        if ssh -p "$REMOTE_PORT" "${REMOTE_USER}@${REMOTE_HOST}" "sudo /usr/local/bin/refresh_usb_gadget.sh" 2>&1 | tail -1 | tee -a "$LOG_FILE"; then
            log_message "USB gadget refreshed - printer should see the new file"
        else
            log_message "WARNING: USB gadget refresh may have failed"
        fi

        return 0
    else
        log_message "ERROR: Failed to sync: $file"
        return 1
    fi
}

# Check if inotify-tools is installed
if ! command -v inotifywait &> /dev/null; then
    log_message "ERROR: inotifywait not found. Installing inotify-tools..."
    sudo apt-get update && sudo apt-get install -y inotify-tools
fi

log_message "Starting gcode file monitor on $WATCH_DIR"
log_message "Will sync to ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PORT}:${REMOTE_PATH}"

# Sync any existing .gcode files on startup (optional)
log_message "Checking for existing .gcode files..."
for file in "$WATCH_DIR"/*.gcode; do
    if [ -f "$file" ]; then
        log_message "Found existing file: $file"
        # Uncomment to sync existing files on startup
        # sync_file "$file"
    fi
done

# Monitor directory for new .gcode files
log_message "Monitoring for new .gcode files..."
inotifywait -m -e close_write,moved_to --format '%w%f' "$WATCH_DIR" |
while read -r file; do
    # Check if file is a .gcode file
    if [[ "$file" == *.gcode ]]; then
        log_message "Detected new file: $file"
        # Small delay to ensure file is fully written
        sleep 1
        sync_file "$file"
    fi
done
