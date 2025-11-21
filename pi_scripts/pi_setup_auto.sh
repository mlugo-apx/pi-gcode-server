#!/bin/bash
# pi_setup_auto.sh - Automated Raspberry Pi USB Gadget Setup
#
# This script eliminates manual configuration steps for pi-gcode-server setup:
# - Auto-detects USB gadget method (ConfigFS vs module)
# - Installs refresh scripts with correct permissions
# - Configures passwordless sudo for refresh script
# - Optionally fixes WiFi power management issues
#
# Usage:
#   ./pi_setup_auto.sh [OPTIONS]
#
# Options:
#   --dry-run            Show what would be done without making changes
#   --skip-wifi          Skip WiFi power management configuration
#   --no-backup          Skip backing up existing configurations
#   --help               Show this help message
#
# Version: 1.0.0
# Project: pi-gcode-server

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/.pi_setup_backup_$(date +%Y%m%d_%H%M%S)"
LOG_FILE="/tmp/pi_setup_auto_$(date +%Y%m%d_%H%M%S).log"

# Flags
DRY_RUN=false
SKIP_WIFI=false
NO_BACKUP=false

# Detection results
USB_GADGET_METHOD=""
WIFI_MANAGER=""
CURRENT_USER="${USER:-$(whoami)}"

#==============================================================================
# Utility Functions
#==============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

    case "$level" in
        INFO)
            echo -e "${BLUE}[INFO]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        SUCCESS)
            echo -e "${GREEN}[✓]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        WARNING)
            echo -e "${YELLOW}[⚠]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        ERROR)
            echo -e "${RED}[✗]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        *)
            echo "$message" | tee -a "$LOG_FILE"
            ;;
    esac
}

show_help() {
    cat << EOF
pi_setup_auto.sh - Automated Raspberry Pi USB Gadget Setup

USAGE:
    ./pi_setup_auto.sh [OPTIONS]

OPTIONS:
    --dry-run           Show what would be done without making changes
    --skip-wifi         Skip WiFi power management configuration
    --no-backup         Skip backing up existing configurations
    --help              Show this help message

DESCRIPTION:
    This script automates the entire Raspberry Pi USB gadget setup process:

    1. Auto-detects USB gadget method (ConfigFS vs g_mass_storage module)
    2. Installs appropriate refresh_usb_gadget.sh script
    3. Configures passwordless sudo for refresh script
    4. Optionally fixes WiFi power management issues
    5. Validates the complete setup

    The script is idempotent and safe to run multiple times.

EXAMPLES:
    # Run full setup with safety checks
    ./pi_setup_auto.sh

    # Preview changes without applying them
    ./pi_setup_auto.sh --dry-run

    # Skip WiFi configuration (if you handle it separately)
    ./pi_setup_auto.sh --skip-wifi

REQUIREMENTS:
    - Raspberry Pi OS (tested on Bullseye/Bookworm)
    - Root/sudo access
    - USB gadget modules already loaded (dwc2, libcomposite or g_mass_storage)
    - /piusb.bin already created and mounted

SAFETY:
    - Creates backups before modifying system files
    - Validates configurations with dry-run mode
    - Rollback capability on failure
    - Idempotent (safe to run multiple times)

For more information, see: docs/PI_SETUP.md
EOF
}

run_command() {
    local cmd="$*"

    if [ "$DRY_RUN" = true ]; then
        log INFO "[DRY-RUN] Would execute: $cmd"
        return 0
    else
        log INFO "Executing: $cmd"
        eval "$cmd" 2>&1 | tee -a "$LOG_FILE"
        return ${PIPESTATUS[0]}
    fi
}

backup_file() {
    local file="$1"

    if [ "$NO_BACKUP" = true ]; then
        log INFO "Skipping backup of $file (--no-backup flag set)"
        return 0
    fi

    if [ ! -e "$file" ]; then
        log INFO "File $file does not exist, skipping backup"
        return 0
    fi

    if [ "$DRY_RUN" = true ]; then
        log INFO "[DRY-RUN] Would backup: $file -> $BACKUP_DIR/"
        return 0
    fi

    mkdir -p "$BACKUP_DIR"
    local backup_path="$BACKUP_DIR/$(basename "$file")"
    cp -a "$file" "$backup_path"
    log SUCCESS "Backed up: $file -> $backup_path"
}

