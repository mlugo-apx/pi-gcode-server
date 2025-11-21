# Raspberry Pi Quick Setup Guide

**One-command automated setup for pi-gcode-server**

This guide gets your Raspberry Pi configured in minutes instead of hours.

---

## Prerequisites (5 minutes)

### Step 1: Initial OS Setup

1. Flash Raspberry Pi OS using [Raspberry Pi Imager](https://www.raspberrypi.com/software/)
2. In Imager advanced options (Ctrl+Shift+X):
   - Enable SSH
   - Set username and password
   - Configure WiFi
3. Boot Pi and SSH in: `ssh your_username@raspberrypi.local`

### Step 2: Enable USB Gadget Modules

```bash
# Add to /boot/config.txt (or /boot/firmware/config.txt on newer Pi OS)
echo "dtoverlay=dwc2" | sudo tee -a /boot/config.txt

# Add to /etc/modules
echo -e "dwc2\nlibcomposite" | sudo tee -a /etc/modules

# Update system
sudo apt update && sudo apt upgrade -y
sudo apt install -y rsync openssh-server network-manager

# Reboot to load modules
sudo reboot
```

Wait for Pi to reboot, then SSH back in.

### Step 3: Create USB Storage Image

```bash
# Create 2GB FAT32 image file
sudo dd if=/dev/zero of=/piusb.bin bs=1M count=2048 status=progress
sudo mkfs.vfat /piusb.bin

# Create mount point
sudo mkdir -p /mnt/usb_share

# Add to /etc/fstab for auto-mount on boot
echo "/piusb.bin  /mnt/usb_share  vfat  loop,rw,users,umask=000  0  0" | sudo tee -a /etc/fstab

# Mount it now
sudo mount -a

# Verify mount worked
df -h | grep usb_share
```

---

## Automated Setup (2 minutes)

### Copy Scripts to Pi

**On your desktop** (from project directory):

```bash
# Copy all Pi scripts to Pi
scp pi_scripts/*.sh your_username@raspberrypi.local:/tmp/
```

### Run Automation

**On the Pi**:

```bash
# Change to temp directory
cd /tmp

# Make script executable
chmod +x pi_setup_auto.sh

# Preview changes (recommended first time)
sudo ./pi_setup_auto.sh --dry-run

# Run full automated setup
sudo ./pi_setup_auto.sh
```

### What It Does

The script automatically:
- ✅ Detects your USB gadget configuration (ConfigFS or module)
- ✅ Installs the correct refresh script
- ✅ Sets up passwordless sudo for refresh script
- ✅ Disables WiFi power management (critical for performance!)
- ✅ Validates everything works
- ✅ Creates backups before any changes

---

## Verification (1 minute)

```bash
# Test refresh script (should not ask for password)
sudo /usr/local/bin/refresh_usb_gadget.sh

# Check WiFi power management (should show "off")
iwconfig wlan0 | grep "Power Management"

# Run full diagnostic
sudo /usr/local/bin/diagnose_usb_gadget.sh

# Check USB gadget status
# For ConfigFS:
cat /sys/kernel/config/usb_gadget/*/UDC

# For module:
lsmod | grep g_mass_storage
```

---

## Desktop Configuration

Now configure your desktop to send files to the Pi:

```bash
# On your desktop, in project directory
cp .env.example .env

# Edit .env and set:
# PI_HOST=raspberrypi.local (or your Pi's IP address)
# PI_USERNAME=your_username
# PI_SSH_PORT=22

# Test connection
python3 monitor.py --test

# Start monitoring (sends files to Pi automatically)
python3 monitor.py
```

---

## Copy-Paste Cheat Sheet

### Complete Setup (Copy all at once on Pi)

```bash
# Prerequisites (run after fresh Pi OS install)
echo "dtoverlay=dwc2" | sudo tee -a /boot/config.txt
echo -e "dwc2\nlibcomposite" | sudo tee -a /etc/modules
sudo apt update && sudo apt upgrade -y
sudo apt install -y rsync openssh-server network-manager
sudo dd if=/dev/zero of=/piusb.bin bs=1M count=2048 status=progress
sudo mkfs.vfat /piusb.bin
sudo mkdir -p /mnt/usb_share
echo "/piusb.bin  /mnt/usb_share  vfat  loop,rw,users,umask=000  0  0" | sudo tee -a /etc/fstab
sudo reboot
```

After reboot:

```bash
# Wait for scripts to be copied via scp, then:
cd /tmp
chmod +x pi_setup_auto.sh
sudo ./pi_setup_auto.sh
```

---

## Troubleshooting

### Script fails: "No USB gadget found"

```bash
# Check modules loaded
lsmod | grep -E "dwc2|libcomposite"

# If not loaded, load manually
sudo modprobe dwc2
sudo modprobe libcomposite

# Try again
sudo ./pi_setup_auto.sh
```

### WiFi power management not disabled

```bash
# Manual NetworkManager fix
sudo nmcli connection modify preconfigured 802-11-wireless.powersave 2
sudo nmcli connection down preconfigured && sudo nmcli connection up preconfigured

# Verify
iwconfig wlan0 | grep "Power Management"
```

### Refresh script fails

```bash
# Check logs
sudo tail -50 /var/log/usb_gadget_refresh.log

# Run diagnostic
sudo /usr/local/bin/diagnose_usb_gadget.sh

# Test manually
sudo /usr/local/bin/refresh_usb_gadget.sh
```

### Need to rollback changes

```bash
# Backups are in home directory
ls -la ~/.pi_setup_backup_*

# Restore manually
sudo cp ~/.pi_setup_backup_*/usb-gadget-refresh /etc/sudoers.d/
```

---

## Performance Tips

After setup, optimize for best performance:

```bash
# Verify WiFi power management is OFF (most important!)
iwconfig wlan0 | grep "Power Management"
# Should show: Power Management:off

# Check network speed
ping -c 100 raspberrypi.local | grep loss
# Should be <1% packet loss

# Optional: Network tuning
echo "net.core.rmem_max=16777216" | sudo tee -a /etc/sysctl.conf
echo "net.core.wmem_max=16777216" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

Expected performance:
- **Without WiFi fix**: 260 KB/s (unusable)
- **With WiFi fix**: 5.5 MB/s (21x faster!)

See `docs/NETWORK_OPTIMIZATION_RESULTS.md` for details.

---

## Next Steps

1. **Connect Pi to 3D printer** via USB cable (data-capable, not power-only)
2. **Reboot printer** (some printers need cold boot to detect USB device)
3. **Test file transfer**: Copy a gcode file to Desktop, it should appear on printer
4. **Setup monitoring**: Run `python3 monitor.py` on desktop to automatically sync files

For detailed setup and troubleshooting, see:
- [docs/PI_SETUP.md](../docs/PI_SETUP.md) - Complete manual setup guide
- [docs/QUICKSTART.md](../docs/QUICKSTART.md) - Desktop configuration
- [docs/TROUBLESHOOTING.md](../docs/TROUBLESHOOTING.md) - Common issues

---

## Support

Questions or issues?
- Check [docs/TROUBLESHOOTING.md](../docs/TROUBLESHOOTING.md)
- Run diagnostic: `sudo /usr/local/bin/diagnose_usb_gadget.sh`
- Open a GitHub issue with diagnostic output

Project: [pi-gcode-server](https://github.com/yourusername/pi-gcode-server)
