# Pi Setup Automation Testing Checklist

This checklist helps verify that `pi_setup_auto.sh` works correctly across different Pi configurations.

## Test Scenarios

### Scenario 1: Fresh Pi with ConfigFS

**Setup:**
- Fresh Raspberry Pi OS (Bullseye/Bookworm)
- USB gadget modules loaded (dwc2, libcomposite)
- /piusb.bin created and mounted
- ConfigFS available at `/sys/kernel/config/usb_gadget`

**Test Steps:**
```bash
# 1. Copy scripts to Pi
scp pi_scripts/*.sh pi@raspberrypi.local:/tmp/

# 2. SSH to Pi
ssh pi@raspberrypi.local

# 3. Dry-run test
cd /tmp
sudo ./pi_setup_auto.sh --dry-run

# 4. Full run
sudo ./pi_setup_auto.sh

# 5. Verify installation
ls -la /usr/local/bin/refresh_usb_gadget*.sh
sudo -l /usr/local/bin/refresh_usb_gadget.sh
iwconfig wlan0 | grep "Power Management"

# 6. Test refresh script
sudo /usr/local/bin/refresh_usb_gadget.sh

# 7. Check logs
sudo tail -20 /var/log/usb_gadget_refresh.log
```

**Expected Results:**
- ✅ Script detects ConfigFS method
- ✅ Installs `refresh_usb_gadget_configfs.sh` to `/usr/local/bin/refresh_usb_gadget.sh`
- ✅ Creates sudoers entry for current user
- ✅ Disables WiFi power management
- ✅ Refresh script runs without errors
- ✅ Backup directory created at `~/.pi_setup_backup_*`

---

### Scenario 2: Fresh Pi with g_mass_storage Module

**Setup:**
- Fresh Raspberry Pi OS
- USB gadget modules loaded (dwc2, g_mass_storage)
- /piusb.bin created and mounted
- g_mass_storage module loaded with file parameter

**Test Steps:**
```bash
# 1. Load g_mass_storage module
sudo modprobe g_mass_storage file=/piusb.bin removable=1 stall=0

# 2. Verify module loaded
lsmod | grep g_mass_storage

# 3. Copy and run automation
scp pi_scripts/*.sh pi@raspberrypi.local:/tmp/
ssh pi@raspberrypi.local
cd /tmp
sudo ./pi_setup_auto.sh --dry-run
sudo ./pi_setup_auto.sh

# 4. Verify
ls -la /usr/local/bin/refresh_usb_gadget*.sh
sudo /usr/local/bin/refresh_usb_gadget.sh
```

**Expected Results:**
- ✅ Script detects module method
- ✅ Installs `refresh_usb_gadget_module.sh` to `/usr/local/bin/refresh_usb_gadget.sh`
- ✅ Refresh script removes and re-inserts module correctly
- ✅ Module parameters preserved after refresh

---

### Scenario 3: Already Configured Pi (Idempotence Test)

**Setup:**
- Pi with automation already run once
- All components already installed

**Test Steps:**
```bash
# Run automation again
cd /tmp
sudo ./pi_setup_auto.sh
```

**Expected Results:**
- ✅ Script runs without errors
- ✅ Detects existing configurations
- ✅ Skips redundant steps gracefully
- ✅ Reports "already configured" where appropriate
- ✅ No duplicate sudoers entries

---

### Scenario 4: Missing Prerequisites

**Setup:**
- Pi with modules loaded BUT /piusb.bin NOT created

**Test Steps:**
```bash
# Remove /piusb.bin if it exists
sudo umount /mnt/usb_share
sudo rm /piusb.bin

# Run automation
cd /tmp
sudo ./pi_setup_auto.sh
```

**Expected Results:**
- ✅ Script warns about missing /piusb.bin
- ✅ Continues with installation of other components
- ✅ Provides instructions for creating /piusb.bin
- ⚠️ Refresh script may not work until /piusb.bin created