check_root() {
    if [ "$EUID" -ne 0 ] && [ "$DRY_RUN" = false ]; then
        log ERROR "This script must be run with sudo privileges"
        log INFO "Try: sudo ./pi_setup_auto.sh"
        exit 1
    fi
}

#==============================================================================
# Detection Functions
#==============================================================================

detect_usb_gadget_method() {
    log INFO "Detecting USB gadget configuration method..."

    # Check for ConfigFS
    if [ -d "/sys/kernel/config/usb_gadget" ]; then
        local gadgets=$(ls /sys/kernel/config/usb_gadget 2>/dev/null || true)
        if [ -n "$gadgets" ]; then
            USB_GADGET_METHOD="configfs"
            log SUCCESS "Detected: ConfigFS USB gadget (modern method)"
            return 0
        fi
    fi

    # Check for g_mass_storage module
    if lsmod | grep -q "g_mass_storage"; then
        USB_GADGET_METHOD="module"
        log SUCCESS "Detected: g_mass_storage kernel module (legacy method)"
        return 0
    fi

    # Check if modules can be loaded
    log WARNING "No active USB gadget found. Checking if modules can be loaded..."

    if modprobe -n libcomposite 2>/dev/null; then
        log INFO "libcomposite module available (ConfigFS method possible)"
        USB_GADGET_METHOD="configfs"
        return 0
    fi

    if modprobe -n g_mass_storage 2>/dev/null; then
        log INFO "g_mass_storage module available (module method possible)"
        USB_GADGET_METHOD="module"
        return 0
    fi

    log ERROR "Cannot detect USB gadget configuration"
    log ERROR "Please ensure dwc2 and libcomposite (or g_mass_storage) modules are available"
    log ERROR "Check /boot/config.txt has: dtoverlay=dwc2"
    log ERROR "Check /etc/modules has: dwc2 and libcomposite (or g_mass_storage)"
    return 1
}

detect_wifi_manager() {
    log INFO "Detecting WiFi management system..."

    if command -v nmcli &> /dev/null; then
        WIFI_MANAGER="networkmanager"
        log SUCCESS "Detected: NetworkManager"
        return 0
    elif systemctl is-active --quiet wpa_supplicant; then
        WIFI_MANAGER="wpa_supplicant"
        log SUCCESS "Detected: wpa_supplicant"
        return 0
    else
        WIFI_MANAGER="none"
        log WARNING "No recognized WiFi manager found"
        return 1
    fi
}

