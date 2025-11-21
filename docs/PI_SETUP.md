# Raspberry Pi Setup Guide

Complete guide for configuring your Raspberry Pi as a USB mass storage gadget for 3D printer file transfers.

---

## Table of Contents

- [Quick Start: Automated Setup](#quick-start-automated-setup) **← NEW! Recommended**
- [Hardware Requirements](#hardware-requirements)
- [Initial Pi Setup](#initial-pi-setup)
- [USB Gadget Configuration](#usb-gadget-configuration)
  - [Method 1: ConfigFS (Recommended)](#method-1-configfs-recommended)
  - [Method 2: g_mass_storage Module](#method-2-g_mass_storage-module)
- [Network Optimization](#network-optimization)
- [SSH Configuration](#ssh-configuration)
- [USB Gadget Refresh Scripts](#usb-gadget-refresh-scripts)
- [Testing & Verification](#testing--verification)
- [Troubleshooting](#troubleshooting)

---

## Quick Start: Automated Setup

**NEW!** Skip manual configuration with our automated setup script that handles all the tedious steps for you.

### Prerequisites

Before running the automation script, you need:

1. **Raspberry Pi OS installed** (Lite or Desktop)
2. **USB gadget modules enabled** in `/boot/config.txt` and `/etc/modules`:
   ```bash
   # In /boot/config.txt
   dtoverlay=dwc2

   # In /etc/modules
   dwc2
   libcomposite
   ```
3. **FAT32 image file created**:
   ```bash
   sudo dd if=/dev/zero of=/piusb.bin bs=1M count=2048
   sudo mkfs.vfat /piusb.bin
   sudo mkdir -p /mnt/usb_share
   ```
4. **Image mounted** (add to `/etc/fstab`):
   ```bash
   /piusb.bin  /mnt/usb_share  vfat  loop,rw,users,umask=000  0  0
   ```

Then reboot: `sudo reboot`

### Running the Automation Script

1. **Copy scripts to your Pi**:
   ```bash
   # On your desktop (from project directory)
   scp pi_scripts/*.sh your_username@raspberrypi.local:/tmp/
   ```

2. **SSH into Pi and run automation**:
   ```bash
   # SSH to Pi
   ssh your_username@raspberrypi.local

   # Move scripts to working directory
   cd /tmp

   # Preview what will be done (dry-run mode)
   sudo bash pi_setup_auto.sh --dry-run

   # Run full automated setup
   sudo bash pi_setup_auto.sh
   ```

3. **What it does automatically**:
   - ✅ Auto-detects USB gadget method (ConfigFS vs g_mass_storage module)
   - ✅ Installs correct refresh script to `/usr/local/bin/`
   - ✅ Configures passwordless sudo for refresh script
   - ✅ Fixes WiFi power management (disables power save mode)
   - ✅ Validates entire configuration
   - ✅ Creates backups before modifying system files

4. **Verify setup worked**:
   ```bash
   # Test refresh script (should not ask for password)
   sudo /usr/local/bin/refresh_usb_gadget.sh

   # Check WiFi power management (should show "off")
   iwconfig wlan0 | grep "Power Management"

   # Run diagnostic to see full configuration
   sudo /usr/local/bin/diagnose_usb_gadget.sh
   ```

### Script Options

```bash
# Show help and available options
sudo bash pi_setup_auto.sh --help

# Dry-run mode (preview changes without applying)
sudo bash pi_setup_auto.sh --dry-run

# Skip WiFi power management configuration
sudo bash pi_setup_auto.sh --skip-wifi

# Skip backup creation (not recommended)
sudo bash pi_setup_auto.sh --no-backup
```

### Troubleshooting Automated Setup

**Script fails with "No USB gadget found"**:
- Ensure you've rebooted after adding modules to `/boot/config.txt` and `/etc/modules`
- Verify modules are loaded: `lsmod | grep -E "dwc2|libcomposite|g_mass_storage"`
- Load manually if needed: `sudo modprobe dwc2 && sudo modprobe libcomposite`

**Script fails with "Permission denied"**:
- Make sure you're running with `sudo`
- Check script has execute permissions: `chmod +x pi_setup_auto.sh`

**WiFi configuration fails**:
- Skip it and configure manually: `sudo bash pi_setup_auto.sh --skip-wifi`
- See [Network Optimization](#network-optimization) section below

**Need to rollback changes**:
- Backups are saved to `~/.pi_setup_backup_<timestamp>/`
- Restore manually or re-run setup

---

## Manual Setup (Alternative)

If you prefer manual configuration or the automated script doesn't work for your setup, follow the sections below:

---

## Hardware Requirements

### Supported Models

**Recommended**:
- **Raspberry Pi Zero 2W** - Best performance (quad-core, 1GHz)
- **Raspberry Pi Zero W** - Budget option (single-core, works well)

**Also Compatible** (requires USB OTG adapter):
- Raspberry Pi 3/4/5
- Raspberry Pi 400

### Required Hardware

- **Micro-USB cable** - Data-capable (not just power-only)
- **SD card** - 8GB minimum, 16GB+ recommended
- **WiFi network** - 2.4GHz minimum (5GHz preferred if Pi supports it)
- **3D Printer** - With USB mass storage support

---

## Initial Pi Setup

### 1. Install Raspberry Pi OS

```bash
# Download Raspberry Pi OS Lite (headless) or Desktop
# Use Raspberry Pi Imager: https://www.raspberrypi.com/software/

# Enable SSH during imaging (Imager: Advanced Options)
# Set hostname, username, WiFi credentials
```

### 2. First Boot Configuration

```bash
# SSH into Pi
ssh your_username@raspberrypi.local

# Update system
sudo apt update && sudo apt upgrade -y

# Install required packages
sudo apt install -y rsync openssh-server network-manager
```

### 3. Enable USB Gadget Support

Edit `/boot/config.txt`:
```bash
sudo nano /boot/config.txt

# Add at the end:
dtoverlay=dwc2
```

Edit `/etc/modules`:
```bash
sudo nano /etc/modules

# Add these lines:
dwc2
libcomposite
```

**Reboot required**:
```bash
sudo reboot
```

---

## USB Gadget Configuration

Choose **one** of the following methods. ConfigFS is recommended for modern Raspberry Pi OS versions.

### Method 1: ConfigFS (Recommended)

ConfigFS provides more flexibility and is the modern approach for USB gadget configuration.

#### Step 1: Create FAT32 Image File

```bash
# Create 2GB image file
sudo dd if=/dev/zero of=/piusb.bin bs=1M count=2048

# Format as FAT32
sudo mkfs.vfat /piusb.bin

# Create mount point
sudo mkdir -p /mnt/usb_share

# Mount the image
sudo mount -o loop,rw,users,umask=000 /piusb.bin /mnt/usb_share
```

#### Step 2: Auto-Mount on Boot

Add to `/etc/fstab`:
```bash
sudo nano /etc/fstab

# Add this line:
/piusb.bin  /mnt/usb_share  vfat  loop,rw,users,umask=000  0  0
```

#### Step 3: Create USB Gadget Configuration Script

Create `/usr/local/bin/usb_gadget_init.sh`:
```bash
sudo nano /usr/local/bin/usb_gadget_init.sh
```

Paste this content:
```bash
#!/bin/bash
# USB Gadget ConfigFS initialization script

cd /sys/kernel/config/usb_gadget/
mkdir -p g1
cd g1

# USB Device Descriptor
echo 0x1d6b > idVendor  # Linux Foundation
echo 0x0104 > idProduct # Multifunction Composite Gadget
echo 0x0100 > bcdDevice # v1.0.0
echo 0x0200 > bcdUSB    # USB 2.0

# Device Strings
mkdir -p strings/0x409
echo "fedcba9876543210" > strings/0x409/serialnumber
echo "Raspberry Pi" > strings/0x409/manufacturer
echo "Pi USB Storage" > strings/0x409/product

# Configuration
mkdir -p configs/c.1/strings/0x409
echo "Config 1: Mass Storage" > configs/c.1/strings/0x409/configuration
echo 250 > configs/c.1/MaxPower

# Mass Storage Function
mkdir -p functions/mass_storage.usb0
echo 1 > functions/mass_storage.usb0/stall
echo 0 > functions/mass_storage.usb0/lun.0/cdrom
echo 0 > functions/mass_storage.usb0/lun.0/ro
echo 0 > functions/mass_storage.usb0/lun.0/nofua
echo /piusb.bin > functions/mass_storage.usb0/lun.0/file

# Link function to configuration
ln -s functions/mass_storage.usb0 configs/c.1/

# Bind to UDC (USB Device Controller)
UDC=$(ls /sys/class/udc | head -n1)
echo "$UDC" > UDC
```

Make it executable:
```bash
sudo chmod +x /usr/local/bin/usb_gadget_init.sh
```

#### Step 4: Create Systemd Service

Create `/etc/systemd/system/usb-gadget.service`:
```bash
sudo nano /etc/systemd/system/usb-gadget.service
```

Paste this content:
```ini
[Unit]
Description=USB Gadget Mass Storage
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/usb_gadget_init.sh
ExecStop=/bin/sh -c 'echo "" > /sys/kernel/config/usb_gadget/g1/UDC'

[Install]
WantedBy=multi-user.target
```

Enable the service:
```bash
sudo systemctl daemon-reload
sudo systemctl enable usb-gadget.service
sudo systemctl start usb-gadget.service
```

#### Step 5: Verify ConfigFS Setup

```bash
# Check gadget is configured
ls /sys/kernel/config/usb_gadget/g1/

# Check UDC binding
cat /sys/kernel/config/usb_gadget/g1/UDC
# Should show something like: fe980000.usb

# Verify mount
mount | grep /mnt/usb_share
# Should show: /piusb.bin on /mnt/usb_share type vfat
```

---

### Method 2: g_mass_storage Module

Simpler but less flexible. Use this if ConfigFS doesn't work on your Pi model.

#### Step 1: Create FAT32 Image File

```bash
# Create 2GB image file
sudo dd if=/dev/zero of=/piusb.bin bs=1M count=2048

# Format as FAT32
sudo mkfs.vfat /piusb.bin

# Create mount point
sudo mkdir -p /mnt/usb_share

# Mount the image
sudo mount -o loop,rw,users,umask=000 /piusb.bin /mnt/usb_share
```

#### Step 2: Auto-Mount on Boot

Add to `/etc/fstab`:
```bash
sudo nano /etc/fstab

# Add this line:
/piusb.bin  /mnt/usb_share  vfat  loop,rw,users,umask=000  0  0
```

#### Step 3: Load Module on Boot

Edit `/etc/modules`:
```bash
sudo nano /etc/modules

# Add this line (replace with your file path):
dwc2
g_mass_storage file=/piusb.bin removable=1 stall=0
```

**Reboot required**:
```bash
sudo reboot
```

#### Step 4: Verify Module Setup

```bash
# Check module is loaded
lsmod | grep g_mass_storage

# Check module parameters
cat /sys/module/g_mass_storage/parameters/file
# Should show: /piusb.bin

cat /sys/module/g_mass_storage/parameters/ro
# Should show: N (not read-only)
```

---

## Network Optimization

**CRITICAL**: WiFi power management causes 95% of performance issues. **You MUST disable it**.

### Disable WiFi Power Management (Permanent)

Using NetworkManager (recommended):
```bash
# Get connection name
nmcli connection show

# Disable power save (replace 'preconfigured' with your connection name)
sudo nmcli connection modify preconfigured 802-11-wireless.powersave 2

# Reactivate connection
sudo nmcli connection down preconfigured
sudo nmcli connection up preconfigured

# Verify (should show "off")
iwconfig wlan0 | grep "Power Management"
```

**Without this fix**: 260 KB/s transfer speed (29.7% packet loss)
**With this fix**: 5.5 MB/s transfer speed (21x faster!)

Reference: `docs/NETWORK_OPTIMIZATION_RESULTS.md:40-56`

### Additional Network Tuning (Optional)

For even better performance, add to `/etc/sysctl.conf`:
```bash
sudo nano /etc/sysctl.conf

# Add at the end:
net.core.rmem_max=16777216
net.core.wmem_max=16777216
```

Apply changes:
```bash
sudo sysctl -p
```

Reference: `docs/NETWORK_OPTIMIZATION_RESULTS.md:96-114`

---

## SSH Configuration

### 1. Enable Passwordless SSH (Desktop → Pi)

On your **desktop** machine:
```bash
# Generate SSH key (if you don't have one)
ssh-keygen -t ed25519 -C "your_email@example.com"

# Copy public key to Pi
ssh-copy-id your_username@raspberrypi.local
```

Test passwordless login:
```bash
ssh your_username@raspberrypi.local
# Should NOT ask for password
```

### 2. Optimize SSH for File Transfers

On your **desktop** machine, edit `~/.ssh/config`:
```bash
nano ~/.ssh/config

# Add this configuration:
Host 192.168.1.6  # Replace with your Pi's IP
    User your_username
    IdentityFile ~/.ssh/id_ed25519
    Ciphers aes128-ctr,aes256-ctr,aes128-gcm@openssh.com
    Compression yes
    ServerAliveInterval 5
    ServerAliveCountMax 3
    StrictHostKeyChecking yes
```

**Why these settings?**
- `aes128-ctr`: Faster encryption on single-core ARM (vs chacha20-poly1305)
- `Compression yes`: 5-10x speedup for gcode files (~70% compressible)
- `ServerAliveInterval`: Keeps connection alive during transfers
- `StrictHostKeyChecking`: Security (reject unknown hosts)

Reference: `docs/NETWORK_OPTIMIZATION_RESULTS.md:60-94`

---

## USB Gadget Refresh Scripts

These scripts force the 3D printer to see new files without rebooting the Pi.

### 1. Copy Refresh Scripts to Pi

From your project directory on the **desktop**:
```bash
# Copy all Pi scripts
scp pi_scripts/*.sh your_username@raspberrypi.local:/tmp/

# SSH into Pi
ssh your_username@raspberrypi.local

# Move scripts to system location
sudo mv /tmp/refresh_usb_gadget*.sh /usr/local/bin/
sudo mv /tmp/diagnose_usb_gadget.sh /usr/local/bin/

# Make executable
sudo chmod +x /usr/local/bin/refresh_usb_gadget*.sh
sudo chmod +x /usr/local/bin/diagnose_usb_gadget.sh
```

### 2. Configure Passwordless Sudo

The desktop monitor needs to run the refresh script via SSH without a password prompt.

On the **Pi**, edit sudoers:
```bash
sudo visudo

# Add this line at the end (replace 'your_username'):
your_username ALL=(ALL) NOPASSWD: /usr/local/bin/refresh_usb_gadget.sh
```

**Security Notes**:
- This only allows passwordless sudo for this specific script, not all commands
- **Verify script integrity** after installation to ensure it hasn't been tampered with:

```bash
# Generate checksum after initial installation
sha256sum /usr/local/bin/refresh_usb_gadget.sh > ~/refresh_usb_gadget.sha256

# Later, verify the script hasn't been modified
sha256sum -c ~/refresh_usb_gadget.sha256

# Output should show: /usr/local/bin/refresh_usb_gadget.sh: OK
```

- If you update the script, regenerate the checksum
- Consider setting immutable flag to prevent modifications: `sudo chattr +i /usr/local/bin/refresh_usb_gadget.sh` (removes ability to modify even with root)

### 3. Test Refresh Script

```bash
# Run diagnostic to identify your USB gadget type
sudo /usr/local/bin/diagnose_usb_gadget.sh

# Test refresh (should complete without errors)
sudo /usr/local/bin/refresh_usb_gadget.sh

# Check logs
sudo tail -n 20 /var/log/usb_gadget_refresh.log
```

---

## Testing & Verification

### 1. Verify USB Gadget is Active

Connect Pi to 3D printer via USB cable, then:

```bash
# On Pi: Check UDC binding (ConfigFS)
cat /sys/kernel/config/usb_gadget/g1/UDC
# Should show UDC name (e.g., fe980000.usb)

# OR check module (g_mass_storage)
lsmod | grep g_mass_storage
# Should show module is loaded

# Check if printer sees the device (may require printer reboot)
# On printer UI: Look for USB storage device
```

### 2. Test File Transfer

On your **desktop**:
```bash
# Create test file
echo "test" > /tmp/test.gcode

# Copy to Pi
scp /tmp/test.gcode your_username@raspberrypi.local:/mnt/usb_share/

# Verify file on Pi
ssh your_username@raspberrypi.local "ls -lh /mnt/usb_share/"

# Test USB refresh
ssh your_username@raspberrypi.local "sudo /usr/local/bin/refresh_usb_gadget.sh"

# Check printer UI - file should appear within 5 seconds
```

### 3. Monitor Pi Performance

```bash
# WiFi power management (should be OFF)
iwconfig wlan0 | grep "Power Management"

# Network speed test
iperf3 -s  # On Pi (install with: sudo apt install iperf3)
iperf3 -c raspberrypi.local  # On desktop

# Disk I/O test
sudo dd if=/dev/zero of=/mnt/usb_share/test.bin bs=1M count=100
```

---

## Troubleshooting

### USB Gadget Not Detected by Printer

**Symptoms**: Printer doesn't see USB device after connecting Pi

**Solutions**:
1. **Reboot printer** (some printers need cold boot)
2. Check cable is data-capable (not power-only)
3. Verify USB gadget is bound:
   ```bash
   # ConfigFS
   cat /sys/kernel/config/usb_gadget/g1/UDC

   # Module
   lsmod | grep g_mass_storage
   ```
4. Check kernel messages:
   ```bash
   sudo dmesg | grep -i usb
   ```

### Slow Transfer Speeds

**Symptoms**: Transfers slower than 2 MB/s

**Solutions**:
1. **Verify WiFi power management is OFF** (most common cause):
   ```bash
   iwconfig wlan0 | grep "Power Management"
   # Should show: off
   ```
2. Check for packet loss:
   ```bash
   ping -c 100 192.168.1.6 | grep loss
   # Should be <1% loss
   ```
3. Verify SSH compression is enabled:
   ```bash
   ssh -v your_pi 2>&1 | grep -i compression
   # Should show: Enabling compression
   ```

### Printer Doesn't See New Files

**Symptoms**: File transfers successfully but doesn't appear on printer

**Solutions**:
1. **Run USB gadget refresh**:
   ```bash
   ssh your_pi "sudo /usr/local/bin/refresh_usb_gadget.sh"
   ```
2. Check refresh script logs:
   ```bash
   ssh your_pi "sudo tail -n 50 /var/log/usb_gadget_refresh.log"
   ```
3. Verify file is on Pi:
   ```bash
   ssh your_pi "ls -lh /mnt/usb_share/"
   ```

### ConfigFS Not Available

**Symptoms**: `/sys/kernel/config/usb_gadget` doesn't exist

**Solutions**:
1. Check kernel modules are loaded:
   ```bash
   lsmod | grep libcomposite
   ```
2. Load module manually:
   ```bash
   sudo modprobe libcomposite
   ```
3. If still not available, use g_mass_storage module method instead

### Module Won't Load

**Symptoms**: `modprobe g_mass_storage` fails

**Solutions**:
1. Check `dwc2` is loaded first:
   ```bash
   lsmod | grep dwc2
   sudo modprobe dwc2
   ```
2. Verify `/boot/config.txt` has `dtoverlay=dwc2`
3. Check kernel version supports USB gadget:
   ```bash
   uname -r  # Should be 4.9+
   ```

---

## Next Steps

After completing Pi setup:

1. **Configure desktop monitor**: See [QUICKSTART.md](QUICKSTART.md)
2. **Test end-to-end**: Copy a gcode file to Desktop and verify it appears on printer
3. **Optimize further**: See [NETWORK_OPTIMIZATION_RESULTS.md](NETWORK_OPTIMIZATION_RESULTS.md)
4. **Setup monitoring**: Add health check cron job (README section "Health Monitoring")

---

## Reference Information

### File Locations on Pi

| File/Directory | Purpose |
|----------------|---------|
| `/piusb.bin` | FAT32 image file (USB storage backing file) |
| `/mnt/usb_share/` | Mount point for image file |
| `/usr/local/bin/refresh_usb_gadget*.sh` | USB gadget refresh scripts |
| `/var/log/usb_gadget_refresh.log` | Refresh script log file |
| `/sys/kernel/config/usb_gadget/g1/` | ConfigFS gadget configuration |
| `/boot/config.txt` | Pi boot configuration (enables dwc2) |
| `/etc/modules` | Kernel modules to load at boot |
| `/etc/fstab` | Filesystem mount configuration |

### Key Commands

```bash
# Check USB gadget status (ConfigFS)
cat /sys/kernel/config/usb_gadget/g1/UDC

# Check USB gadget status (module)
lsmod | grep g_mass_storage

# Refresh USB gadget
sudo /usr/local/bin/refresh_usb_gadget.sh

# Diagnose USB gadget setup
sudo /usr/local/bin/diagnose_usb_gadget.sh

# Check WiFi power management
iwconfig wlan0 | grep "Power Management"

# View USB refresh logs
sudo tail -f /var/log/usb_gadget_refresh.log
```

---

## Additional Resources

- [Raspberry Pi USB Gadget Documentation](https://www.kernel.org/doc/html/latest/usb/gadget_configfs.html)
- [NetworkManager WiFi Power Save](https://wiki.archlinux.org/title/NetworkManager#Wi-Fi_power_saving)
- [Linux USB Gadget API](https://www.kernel.org/doc/html/latest/driver-api/usb/gadget.html)

---

**Questions or issues?** See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) or open a GitHub issue.