---

### Scenario 5: Dry-Run Mode (No Changes)

**Setup:**
- Any Pi configuration

**Test Steps:**
```bash
# Run dry-run multiple times
sudo ./pi_setup_auto.sh --dry-run
sudo ./pi_setup_auto.sh --dry-run

# Verify no changes made
ls -la /usr/local/bin/refresh_usb_gadget.sh
cat /etc/sudoers.d/usb-gadget-refresh
```

**Expected Results:**
- ✅ Script shows what WOULD be done
- ✅ No files actually modified
- ✅ No backup directories created
- ✅ Can run multiple times safely

---

### Scenario 6: Skip WiFi Configuration

**Setup:**
- Pi with NetworkManager but user wants to configure WiFi manually

**Test Steps:**
```bash
cd /tmp
sudo ./pi_setup_auto.sh --skip-wifi

# Verify WiFi untouched
nmcli connection show preconfigured | grep powersave
```

**Expected Results:**
- ✅ Script skips WiFi configuration
- ✅ WiFi power save settings unchanged
- ✅ All other components installed correctly

---

### Scenario 7: NetworkManager vs wpa_supplicant

**Setup A (NetworkManager):**
- Pi with NetworkManager installed and active

**Test Steps:**
```bash
# Verify NetworkManager active
systemctl is-active NetworkManager

# Run automation
sudo ./pi_setup_auto.sh

# Check setting
nmcli connection show preconfigured | grep powersave
```

**Expected Results:**
- ✅ Detects NetworkManager
- ✅ Disables power save using `nmcli`
- ✅ Power management shows "off" after reactivation

**Setup B (wpa_supplicant):**
- Pi with wpa_supplicant (no NetworkManager)

**Test Steps:**
```bash
# Verify wpa_supplicant active
systemctl is-active wpa_supplicant

# Run automation
sudo ./pi_setup_auto.sh

# Check config
grep "wireless-power" /etc/network/interfaces
```

**Expected Results:**
- ✅ Detects wpa_supplicant
- ✅ Adds `wireless-power off` to interfaces file
- ✅ Provides restart instructions

---

### Scenario 8: Rollback on Failure

**Setup:**
- Pi with valid configuration
- Simulate failure (e.g., make /usr/local/bin read-only)

**Test Steps:**
```bash
# Make target directory read-only
sudo chmod 555 /usr/local/bin

# Try to run automation (should fail)
sudo ./pi_setup_auto.sh || true

# Check if rollback happened
ls -la ~/.pi_setup_backup_*

# Restore permissions
sudo chmod 755 /usr/local/bin
```

**Expected Results:**
- ✅ Script detects failure
- ✅ Attempts rollback from backup
- ✅ Preserves backup directory
- ✅ Logs error details

---

### Scenario 9: Permissions Test

**Setup:**
- Pi with standard user account

**Test Steps:**
```bash
# Try running without sudo (should fail)
./pi_setup_auto.sh

# Run with sudo (should work)
sudo ./pi_setup_auto.sh

# Test passwordless sudo
sudo /usr/local/bin/refresh_usb_gadget.sh

# Should NOT ask for password
```

**Expected Results:**
- ✅ Script requires sudo
- ✅ Clear error message if run without sudo
- ✅ Passwordless sudo works after setup
- ✅ Only refresh script has passwordless access (not all commands)

---

### Scenario 10: Different User Names

**Setup:**
- Create test user with non-standard name

**Test Steps:**
```bash
# Create test user
sudo useradd -m -s /bin/bash testuser123
sudo su - testuser123

# Copy scripts and run
cd /tmp
sudo ./pi_setup_auto.sh

# Verify sudoers entry
sudo cat /etc/sudoers.d/usb-gadget-refresh
```

**Expected Results:**
- ✅ Detects current username correctly
- ✅ Creates sudoers entry with correct username
- ✅ Passwordless sudo works for that user