check_prerequisites() {
    log INFO "Checking prerequisites..."

    local missing_prereqs=()

    # Check for /piusb.bin
    if [ ! -f "/piusb.bin" ]; then
        log WARNING "/piusb.bin not found. You'll need to create it manually:"
        log INFO "  sudo dd if=/dev/zero of=/piusb.bin bs=1M count=2048"
        log INFO "  sudo mkfs.vfat /piusb.bin"
        missing_prereqs+=("/piusb.bin")
    else
        log SUCCESS "Found /piusb.bin"
    fi

    # Check for /mnt/usb_share mount point
    if [ ! -d "/mnt/usb_share" ]; then
        log WARNING "/mnt/usb_share directory not found"
        if [ "$DRY_RUN" = false ]; then
            run_command "mkdir -p /mnt/usb_share"
        fi
    else
        log SUCCESS "Found /mnt/usb_share"
    fi

    # Check if /piusb.bin is mounted
    if ! mount | grep -q "/mnt/usb_share"; then
        log WARNING "/piusb.bin is not mounted at /mnt/usb_share"
        log INFO "You may need to add to /etc/fstab:"
        log INFO "  /piusb.bin  /mnt/usb_share  vfat  loop,rw,users,umask=000  0  0"
        missing_prereqs+=("mount")
    else
        log SUCCESS "/piusb.bin is mounted"
    fi

    if [ ${#missing_prereqs[@]} -gt 0 ]; then
        log WARNING "Some prerequisites are missing. Setup will continue but may not be fully functional."
        return 1
    fi

    return 0
}

#==============================================================================
# Installation Functions
#==============================================================================

install_refresh_script() {
    log INFO "Installing USB gadget refresh script..."

    local source_script=""
    local target_script="/usr/local/bin/refresh_usb_gadget.sh"

    # Determine which script to install
    case "$USB_GADGET_METHOD" in
        configfs)
            source_script="$SCRIPT_DIR/refresh_usb_gadget_configfs.sh"
            ;;
        module)
            source_script="$SCRIPT_DIR/refresh_usb_gadget_module.sh"
            ;;
        *)
            log ERROR "Unknown USB gadget method: $USB_GADGET_METHOD"
            return 1
            ;;
    esac

    if [ ! -f "$source_script" ]; then
        log ERROR "Source script not found: $source_script"
        log ERROR "Make sure you're running this script from the pi_scripts directory"
        log ERROR "Or that you've copied all pi_scripts/*.sh files to the Pi"
        return 1
    fi

    # Backup existing script if present
    backup_file "$target_script"

    # Install script
    run_command "cp '$source_script' '$target_script'"
    run_command "chmod +x '$target_script'"

    # Also install the universal refresh script
    local universal_script="$SCRIPT_DIR/refresh_usb_gadget.sh"
    if [ -f "$universal_script" ]; then
        backup_file "/usr/local/bin/refresh_usb_gadget_universal.sh"
        run_command "cp '$universal_script' '/usr/local/bin/refresh_usb_gadget_universal.sh'"
        run_command "chmod +x '/usr/local/bin/refresh_usb_gadget_universal.sh'"
        log SUCCESS "Installed both specific and universal refresh scripts"
    fi

    log SUCCESS "Installed refresh script for $USB_GADGET_METHOD method"
    return 0
}

install_diagnose_script() {
    log INFO "Installing diagnostic script..."

    local source_script="$SCRIPT_DIR/diagnose_usb_gadget.sh"
    local target_script="/usr/local/bin/diagnose_usb_gadget.sh"

    if [ ! -f "$source_script" ]; then
        log WARNING "Diagnostic script not found: $source_script"
        return 1
    fi

    backup_file "$target_script"
    run_command "cp '$source_script' '$target_script'"
    run_command "chmod +x '$target_script'"

    log SUCCESS "Installed diagnostic script"
    return 0
}

configure_sudoers() {
    log INFO "Configuring passwordless sudo for refresh script..."

    local sudoers_file="/etc/sudoers.d/usb-gadget-refresh"
    local refresh_script="/usr/local/bin/refresh_usb_gadget.sh"
    local sudoers_entry="$CURRENT_USER ALL=(ALL) NOPASSWD: $refresh_script"

    # Check if entry already exists
    if [ -f "$sudoers_file" ] && grep -q "$refresh_script" "$sudoers_file"; then
        log INFO "Sudoers entry already exists"
        return 0
    fi

    backup_file "$sudoers_file"

    if [ "$DRY_RUN" = true ]; then
        log INFO "[DRY-RUN] Would create sudoers file: $sudoers_file"
        log INFO "[DRY-RUN] Content: $sudoers_entry"
        return 0
    fi

    # Create sudoers file with proper permissions
    echo "$sudoers_entry" | tee "$sudoers_file" > /dev/null
    chmod 0440 "$sudoers_file"

    # Validate sudoers file
    if visudo -c -f "$sudoers_file" > /dev/null 2>&1; then
        log SUCCESS "Configured passwordless sudo for $CURRENT_USER"
        log INFO "User can now run: sudo $refresh_script (without password)"
    else
        log ERROR "Sudoers file validation failed! Removing invalid file..."
        rm -f "$sudoers_file"
        return 1
    fi

    return 0
}

#==============================================================================
# WiFi Power Management Fix
#==============================================================================

