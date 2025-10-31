#!/bin/bash
# Interactive Setup Wizard for pi-gcode-server
# Guides user through configuration and generates config.local

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.local"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║    pi-gcode-server Configuration Wizard         ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════╝${NC}"
echo

# Check if config.local already exists
if [ -f "$CONFIG_FILE" ]; then
    echo -e "${YELLOW}⚠️  config.local already exists!${NC}"
    echo
    read -p "Do you want to reconfigure? This will backup your existing config. (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}✓ Using existing configuration${NC}"
        exit 0
    fi
    # Backup existing config
    BACKUP_FILE="$CONFIG_FILE.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$CONFIG_FILE" "$BACKUP_FILE"
    echo -e "${GREEN}✓ Backed up existing config to: $BACKUP_FILE${NC}"
    echo
fi

echo "This wizard will help you configure your pi-gcode-server installation."
echo "Press Ctrl+C at any time to cancel."
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

# Function to prompt for input with default
prompt_with_default() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    local value

    read -p "$prompt [$default]: " value
    value="${value:-$default}"
    printf -v "$var_name" '%s' "$value"
}

# Function to validate directory
validate_directory() {
    local dir="$1"
    # Expand variables safely
    dir="${dir/#\~/$HOME}"
    dir=$(echo "$dir" | envsubst)

    if [ ! -d "$dir" ]; then
        echo -e "${YELLOW}⚠️  Directory doesn't exist: $dir${NC}"
        read -p "Create it now? (Y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            mkdir -p "$dir"
            echo -e "${GREEN}✓ Created directory: $dir${NC}"
            return 0
        else
            return 1
        fi
    fi
    return 0
}