---

## Validation Commands

Use these commands to verify each component after setup:

```bash
# 1. USB Gadget Method Detection
echo "=== USB Gadget Configuration ==="
if [ -d "/sys/kernel/config/usb_gadget" ]; then
    echo "Method: ConfigFS"
    ls /sys/kernel/config/usb_gadget/
elif lsmod | grep -q "g_mass_storage"; then
    echo "Method: g_mass_storage module"
    cat /sys/module/g_mass_storage/parameters/file
else
    echo "ERROR: No USB gadget found"
fi

# 2. Refresh Script Installation
echo -e "\n=== Refresh Script ==="
ls -lh /usr/local/bin/refresh_usb_gadget*.sh

# 3. Sudoers Configuration
echo -e "\n=== Sudoers Entry ==="
sudo cat /etc/sudoers.d/usb-gadget-refresh

# 4. WiFi Power Management
echo -e "\n=== WiFi Power Management ==="
iwconfig wlan0 2>/dev/null | grep "Power Management" || echo "wlan0 not found"

# 5. Test Refresh Script
echo -e "\n=== Testing Refresh Script ==="
sudo /usr/local/bin/refresh_usb_gadget.sh

# 6. Check Logs
echo -e "\n=== Recent Logs ==="
sudo tail -10 /var/log/usb_gadget_refresh.log

# 7. Full Diagnostic
echo -e "\n=== Full Diagnostic ==="
sudo /usr/local/bin/diagnose_usb_gadget.sh
```

---

## Common Issues and Fixes

### Issue: Script says "No USB gadget found"

**Cause:** Modules not loaded or ConfigFS not available

**Fix:**
```bash
# Check if modules exist
lsmod | grep -E "dwc2|libcomposite|g_mass_storage"

# Load manually
sudo modprobe dwc2
sudo modprobe libcomposite

# Check /boot/config.txt
grep "dtoverlay=dwc2" /boot/config.txt

# If missing, add and reboot
echo "dtoverlay=dwc2" | sudo tee -a /boot/config.txt
sudo reboot
```

### Issue: Sudoers validation fails

**Cause:** Syntax error in sudoers file

**Fix:**
```bash
# Check syntax
sudo visudo -c -f /etc/sudoers.d/usb-gadget-refresh

# If invalid, remove and recreate
sudo rm /etc/sudoers.d/usb-gadget-refresh

# Manually create correct entry
echo "pi ALL=(ALL) NOPASSWD: /usr/local/bin/refresh_usb_gadget.sh" | \
    sudo tee /etc/sudoers.d/usb-gadget-refresh
sudo chmod 0440 /etc/sudoers.d/usb-gadget-refresh
```

### Issue: WiFi power management still enabled

**Cause:** NetworkManager connection name wrong or setting not applied

**Fix:**
```bash
# Find actual connection name
nmcli connection show

# Disable power save (replace 'Your-Connection-Name')
sudo nmcli connection modify 'Your-Connection-Name' 802-11-wireless.powersave 2

# Reactivate
sudo nmcli connection down 'Your-Connection-Name'
sudo nmcli connection up 'Your-Connection-Name'

# Verify
iwconfig wlan0 | grep "Power Management"
```

### Issue: Refresh script fails to run

**Cause:** Script permissions or path issues

**Fix:**
```bash
# Check if script exists
ls -la /usr/local/bin/refresh_usb_gadget.sh

# Make executable
sudo chmod +x /usr/local/bin/refresh_usb_gadget.sh

# Test manually
sudo /usr/local/bin/refresh_usb_gadget.sh

# Check logs for errors
sudo tail -50 /var/log/usb_gadget_refresh.log
```

---

## Automated Test Suite

Create this test runner script for automated validation:

```bash
#!/bin/bash
# test_pi_setup.sh - Automated test runner

set -e

PASSED=0
FAILED=0

test_case() {
    local name="$1"
    local command="$2"

    echo -n "Testing: $name... "
    if eval "$command" &>/dev/null; then
        echo "✅ PASS"
        ((PASSED++))
    else
        echo "❌ FAIL"
        ((FAILED++))
    fi
}

echo "=== Pi Setup Automation Test Suite ==="
echo

test_case "USB gadget detected" \
    "[ -d '/sys/kernel/config/usb_gadget' ] || lsmod | grep -q 'g_mass_storage'"

test_case "Refresh script installed" \
    "[ -x '/usr/local/bin/refresh_usb_gadget.sh' ]"

test_case "Diagnostic script installed" \
    "[ -x '/usr/local/bin/diagnose_usb_gadget.sh' ]"

test_case "Sudoers entry valid" \
    "sudo visudo -c -f /etc/sudoers.d/usb-gadget-refresh"

test_case "WiFi interface exists" \
    "iwconfig wlan0 &>/dev/null"

test_case "Refresh script executes" \
    "sudo /usr/local/bin/refresh_usb_gadget.sh"

test_case "Log file created" \
    "[ -f '/var/log/usb_gadget_refresh.log' ]"

echo
echo "=== Test Results ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"

if [ $FAILED -eq 0 ]; then
    echo "✅ All tests passed!"
    exit 0
else
    echo "❌ Some tests failed"
    exit 1
fi
```

Save as `test_pi_setup.sh` and run with: `sudo ./test_pi_setup.sh`

---

## Manual Verification Steps

After running automation, manually verify:

1. **Refresh script works without password**:
   ```bash
   # Should NOT prompt for password
   sudo /usr/local/bin/refresh_usb_gadget.sh
   ```

2. **WiFi power management disabled**:
   ```bash
   # Should show "off"
   iwconfig wlan0 | grep "Power Management"
   ```

3. **USB gadget responds**:
   ```bash
   # ConfigFS: Should show UDC name
   cat /sys/kernel/config/usb_gadget/*/UDC

   # Module: Should show module loaded
   lsmod | grep g_mass_storage
   ```

4. **Printer sees USB device**:
   - Connect Pi to printer via USB
   - Check printer UI for USB storage device
   - Copy test file: `echo "test" > /mnt/usb_share/test.txt`
   - Run refresh: `sudo /usr/local/bin/refresh_usb_gadget.sh`
   - File should appear on printer within 5 seconds

---

## Report Template

When reporting issues, include:

```
**Environment:**
- Pi Model: [Raspberry Pi Zero W / Zero 2W / etc]
- OS: [Raspberry Pi OS Bullseye / Bookworm]
- USB Gadget Method: [ConfigFS / g_mass_storage module / unknown]
- WiFi Manager: [NetworkManager / wpa_supplicant / none]

**Test Scenario:**
[Describe which scenario you tested]

**Steps to Reproduce:**
1.
2.
3.

**Expected Result:**
[What should happen]

**Actual Result:**
[What actually happened]

**Logs:**
```
# Attach these:
sudo cat /var/log/usb_gadget_refresh.log
sudo /usr/local/bin/diagnose_usb_gadget.sh
```

**Script Output:**
[Paste output from pi_setup_auto.sh]
```

---

## Success Criteria

Setup automation is considered successful when:

- ✅ Script detects USB gadget method correctly (ConfigFS or module)
- ✅ Correct refresh script installed to `/usr/local/bin/`
- ✅ Passwordless sudo configured for refresh script only
- ✅ WiFi power management disabled (if NetworkManager available)
- ✅ All components validated successfully
- ✅ Refresh script runs without errors
- ✅ Backup created before any modifications
- ✅ Script is idempotent (can run multiple times safely)
- ✅ Help output displays correctly
- ✅ Dry-run mode makes no changes
- ✅ Clear error messages for common issues

---

**Last Updated:** 2025-11-21
**Script Version:** 1.0.0