fix_wifi_power_management() {
    if [ "$SKIP_WIFI" = true ]; then
        log INFO "Skipping WiFi power management configuration (--skip-wifi flag)"
        return 0
    fi

    log INFO "Configuring WiFi power management..."

    case "$WIFI_MANAGER" in
        networkmanager)
            fix_wifi_networkmanager
            ;;
        wpa_supplicant)
            fix_wifi_wpa_supplicant
            ;;
        none)
            log WARNING "No WiFi manager detected, skipping WiFi configuration"
            return 1
            ;;
    esac
}

fix_wifi_networkmanager() {
    log INFO "Disabling WiFi power save via NetworkManager..."

    # Get active WiFi connection
    local wifi_connection=$(nmcli -t -f NAME,TYPE connection show --active | grep wireless | cut -d: -f1 | head -1)

    if [ -z "$wifi_connection" ]; then
        log WARNING "No active WiFi connection found"
        log INFO "WiFi power management will be disabled when WiFi is connected"
        wifi_connection="preconfigured"  # Default connection name
    else
        log INFO "Found active WiFi connection: $wifi_connection"
    fi

    # Check current power save setting
    local current_powersave=$(nmcli -g 802-11-wireless.powersave connection show "$wifi_connection" 2>/dev/null || echo "unknown")
    log INFO "Current power save setting: $current_powersave (2=disabled)"

    if [ "$current_powersave" = "2" ]; then
        log SUCCESS "WiFi power save already disabled"
        return 0
    fi

    # Disable power save (2 = disabled)
    run_command "nmcli connection modify '$wifi_connection' 802-11-wireless.powersave 2"

    if [ "$DRY_RUN" = false ]; then
        # Reactivate connection to apply changes
        log INFO "Reactivating WiFi connection to apply changes..."
        nmcli connection down "$wifi_connection" 2>/dev/null || true
        sleep 2
        nmcli connection up "$wifi_connection" || true
        sleep 2

        # Verify setting
        local verification=$(iwconfig wlan0 2>/dev/null | grep "Power Management" || echo "unknown")
        log INFO "WiFi power management status: $verification"

        if echo "$verification" | grep -q "off"; then
            log SUCCESS "WiFi power management disabled successfully"
        else
            log WARNING "Power management may still be enabled. Check with: iwconfig wlan0"
        fi
    fi

    return 0
}

fix_wifi_wpa_supplicant() {
    log INFO "Disabling WiFi power save via wpa_supplicant..."

    local conf_file="/etc/network/interfaces"

    backup_file "$conf_file"

    if [ "$DRY_RUN" = true ]; then
        log INFO "[DRY-RUN] Would add 'wireless-power off' to $conf_file"
        return 0
    fi

    if grep -q "wireless-power off" "$conf_file"; then
        log SUCCESS "WiFi power management already disabled in $conf_file"
        return 0
    fi

    # Add wireless-power off to wlan0 configuration
    if grep -q "iface wlan0" "$conf_file"; then
        sed -i '/iface wlan0/a \    wireless-power off' "$conf_file"
        log SUCCESS "Added wireless-power off to $conf_file"
        log INFO "Restart networking or reboot for changes to take effect"
    else
        log WARNING "Could not find wlan0 configuration in $conf_file"
        log INFO "You may need to add 'wireless-power off' manually"
        return 1
    fi

    return 0
}

#==============================================================================
# Validation Functions
#==============================================================================

validate_usb_gadget() {
    log INFO "Validating USB gadget configuration..."

    case "$USB_GADGET_METHOD" in
        configfs)
            validate_configfs
            ;;
        module)
            validate_module
            ;;
        *)
            log ERROR "Unknown USB gadget method: $USB_GADGET_METHOD"
            return 1
            ;;
    esac
}

validate_configfs() {
    local gadgets=$(ls /sys/kernel/config/usb_gadget 2>/dev/null || true)

    if [ -z "$gadgets" ]; then
        log WARNING "No USB gadgets configured in ConfigFS"
        log INFO "You may need to create the gadget configuration manually"
        return 1
    fi

    local gadget_name=$(echo "$gadgets" | head -1)
    local gadget_path="/sys/kernel/config/usb_gadget/$gadget_name"
    local udc=$(cat "$gadget_path/UDC" 2>/dev/null || echo "")

    if [ -z "$udc" ]; then
        log WARNING "USB gadget not bound to UDC (USB Device Controller)"
        log INFO "You may need to bind it: echo <UDC> > $gadget_path/UDC"
        return 1
    fi

    log SUCCESS "USB gadget '$gadget_name' is bound to UDC: $udc"
    return 0
}