# Function to validate SSH parameters
validate_ssh_params() {
    local user="$1"
    local host="$2"
    local port="$3"

    # Validate port is numeric and in range
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}✗ Port must be numeric${NC}"
        return 1
    fi
    if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        echo -e "${RED}✗ Port must be between 1-65535${NC}"
        return 1
    fi

    # Validate no dangerous characters in user/host
    if [[ "$user" =~ [\$\`\;\|\&\<\>\(\)\{\}] ]]; then
        echo -e "${RED}✗ Username contains invalid characters${NC}"
        return 1
    fi
    if [[ "$host" =~ [\$\`\;\|\&\<\>\(\)\{\}] ]]; then
        echo -e "${RED}✗ Hostname contains invalid characters${NC}"
        return 1
    fi

    return 0
}

# Function to test SSH connection
test_ssh_connection() {
    local user="$1"
    local host="$2"
    local port="$3"

    echo -n "Testing SSH connection to ${user}@${host}:${port}... "
    if ssh -p "$port" -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=yes "${user}@${host}" "echo 'Connected'" &>/dev/null; then
        echo -e "${GREEN}✓ Success${NC}"
        return 0
    else
        echo -e "${RED}✗ Failed${NC}"
        echo -e "${YELLOW}⚠️  SSH connection failed. Please ensure:${NC}"
        echo "   - Raspberry Pi is powered on and connected to network"
        echo "   - SSH is enabled on the Pi"
        echo "   - SSH keys are set up (run: ssh-copy-id ${user}@${host})"
        echo "   - Firewall allows SSH connections"
        return 1
    fi
}

echo -e "${BLUE}📁 Local Machine Configuration${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

# Watch directory
while true; do
    prompt_with_default "Directory to monitor for .gcode files" "\$HOME/Desktop" WATCH_DIR
    if validate_directory "$WATCH_DIR"; then
        break
    fi
done

# Log file
prompt_with_default "Log file location" "\$HOME/.gcode_sync.log" LOG_FILE

echo
echo -e "${BLUE}🔌 Raspberry Pi Connection${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

# Remote user
prompt_with_default "Raspberry Pi SSH username" "$USER" REMOTE_USER

# Remote host
echo
echo "Enter your Raspberry Pi's IP address or hostname."
echo "Examples: 192.168.1.6, raspberrypi.local, localhost (if using port forwarding)"
prompt_with_default "Raspberry Pi hostname/IP" "192.168.1.100" REMOTE_HOST

# Remote port
prompt_with_default "SSH port" "22" REMOTE_PORT

# Validate SSH parameters before testing connection
echo
if ! validate_ssh_params "$REMOTE_USER" "$REMOTE_HOST" "$REMOTE_PORT"; then
    echo
    echo -e "${RED}✗ Invalid SSH parameters. Please run the wizard again.${NC}"
    exit 1
fi

# Test SSH connection
if ! test_ssh_connection "$REMOTE_USER" "$REMOTE_HOST" "$REMOTE_PORT"; then
    echo
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${RED}✗ Setup cancelled${NC}"
        exit 1
    fi
fi

# Remote path
echo
echo "Path on Raspberry Pi where USB gadget is mounted."
prompt_with_default "USB gadget mount point" "/mnt/usb_share" REMOTE_PATH

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${BLUE}📝 Configuration Summary${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "  Watch Directory:  $WATCH_DIR"
echo "  Log File:         $LOG_FILE"
echo "  Pi Username:      $REMOTE_USER"
echo "  Pi Host:          $REMOTE_HOST"
echo "  Pi SSH Port:      $REMOTE_PORT"
echo "  Pi Mount Path:    $REMOTE_PATH"
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

read -p "Save this configuration? (Y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Nn]$ ]]; then
    echo -e "${RED}✗ Configuration not saved${NC}"
    exit 1
fi

# Generate config.local with secure permissions
(
    umask 077
    cat > "$CONFIG_FILE" << EOF
# Configuration for pi-gcode-server
# Generated by setup wizard on $(date)
#
# To modify this configuration:
# 1. Edit this file directly, OR
# 2. Run: ./setup_wizard.sh

# Local machine settings
WATCH_DIR="$WATCH_DIR"
LOG_FILE="$LOG_FILE"

# Raspberry Pi connection settings
REMOTE_USER="$REMOTE_USER"
REMOTE_HOST="$REMOTE_HOST"
REMOTE_PORT="$REMOTE_PORT"
REMOTE_PATH="$REMOTE_PATH"
EOF
)

# Ensure secure permissions and verify
chmod 600 "$CONFIG_FILE"
if [ "$(stat -c '%a' "$CONFIG_FILE")" != "600" ]; then
    echo -e "${RED}✗ ERROR: Failed to set secure permissions on $CONFIG_FILE${NC}"
    echo "Current permissions: $(stat -c '%a' "$CONFIG_FILE")"
    exit 1
fi

echo
echo -e "${GREEN}✓ Configuration saved to: $CONFIG_FILE${NC}"
echo
echo -e "${BLUE}📋 Next Steps:${NC}"
echo
echo "1. Install dependencies:"
echo "   ${YELLOW}sudo apt-get install -y inotify-tools rsync openssh-client${NC}"
echo
echo "2. Set up SSH keys (if not already done):"
echo "   ${YELLOW}ssh-keygen -t rsa -b 4096${NC}"
echo "   ${YELLOW}ssh-copy-id -p $REMOTE_PORT ${REMOTE_USER}@${REMOTE_HOST}${NC}"
echo
echo "3. Install Pi scripts on Raspberry Pi:"
echo "   ${YELLOW}scp -P $REMOTE_PORT pi_scripts/refresh_usb_gadget.sh ${REMOTE_USER}@${REMOTE_HOST}:/tmp/${NC}"
echo "   ${YELLOW}ssh -p $REMOTE_PORT ${REMOTE_USER}@${REMOTE_HOST} \"sudo mv /tmp/refresh_usb_gadget.sh /usr/local/bin/ && sudo chmod +x /usr/local/bin/refresh_usb_gadget.sh\"${NC}"
echo
echo "4. Test the monitor script:"
echo "   ${YELLOW}./monitor_and_sync.sh${NC}"
echo
echo "5. Install as systemd service (optional):"
echo "   ${YELLOW}./install_service.sh${NC}"
echo
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓ Setup complete! Happy printing! 🖨️${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo
echo "To modify configuration in the future:"
echo "  - Edit: $CONFIG_FILE"
echo "  - Or run: ./setup_wizard.sh"
echo
echo "To restart the service after config changes:"
echo "  ${YELLOW}sudo systemctl restart gcode-monitor.service${NC}"
echo
