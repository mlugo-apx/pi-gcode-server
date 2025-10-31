#!/bin/bash

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load configuration from config.local
CONFIG_FILE="$SCRIPT_DIR/config.local"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Configuration file not found: $CONFIG_FILE"
    echo
    echo "Please run the setup wizard first:"
    echo "  ./setup_wizard.sh"
    echo
    echo "Or manually create config.local from config.example:"
    echo "  cp config.example config.local"
    echo "  nano config.local"
    exit 1
fi

# Source the configuration
source "$CONFIG_FILE"

# Validate required variables
REQUIRED_VARS=("WATCH_DIR" "REMOTE_USER" "REMOTE_HOST" "REMOTE_PORT" "REMOTE_PATH" "LOG_FILE")
for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        echo "ERROR: Required variable $var is not set in $CONFIG_FILE"
        exit 1
    fi
done

# Validate config values to prevent injection attacks
validate_config() {
    # Port must be numeric
    if ! [[ "$REMOTE_PORT" =~ ^[0-9]+$ ]]; then
        echo "ERROR: REMOTE_PORT must be numeric (got: $REMOTE_PORT)"
        exit 1
    fi

    # Port must be in valid range
    if [ "$REMOTE_PORT" -lt 1 ] || [ "$REMOTE_PORT" -gt 65535 ]; then
        echo "ERROR: REMOTE_PORT must be between 1 and 65535 (got: $REMOTE_PORT)"
        exit 1
    fi

    # Host must not contain shell metacharacters
    if [[ "$REMOTE_HOST" =~ [\$\`\;\|\&\<\>\(\)\{\}] ]]; then
        echo "ERROR: REMOTE_HOST contains invalid characters"
        exit 1
    fi

    # User must not contain shell metacharacters
    if [[ "$REMOTE_USER" =~ [\$\`\;\|\&\<\>\(\)\{\}] ]]; then
        echo "ERROR: REMOTE_USER contains invalid characters"
        exit 1
    fi

    # Path must not contain shell metacharacters (except /)
    if [[ "$REMOTE_PATH" =~ [\$\`\;\|\&\<\>\(\)\{\}] ]]; then
        echo "ERROR: REMOTE_PATH contains invalid characters"
        exit 1
    fi
}

validate_config

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to sync a file
sync_file() {
    local file="$1"
    log_message "Syncing file: $file"

    # Use rsync with SSH (with timeouts to prevent hanging)
    # SECURITY: Quote all variables to prevent command injection
    if rsync -avz --timeout=60 \
        -e "ssh -p \"$REMOTE_PORT\" -o StrictHostKeyChecking=yes -o ConnectTimeout=10 -o ServerAliveInterval=5 -o ServerAliveCountMax=3" \
        "$file" "${REMOTE_USER}@${REMOTE_HOST}:\"${REMOTE_PATH}/\""; then
        log_message "Successfully synced: $(basename "$file")"

        # Trigger USB gadget refresh on the Pi
        log_message "Refreshing USB gadget..."
        if ssh -p "$REMOTE_PORT" -o StrictHostKeyChecking=yes -o ConnectTimeout=10 -o ServerAliveInterval=5 -o ServerAliveCountMax=3 \
            "${REMOTE_USER}@${REMOTE_HOST}" "timeout 30 sudo /usr/local/bin/refresh_usb_gadget.sh" 2>&1 | tail -1 | tee -a "$LOG_FILE"; then
            log_message "USB gadget refreshed - printer should see the new file"
            return 0
        else
            log_message "ERROR: USB gadget refresh failed"
            return 1
        fi
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