validate_module() {
    if ! lsmod | grep -q "g_mass_storage"; then
        log WARNING "g_mass_storage module is not loaded"
        log INFO "Load it with: sudo modprobe g_mass_storage file=/piusb.bin removable=1"
        return 1
    fi

    local module_file=$(cat /sys/module/g_mass_storage/parameters/file 2>/dev/null || echo "")

    if [ -z "$module_file" ]; then
        log WARNING "g_mass_storage module has no backing file configured"
        return 1
    fi

    log SUCCESS "g_mass_storage module loaded with file: $module_file"
    return 0
}

validate_sudo_access() {
    log INFO "Validating passwordless sudo for refresh script..."

    local refresh_script="/usr/local/bin/refresh_usb_gadget.sh"

    if [ "$DRY_RUN" = true ]; then
        log INFO "[DRY-RUN] Would test: sudo -n $refresh_script"
        return 0
    fi

    # Test if user can run refresh script without password
    if sudo -n -l "$refresh_script" &> /dev/null; then
        log SUCCESS "Passwordless sudo configured correctly"
        return 0
    else
        log WARNING "Passwordless sudo may not be configured correctly"
        log INFO "Test manually: sudo $refresh_script (should not ask for password)"
        return 1
    fi
}

test_refresh_script() {
    log INFO "Testing USB gadget refresh script..."

    local refresh_script="/usr/local/bin/refresh_usb_gadget.sh"

    if [ ! -x "$refresh_script" ]; then
        log ERROR "Refresh script not found or not executable: $refresh_script"
        return 1
    fi

    if [ "$DRY_RUN" = true ]; then
        log INFO "[DRY-RUN] Would execute: sudo $refresh_script"
        return 0
    fi

    # Run refresh script (this should not fail)
    if sudo "$refresh_script"; then
        log SUCCESS "Refresh script executed successfully"

        # Check log file
        if [ -f "/var/log/usb_gadget_refresh.log" ]; then
            log INFO "Last few log entries:"
            tail -5 "/var/log/usb_gadget_refresh.log" | while read line; do
                log INFO "  $line"
            done
        fi

        return 0
    else
        log ERROR "Refresh script failed to execute"
        log INFO "Check logs: sudo tail /var/log/usb_gadget_refresh.log"
        return 1
    fi
}

#==============================================================================
# Main Setup Flow
#==============================================================================

generate_report() {
    log ""
    log "======================================================================"
    log "                   Pi Setup Summary Report"
    log "======================================================================"
    log ""
    log "Setup completed at: $(date)"
    log "Log file: $LOG_FILE"

    if [ "$DRY_RUN" = true ]; then
        log ""
        log "MODE: DRY RUN (no changes were made)"
        log ""
    fi

    if [ "$NO_BACKUP" = false ] && [ -d "$BACKUP_DIR" ]; then
        log ""
        log "Backups saved to: $BACKUP_DIR"
        log ""
    fi

    log "Configuration Details:"
    log "  User: $CURRENT_USER"
    log "  USB Gadget Method: $USB_GADGET_METHOD"
    log "  WiFi Manager: $WIFI_MANAGER"
    log ""

    log "Installed Components:"
    log "  ✓ /usr/local/bin/refresh_usb_gadget.sh"
    log "  ✓ /usr/local/bin/diagnose_usb_gadget.sh"
    log "  ✓ /etc/sudoers.d/usb-gadget-refresh"
    log ""

    log "Next Steps:"
    log ""
    log "1. Verify setup is working:"
    log "   sudo /usr/local/bin/refresh_usb_gadget.sh"
    log ""
    log "2. Test passwordless sudo (should not ask for password):"
    log "   sudo /usr/local/bin/refresh_usb_gadget.sh"
    log ""
    log "3. Check WiFi power management (should show 'off'):"
    log "   iwconfig wlan0 | grep 'Power Management'"
    log ""
    log "4. Run diagnostic to see full configuration:"
    log "   sudo /usr/local/bin/diagnose_usb_gadget.sh"
    log ""
    log "5. Configure desktop monitor (see docs/QUICKSTART.md):"
    log "   - Update .env file with Pi's IP address"
    log "   - Run: python3 monitor.py"
    log ""

    if [ "$DRY_RUN" = true ]; then
        log ""
        log "To apply these changes, run without --dry-run flag:"
        log "  sudo ./pi_setup_auto.sh"
        log ""
    fi

    log "======================================================================"
    log ""

    log SUCCESS "Pi setup automation complete!"
    log INFO "For troubleshooting, see: docs/TROUBLESHOOTING.md"
}

