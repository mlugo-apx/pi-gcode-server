# Raspberry Pi Scripts

Scripts for configuring and managing the Raspberry Pi USB gadget for pi-gcode-server.

---

## Quick Start (Automated Setup)

**Recommended for most users:**

```bash
# On your desktop (from project directory):
scp pi_scripts/*.sh pi@raspberrypi.local:/tmp/

# On your Pi:
ssh pi@raspberrypi.local
cd /tmp
chmod +x pi_setup_auto.sh
sudo ./pi_setup_auto.sh
```

See [QUICK_SETUP.md](QUICK_SETUP.md) for detailed instructions.

---

## Files

### Setup Scripts

- **`pi_setup_auto.sh`** - Main automation script (RECOMMENDED)
  - Auto-detects USB gadget configuration
  - Installs correct refresh script
  - Configures passwordless sudo
  - Fixes WiFi power management
  - Validates complete setup

### USB Gadget Refresh Scripts

- **`refresh_usb_gadget.sh`** - Universal auto-detecting refresh script
- **`refresh_usb_gadget_configfs.sh`** - ConfigFS-specific variant
- **`refresh_usb_gadget_module.sh`** - g_mass_storage module variant

### Diagnostic Tools

- **`diagnose_usb_gadget.sh`** - Comprehensive system diagnostic

### Documentation

- **`QUICK_SETUP.md`** - Copy-paste quick start guide (START HERE)
- **`TESTING_CHECKLIST.md`** - Comprehensive testing guide
- **`AUTOMATION_SUMMARY.md`** - Technical implementation details
- **`README.md`** - This file

---

## Usage

### Automated Setup (Recommended)

```bash
# Preview changes (dry-run)
sudo ./pi_setup_auto.sh --dry-run

# Full automated setup
sudo ./pi_setup_auto.sh

# Skip WiFi configuration
sudo ./pi_setup_auto.sh --skip-wifi

# Get help
sudo ./pi_setup_auto.sh --help
```

### Manual Refresh Script Installation

If you prefer manual setup or automation fails:

```bash
# For ConfigFS systems
sudo cp refresh_usb_gadget_configfs.sh /usr/local/bin/refresh_usb_gadget.sh
sudo chmod +x /usr/local/bin/refresh_usb_gadget.sh

# For g_mass_storage module systems
sudo cp refresh_usb_gadget_module.sh /usr/local/bin/refresh_usb_gadget.sh
sudo chmod +x /usr/local/bin/refresh_usb_gadget.sh

# Configure passwordless sudo
sudo visudo
# Add: your_username ALL=(ALL) NOPASSWD: /usr/local/bin/refresh_usb_gadget.sh
```

### Running Diagnostics

```bash
sudo ./diagnose_usb_gadget.sh
```

---

## Requirements

### Before Running Scripts

1. **Raspberry Pi OS installed** (Lite or Desktop)
2. **USB gadget modules enabled:**
   ```bash
   # In /boot/config.txt
   dtoverlay=dwc2

   # In /etc/modules
   dwc2
   libcomposite
   ```
3. **FAT32 image created and mounted:**
   ```bash
   sudo dd if=/dev/zero of=/piusb.bin bs=1M count=2048
   sudo mkfs.vfat /piusb.bin
   sudo mkdir -p /mnt/usb_share

   # Add to /etc/fstab:
   /piusb.bin  /mnt/usb_share  vfat  loop,rw,users,umask=000  0  0

   sudo mount -a
   ```

See [QUICK_SETUP.md](QUICK_SETUP.md) for complete prerequisite setup.

---

## Troubleshooting

### Common Issues

**"No USB gadget found":**
```bash
# Check modules loaded
lsmod | grep -E "dwc2|libcomposite|g_mass_storage"

# Load manually
sudo modprobe dwc2
sudo modprobe libcomposite
```

**"Permission denied":**
```bash
# Make sure you're using sudo
sudo ./pi_setup_auto.sh

# Check script is executable
chmod +x pi_setup_auto.sh
```

**WiFi power management still enabled:**
```bash
# Manual fix
sudo nmcli connection modify preconfigured 802-11-wireless.powersave 2
sudo nmcli connection down preconfigured
sudo nmcli connection up preconfigured

# Verify
iwconfig wlan0 | grep "Power Management"
```

See [TESTING_CHECKLIST.md](TESTING_CHECKLIST.md) for more troubleshooting steps.

---

## What Each Script Does

### pi_setup_auto.sh

Automates the entire Pi setup process:

1. **Detects** USB gadget configuration (ConfigFS or module)
2. **Installs** appropriate refresh script to `/usr/local/bin/`
3. **Configures** passwordless sudo for refresh script only
4. **Fixes** WiFi power management (optional)
5. **Validates** complete setup
6. **Creates** backups before any modifications

Safety features:
- Dry-run mode to preview changes
- Automatic rollback on failure
- Idempotent (safe to run multiple times)
- Comprehensive logging

### refresh_usb_gadget.sh (Universal)

Auto-detects USB gadget method and refreshes accordingly:
- For ConfigFS: Unbinds/rebinds UDC
- For module: Removes/reinserts g_mass_storage module
- Syncs filesystem before refresh
- Logs all operations to `/var/log/usb_gadget_refresh.log`

Forces 3D printer to re-enumerate USB device and see new files.

### diagnose_usb_gadget.sh

Comprehensive diagnostic that checks:
- Loaded kernel modules
- USB gadget configuration (ConfigFS or module)
- Boot configuration (/boot/config.txt)
- Mount points and backing files
- Recent kernel messages
- Provides troubleshooting guidance

---

## Documentation Hierarchy

1. **Start Here:** [QUICK_SETUP.md](QUICK_SETUP.md)
   - Copy-paste commands to get started
   - Fastest path to working setup

2. **Testing:** [TESTING_CHECKLIST.md](TESTING_CHECKLIST.md)
   - Comprehensive test scenarios
   - Validation commands
   - Issue reporting template

3. **Technical Details:** [AUTOMATION_SUMMARY.md](AUTOMATION_SUMMARY.md)
   - Implementation details
   - Design decisions
   - Future enhancements

4. **Complete Manual Setup:** [../docs/PI_SETUP.md](../docs/PI_SETUP.md)
   - Detailed manual configuration guide
   - Background information
   - Alternative approaches

---

## Support

Questions or issues?

1. Run diagnostic: `sudo ./diagnose_usb_gadget.sh`
2. Check logs: `sudo tail -50 /var/log/usb_gadget_refresh.log`
3. Review troubleshooting: [TESTING_CHECKLIST.md](TESTING_CHECKLIST.md)
4. See main docs: [../docs/TROUBLESHOOTING.md](../docs/TROUBLESHOOTING.md)
5. Open GitHub issue with diagnostic output

---

## License

Part of pi-gcode-server project - MIT License

---

**Last Updated:** 2025-11-21
**Automation Version:** 1.0.0