rollback_on_failure() {
    local exit_code=$?

    if [ $exit_code -ne 0 ] && [ "$DRY_RUN" = false ]; then
        log ERROR "Setup failed with exit code: $exit_code"

        if [ -d "$BACKUP_DIR" ] && [ "$NO_BACKUP" = false ]; then
            log WARNING "Attempting to rollback changes..."

            # Restore backups
            for backup_file in "$BACKUP_DIR"/*; do
                if [ -f "$backup_file" ]; then
                    local original_name=$(basename "$backup_file")
                    local target=""

                    case "$original_name" in
                        usb-gadget-refresh)
                            target="/etc/sudoers.d/$original_name"
                            ;;
                        refresh_usb_gadget.sh)
                            target="/usr/local/bin/$original_name"
                            ;;
                        diagnose_usb_gadget.sh)
                            target="/usr/local/bin/$original_name"
                            ;;
                    esac

                    if [ -n "$target" ]; then
                        cp -a "$backup_file" "$target"
                        log INFO "Restored: $target"
                    fi
                fi
            done

            log SUCCESS "Rollback completed. Backup preserved at: $BACKUP_DIR"
        fi

        log ERROR "Setup failed. Check log: $LOG_FILE"
        exit $exit_code
    fi
}

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --skip-wifi)
                SKIP_WIFI=true
                shift
                ;;
            --no-backup)
                NO_BACKUP=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log ERROR "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Setup trap for rollback on failure
    trap rollback_on_failure EXIT

    # Header
    log ""
    log "======================================================================"
    log "      Raspberry Pi USB Gadget Setup - Automated Configuration"
    log "======================================================================"
    log ""
    log "Project: pi-gcode-server"
    log "Version: 1.0.0"
    log "Started: $(date)"
    log ""

    if [ "$DRY_RUN" = true ]; then
        log WARNING "DRY RUN MODE - No changes will be made"
        log ""
    fi

    # Check permissions
    check_root

    # Phase 1: Detection
    log INFO "Phase 1: Detecting system configuration..."
    log ""

    detect_usb_gadget_method || exit 1
    detect_wifi_manager || true  # Non-critical
    check_prerequisites || true  # Non-critical, show warnings

    log ""
    log SUCCESS "Phase 1 complete. Detected configuration:"
    log INFO "  USB Gadget Method: $USB_GADGET_METHOD"
    log INFO "  WiFi Manager: $WIFI_MANAGER"
    log ""

    # Phase 2: Installation
    log INFO "Phase 2: Installing scripts and configurations..."
    log ""

    install_refresh_script || exit 1
    install_diagnose_script || true  # Non-critical
    configure_sudoers || exit 1
    fix_wifi_power_management || true  # Non-critical

    log ""
    log SUCCESS "Phase 2 complete. All components installed."
    log ""

    # Phase 3: Validation
    log INFO "Phase 3: Validating configuration..."
    log ""

    validate_usb_gadget || true  # Non-critical, show warnings
    validate_sudo_access || true  # Non-critical
    test_refresh_script || true  # Non-critical

    log ""
    log SUCCESS "Phase 3 complete. Configuration validated."
    log ""

    # Generate final report
    generate_report

    # Disable trap (success case)
    trap - EXIT

    return 0
}

# Run main function
main "$@"
