# Troubleshooting Guide

Common issues and solutions for the pi-gcode-server file monitoring and sync system.

---

## Table of Contents

- [Service Issues](#service-issues)
- [Configuration Errors](#configuration-errors)
- [File Transfer Problems](#file-transfer-problems)
- [Network Connectivity](#network-connectivity)
- [USB Gadget Issues](#usb-gadget-issues)
- [Performance Problems](#performance-problems)
- [Security & Validation Errors](#security--validation-errors)
- [Dependency Issues](#dependency-issues)
- [Diagnostic Tools](#diagnostic-tools)

---

## Service Issues

### Service Not Starting

**Symptoms**:
```bash
sudo systemctl status gcode-monitor.service
# Shows: failed (code=exited, status=1)
```

**Solutions**:

1. **Check service logs**:
   ```bash
   journalctl -u gcode-monitor.service -n 50 --no-pager
   ```

2. **Verify Python script syntax**:
   ```bash
   python3 monitor_and_sync.py
   # Should show configuration errors, not syntax errors
   ```

3. **Check configuration file exists**:
   ```bash
   ls -l config.local
   # If missing: cp config.example config.local && nano config.local
   ```

4. **Verify file permissions**:
   ```bash
   chmod +x monitor_and_sync.py
   chmod 644 config.local
   ```

5. **Check systemd service file path**:
   ```bash
   sudo systemctl cat gcode-monitor.service
   # Verify ExecStart path matches your installation
   ```

Reference: `gcode-monitor.service:12`, `monitor_and_sync.py:518-566`

---

### Service Crashes Repeatedly

**Symptoms**:
```bash
sudo systemctl status gcode-monitor.service
# Shows: activating (auto-restart)
```

**Solutions**:

1. **Check restart limit**:
   ```bash
   # Service stops restarting after 5 failures in 10 minutes
   sudo systemctl reset-failed gcode-monitor.service
   sudo systemctl start gcode-monitor.service
   ```

2. **View crash logs**:
   ```bash
   journalctl -u gcode-monitor.service --since "10 minutes ago"
   ```

3. **Common crash causes**:
   - Invalid configuration (fix `config.local`)
   - Missing watchdog module (auto-installs, check logs)
   - Network unreachable (verify Pi is online)
   - Permission errors (check file ownership)

Reference: `gcode-monitor.service:5-6,15-16`

---

### High Memory/CPU Usage

**Symptoms**: Service consuming >500MB RAM or >50% CPU continuously

**Solutions**:

1. **Check resource limits**:
   ```bash
   systemctl show gcode-monitor.service | grep -E 'Memory|CPU|Tasks'
   ```

2. **View current usage**:
   ```bash
   ps aux | grep monitor_and_sync.py
   ```

3. **Restart service**:
   ```bash
   sudo systemctl restart gcode-monitor.service
   ```

4. **Adjust systemd limits** (if needed):
   ```bash
   sudo nano /etc/systemd/system/gcode-monitor.service

   # Current limits:
   # MemoryMax=500M
   # CPUQuota=50%
   # TasksMax=20
   ```

Reference: `gcode-monitor.service:19-21`

---

## Configuration Errors

### Configuration File Not Found

**Error Message**:
```
ERROR: Configuration file not found: config.local
```

**Solution**:
```bash
cp config.example config.local
nano config.local

# Set these required variables:
WATCH_DIR="$HOME/Desktop"
REMOTE_USER="your_pi_username"
REMOTE_HOST="192.168.1.6"  # Your Pi's IP
REMOTE_PORT="22"
REMOTE_PATH="/mnt/usb_share"
LOG_FILE="$HOME/.gcode_sync.log"
```

Reference: `monitor_and_sync.py:121`

---

### Invalid Port Number

**Error Message**:
```
ERROR: REMOTE_PORT must be numeric (got: abc)
ERROR: REMOTE_PORT must be between 1 and 65535 (got: 99999)
```

**Solution**:
```bash
nano config.local

# Set valid port (default SSH port):
REMOTE_PORT="22"
```

Reference: `monitor_and_sync.py:158-165`

---

### Invalid Characters in Configuration

**Error Message**:
```
ERROR: REMOTE_HOST contains invalid characters
ERROR: REMOTE_USER contains invalid characters
ERROR: REMOTE_PATH contains invalid characters
```

**Cause**: Configuration values contain shell metacharacters: `$`, `` ` ``, `;`, `|`, `&`, `<`, `>`, `(`, `)`, `{`, `}`

**Solution**:
```bash
nano config.local

# Remove special characters:
REMOTE_HOST="192.168.1.6"     # ✓ Valid
REMOTE_HOST="192.168.1.6;ls"  # ✗ Invalid (semicolon)

REMOTE_USER="pi"              # ✓ Valid
REMOTE_USER="pi$(whoami)"     # ✗ Invalid (command substitution)

REMOTE_PATH="/mnt/usb_share"  # ✓ Valid
REMOTE_PATH="/mnt/usb&share"  # ✗ Invalid (ampersand)
```

Reference: `monitor_and_sync.py:168-180`, validation regex: `[$`;\|&<>(){}]`

---

### Path Traversal in Configuration

**Error Message**:
```
ERROR: WATCH_DIR contains path traversal sequence (..)
ERROR: LOG_FILE contains path traversal sequence (..)
```

**Cause**: Configuration paths contain `..` (parent directory references)

**Solution**:
```bash
nano config.local

# Use absolute paths without '..'
WATCH_DIR="$HOME/Desktop"           # ✓ Valid
WATCH_DIR="$HOME/../other/Desktop"  # ✗ Invalid (contains ..)

LOG_FILE="$HOME/.gcode_sync.log"    # ✓ Valid
LOG_FILE="$HOME/../../tmp/log"      # ✗ Invalid (contains ..)
```

Reference: `monitor_and_sync.py:236-241`

---

### Invalid Watch Directory

**Error Message**:
```
ERROR: WATCH_DIR must be an absolute path
ERROR: WATCH_DIR must be within user home directory
```

**Solution**:
```bash
nano config.local

# Use absolute path within home directory:
WATCH_DIR="$HOME/Desktop"            # ✓ Valid
WATCH_DIR="/home/milugo/Desktop"     # ✓ Valid
WATCH_DIR="Desktop"                  # ✗ Invalid (relative path)
WATCH_DIR="/tmp/gcode"               # ✗ Invalid (not in home)
```

Reference: `monitor_and_sync.py:195-204`

---

### Forbidden Log File Location

**Error Message**:
```
ERROR: LOG_FILE cannot be in system directory
```

**Cause**: Log file path is in a protected system directory

**Solution**:
```bash
nano config.local

# Use log file in home directory:
LOG_FILE="$HOME/.gcode_sync.log"     # ✓ Valid
LOG_FILE="/var/log/gcode.log"        # ✗ Invalid (system directory)
LOG_FILE="/etc/gcode.log"            # ✗ Invalid (system directory)
```

**Forbidden directories**: `/etc`, `/var`, `/usr`, `/bin`, `/sbin`, `/boot`

Reference: `monitor_and_sync.py:219-231`

---

## File Transfer Problems

### Timeout Syncing File

**Error Message**:
```
ERROR: Timeout syncing filename.gcode - transfer took longer than X minutes
```

**Cause**: Network too slow or file too large for configured timeout

**Solutions**:

1. **Check network speed**:
   ```bash
   # On desktop:
   iperf3 -c your_pi_ip

   # Should see 5+ MB/s for WiFi, 50+ MB/s for Ethernet
   ```

2. **Verify WiFi power management is OFF** (on Pi):
   ```bash
   iwconfig wlan0 | grep "Power Management"
   # Should show: off
   ```

3. **Check file size vs timeout**:
   - Timeout formula: `max(120 seconds, file_size_MB / 100 * 60)`
   - 100 MB → 120s (2 min)
   - 500 MB → 300s (5 min)
   - 1 GB → 600s (10 min)

4. **Reduce file size** (if using test files):
   ```bash
   # Check file size
   ls -lh ~/Desktop/filename.gcode
   ```

5. **Check for packet loss**:
   ```bash
   ping -c 100 your_pi_ip | grep loss
   # Should be <1% packet loss
   ```

Reference: `monitor_and_sync.py:432`, `368-372` (timeout calculation)

---

### Failed to Sync File

**Error Message**:
```
ERROR: Failed to sync filename.gcode: [error details]
STDERR: [rsync error output]
```

**Common Causes**:

#### 1. SSH Connection Failed
```
STDERR: ssh: connect to host 192.168.1.6 port 22: Connection refused
```
**Solution**: Verify Pi is online and SSH is enabled
```bash
ping your_pi_ip
ssh your_pi_username@your_pi_ip
```

#### 2. Authentication Failed
```
STDERR: Permission denied (publickey,password)
```
**Solution**: Setup passwordless SSH
```bash
ssh-copy-id your_pi_username@your_pi_ip
ssh your_pi_username@your_pi_ip  # Should not ask for password
```

#### 3. Remote Directory Not Found
```
STDERR: rsync: mkdir "/mnt/usb_share" failed: No such file or directory
```
**Solution**: Create directory on Pi
```bash
ssh your_pi "sudo mkdir -p /mnt/usb_share"
ssh your_pi "sudo chmod 777 /mnt/usb_share"
```

#### 4. Disk Full on Pi
```
STDERR: rsync: write failed on "filename.gcode": No space left on device
```
**Solution**: Check Pi disk space
```bash
ssh your_pi "df -h /mnt/usb_share"
ssh your_pi "du -sh /mnt/usb_share/*"
# Delete old files if needed
```

Reference: `monitor_and_sync.py:431-437`

---

### Retry Logic Exhausted

**Log Messages**:
```
WARN: Attempt 1/3 failed, retrying in 2 seconds...
WARN: Attempt 2/3 failed, retrying in 4 seconds...
WARN: Attempt 3/3 failed, retrying in 8 seconds...
ERROR: Failed to sync after 3 attempts
```

**Cause**: Persistent network or system issue preventing transfer

**Solutions**:

1. **Check Pi is responsive**:
   ```bash
   ssh your_pi "uptime"
   ```

2. **Verify network stability**:
   ```bash
   ping -c 100 your_pi_ip | grep -E 'loss|time'
   ```

3. **Check Pi system load**:
   ```bash
   ssh your_pi "top -bn1 | head -20"
   ```

4. **Review full error in log**:
   ```bash
   tail -n 50 ~/.gcode_sync.log
   ```

Reference: `monitor_and_sync.py:75-114`, retry configuration: max 3 attempts, 2s/4s/8s delays

---

## Network Connectivity

### Cannot Reach Pi

**Symptoms**: All transfers fail with "Connection refused" or "No route to host"

**Solutions**:

1. **Verify Pi is on network**:
   ```bash
   ping your_pi_ip
   # Should get responses
   ```

2. **Check Pi's IP address** (may have changed):
   ```bash
   # On Pi:
   ip addr show wlan0 | grep inet

   # Or from router's DHCP client list
   ```

3. **Update config.local** if IP changed:
   ```bash
   nano config.local
   REMOTE_HOST="192.168.1.NEW_IP"
   ```

4. **Check SSH service on Pi**:
   ```bash
   ssh your_pi "systemctl status sshd"
   ```

5. **Verify firewall** (if enabled):
   ```bash
   # On Pi:
   sudo ufw status
   # Should allow port 22 (SSH)
   ```

Reference: `monitor_and_sync.py:381-384` (SSH options)

---

### Slow Transfer Speed

**Symptoms**: Transfers slower than 2 MB/s

**Root Cause Checklist**:

1. **WiFi Power Management** (95% of issues):
   ```bash
   # On Pi:
   iwconfig wlan0 | grep "Power Management"
   # Must show: off

   # If not off:
   sudo nmcli connection modify preconfigured 802-11-wireless.powersave 2
   sudo nmcli connection down preconfigured && sudo nmcli connection up preconfigured
   ```

2. **WiFi Signal Strength**:
   ```bash
   # On Pi:
   iwconfig wlan0 | grep -E 'Signal|Quality'
   # Signal should be > -70 dBm
   ```

3. **Network Congestion**:
   ```bash
   # Check bandwidth
   iperf3 -s  # On Pi
   iperf3 -c your_pi_ip  # On desktop
   # Should see 20+ Mbps for 2.4GHz, 50+ Mbps for 5GHz
   ```

4. **Pi CPU Load**:
   ```bash
   # On Pi:
   top -bn1 | head -5
   # CPU should be <80% during transfers
   ```

Reference: `docs/NETWORK_OPTIMIZATION_RESULTS.md`, WiFi power mgmt impact: 21x speedup

---

### SSH Connection Drops During Transfer

**Symptoms**: Transfers fail mid-way with "Connection reset by peer"

**Solutions**:

1. **Enable SSH keepalive** (desktop `~/.ssh/config`):
   ```ssh-config
   Host your_pi_ip
       ServerAliveInterval 5
       ServerAliveCountMax 3
   ```

2. **Check WiFi stability on Pi**:
   ```bash
   # On Pi, run for 5 minutes:
   ping -i 0.2 8.8.8.8 | tee ping_test.log
   # Review for packet loss
   ```

3. **Disable WiFi power management** (if not already):
   ```bash
   # On Pi:
   sudo nmcli connection modify preconfigured 802-11-wireless.powersave 2
   ```

Reference: `monitor_and_sync.py:381` (SSH options), `ServerAliveInterval=5`

---

## USB Gadget Issues

### USB Gadget Refresh Timeout

**Error Message**:
```
ERROR: USB gadget refresh timed out after 30 seconds
WARN: File was synced but printer may not see it until Pi reboot
```

**Cause**: Pi couldn't complete USB refresh within 30-second timeout

**Solutions**:

1. **Check if file is on Pi**:
   ```bash
   ssh your_pi "ls -lh /mnt/usb_share/"
   ```

2. **Manually refresh USB gadget**:
   ```bash
   ssh your_pi "sudo /usr/local/bin/refresh_usb_gadget.sh"
   ```

3. **Check refresh script logs**:
   ```bash
   ssh your_pi "sudo tail -n 50 /var/log/usb_gadget_refresh.log"
   ```

4. **Verify USB gadget is configured**:
   ```bash
   ssh your_pi "sudo /usr/local/bin/diagnose_usb_gadget.sh"
   ```

5. **Reboot Pi** (if manual refresh fails):
   ```bash
   ssh your_pi "sudo reboot"
   ```

Reference: `monitor_and_sync.py:499-515`, timeout: 30 seconds

---

### USB Gadget Refresh Failed

**Error Message**:
```
ERROR: USB gadget refresh failed with exit code 1
ERROR: Error details: [script error output]
```

**Common Causes**:

#### 1. No USB Gadget Configuration Found
```
ERROR: No recognized USB gadget configuration found
```
**Solution**: Run diagnostic and setup USB gadget
```bash
ssh your_pi "sudo /usr/local/bin/diagnose_usb_gadget.sh"
# Follow PI_SETUP.md to configure USB gadget
```

#### 2. Gadget Not Bound to UDC
```
WARNING: Gadget not bound to UDC, skipping unbind/rebind
```
**Solution**: Verify USB gadget service
```bash
# ConfigFS method:
ssh your_pi "sudo systemctl status usb-gadget.service"
ssh your_pi "cat /sys/kernel/config/usb_gadget/g1/UDC"

# Module method:
ssh your_pi "lsmod | grep g_mass_storage"
```

#### 3. Module Cannot Reload
```
ERROR: Cannot determine module parameters
```
**Solution**: Manually reload module
```bash
ssh your_pi "sudo modprobe -r g_mass_storage"
ssh your_pi "sudo modprobe g_mass_storage file=/piusb.bin removable=1 stall=0"
```

Reference: `pi_scripts/refresh_usb_gadget.sh:67-71`, diagnostic: `diagnose_usb_gadget.sh`

---

### Printer Doesn't See New Files

**Symptoms**: File transfers successfully, no refresh errors, but printer UI doesn't show file

**Solutions**:

1. **Check file is on Pi**:
   ```bash
   ssh your_pi "ls -lh /mnt/usb_share/*.gcode"
   ```

2. **Manually trigger USB refresh**:
   ```bash
   ssh your_pi "sudo /usr/local/bin/refresh_usb_gadget.sh"
   # Wait 5 seconds, check printer UI
   ```

3. **Reboot printer** (cold boot):
   - Power off printer completely
   - Wait 10 seconds
   - Power on
   - Check USB device in printer menu

4. **Verify USB cable**:
   - Use data-capable cable (not power-only)
   - Try different cable
   - Ensure micro-USB end is in Pi's data port (not power port)

5. **Check printer USB mode**:
   - Some printers have USB host/device mode setting
   - Ensure printer is in USB host mode

6. **Test with manual file**:
   ```bash
   ssh your_pi "sudo sh -c 'echo test > /mnt/usb_share/test.txt'"
   ssh your_pi "sudo /usr/local/bin/refresh_usb_gadget.sh"
   # Check if printer sees test.txt
   ```

Reference: `monitor_and_sync.py:466-515` (refresh logic)

---

## Performance Problems

### Large File Warning

**Log Message**:
```
WARN: Large file detected: filename.gcode (550 MB)
WARN: This may take several minutes to sync
```

**Explanation**: File is between 500 MB - 1 GB (warning threshold)

**Expected Behavior**:
- File will transfer successfully
- Timeout automatically extended (dynamic scaling)
- 500 MB file: ~90 seconds at 5.5 MB/s

**No action needed unless**:
- Transfer times out (see "Timeout Syncing File")
- You want to reduce file size (slice with fewer polygons)

Reference: `monitor_and_sync.py:348-350`, warning threshold: 500 MB

---

### File Too Large

**Error Message**:
```
ERROR: File too large: filename.gcode (1200 MB)
ERROR: Maximum allowed size: 1024 MB
```

**Cause**: File exceeds 1 GB hard limit

**Solutions**:

1. **Reduce file size** (preferred):
   - Re-slice with lower resolution
   - Reduce infill density
   - Simplify model geometry

2. **Increase limit** (if Pi has space):
   ```bash
   nano monitor_and_sync.py

   # Line 31: Change from 1 GB to 2 GB
   MAX_FILE_SIZE = 2 * 1024 * 1024 * 1024  # 2 GB
   ```

   Then restart service:
   ```bash
   sudo systemctl restart gcode-monitor.service
   ```

3. **Check Pi storage capacity**:
   ```bash
   ssh your_pi "df -h /mnt/usb_share"
   # Ensure Pi image file is large enough
   ```

Reference: `monitor_and_sync.py:343-346`, hard limit: 1 GB (1024 MB)

---

## Security & Validation Errors

### File Outside Watch Directory

**Error Message**:
```
ERROR: Security: File outside watch directory: /path/to/file.gcode
```

**Cause**: File path is not within configured `WATCH_DIR`

**Why This Happens**:
- Symlink from watch directory to other location
- File event triggered for wrong directory
- Bug in file system event handler

**Solution**:
```bash
# Verify WATCH_DIR in config
grep WATCH_DIR config.local

# Only files in this directory will sync
# Move gcode files to watch directory:
mv /some/other/path/file.gcode ~/Desktop/
```

Reference: `monitor_and_sync.py:309`, path bounds check

---

### Refusing to Sync Symlink

**Error Message**:
```
ERROR: Security: Refusing to sync symlink: /path/to/link.gcode
```

**Cause**: File is a symbolic link, not a regular file

**Why This Is Blocked**: Symlink attacks can trick the system into reading files outside watch directory

**Solution**:
```bash
# Copy actual file instead of creating symlink:
cp /path/to/original.gcode ~/Desktop/  # ✓ Valid
ln -s /path/to/original.gcode ~/Desktop/link.gcode  # ✗ Invalid (symlink)

# Or copy target of existing symlink:
TARGET=$(readlink ~/Desktop/link.gcode)
cp "$TARGET" ~/Desktop/file.gcode
```

Reference: `monitor_and_sync.py:320-321`, symlink detection

---

### File Changed Type After Validation

**Error Messages**:
```
ERROR: Security: File became symlink after validation: filename.gcode
ERROR: Security: File changed type after validation: filename.gcode
ERROR: Security: File extension changed after validation: filename.gcode
```

**Cause**: File was modified between validation and transfer (TOCTOU race condition)

**Why This Happens**:
- File replaced with symlink during sync
- File moved/renamed during sync
- Extremely rare (window <20 lines of code)

**Solutions**:

1. **Retry** - File will be re-validated on next attempt

2. **Check if file is being actively modified**:
   ```bash
   lsof ~/Desktop/filename.gcode
   # Should be empty (no processes using file)
   ```

3. **Wait for file write to complete** before moving to Desktop:
   ```bash
   # Bad: Move while slicer is writing
   mv file.gcode ~/Desktop/ &  # ✗ Race condition

   # Good: Wait for write to complete
   mv file.gcode ~/Desktop/    # ✓ Atomic move after write complete
   ```

Reference: `monitor_and_sync.py:354-366`, TOCTOU mitigation

---

### Empty File Skipped

**Log Message**:
```
WARN: Skipping empty file: filename.gcode (0 bytes)
```

**Cause**: File is 0 bytes (empty)

**Why This Is Blocked**: Prevents DoS attacks with thousands of empty files

**Solutions**:

1. **Check if file write completed**:
   ```bash
   ls -lh ~/Desktop/filename.gcode
   # If 0 bytes, file may still be writing
   ```

2. **Wait for slicer to finish**:
   - Some slicers create empty file first, then write content
   - Wait a few seconds, file will auto-sync when write completes

3. **Verify slicer output**:
   - Check slicer logs for errors
   - Re-slice model

Reference: `monitor_and_sync.py:339-341`, minimum file size: 1 byte

---

## Dependency Issues

### Watchdog Module Not Found

**Log Message**:
```
WARN: watchdog module not found. Installing...
Installing watchdog module using uv...
```

**Explanation**: Python `watchdog` library is missing, auto-installing

**Expected Behavior**:
- System auto-detects `uv` or `pip`
- Installs `watchdog==3.0.0` with SHA256 hash verification
- Continues monitoring after successful install

**If Auto-Install Fails**:
```bash
# Manual install with uv (preferred):
uv pip install watchdog==3.0.0

# Or with pip:
pip3 install --user watchdog==3.0.0

# Verify installation:
python3 -c "import watchdog; print(watchdog.__version__)"
```

Reference: `monitor_and_sync.py:524-540`, auto-install logic

---

### rsync Not Found

**Error Message**:
```
ERROR: Required command not found: rsync
```

**Solution**:
```bash
# Ubuntu/Debian:
sudo apt install rsync

# Fedora/RHEL:
sudo dnf install rsync

# macOS:
brew install rsync

# Verify:
which rsync
rsync --version
```

---

### SSH Not Found

**Error Message**:
```
ERROR: Required command not found: ssh
```

**Solution**:
```bash
# Ubuntu/Debian:
sudo apt install openssh-client

# Fedora/RHEL:
sudo dnf install openssh-clients

# macOS: (pre-installed)
# Verify:
which ssh
ssh -V
```

---

## Diagnostic Tools

### Health Check Script

Verify service is running and logs are fresh:

```bash
./check_gcode_monitor.sh
```

**What It Checks**:
- Service is active
- Log file updated within 30 minutes
- No errors in systemd journal

**Output**:
```
[2025-11-20 14:30:00] Service gcode-monitor.service is active.
[2025-11-20 14:30:00] Log file updated 5 minutes ago.
[2025-11-20 14:30:00] Last five log entries:
...
[2025-11-20 14:30:00] No errors detected in journal over the last 30 minutes.
[2025-11-20 14:30:00] Health check completed successfully.
```

Reference: `check_gcode_monitor.sh`

---

### USB Gadget Diagnostic

Identify USB gadget configuration on Pi:

```bash
ssh your_pi "sudo /usr/local/bin/diagnose_usb_gadget.sh"
```

**What It Reports**:
- Loaded USB kernel modules
- ConfigFS gadget configuration
- g_mass_storage module details
- Device tree overlays
- Mount points
- Backing file location
- Recent kernel messages

Reference: `pi_scripts/diagnose_usb_gadget.sh:1-80`

---

### Manual Sync Test

Test rsync connectivity without the monitor:

```bash
./test_sync.sh /path/to/test.gcode
```

**What It Tests**:
- Configuration loading
- File validation
- rsync transfer
- USB gadget refresh
- End-to-end workflow

Reference: `test_sync.sh`

---

### View Live Logs

Monitor service activity in real-time:

```bash
# Application log:
tail -f ~/.gcode_sync.log

# Systemd journal:
journalctl -u gcode-monitor.service -f

# Both simultaneously:
tail -f ~/.gcode_sync.log & journalctl -u gcode-monitor.service -f
```

---

### Check Service Status

Get detailed service information:

```bash
# Service status
sudo systemctl status gcode-monitor.service

# Check if enabled at boot
systemctl is-enabled gcode-monitor.service

# Check recent failures
systemctl list-units --failed

# View resource usage
systemctl show gcode-monitor.service | grep -E 'Memory|CPU|Tasks'
```

---

### Network Diagnostics

Test network connectivity and speed:

```bash
# Ping test
ping -c 100 your_pi_ip | grep -E 'loss|rtt'

# Bandwidth test (requires iperf3)
iperf3 -s  # On Pi
iperf3 -c your_pi_ip  # On desktop

# SSH connection test
time ssh your_pi "echo connected"

# File transfer speed test
time scp /tmp/100MB.bin your_pi:/tmp/
```

---

## Getting Help

If you've tried the solutions above and still have issues:

1. **Gather diagnostic information**:
   ```bash
   # Service status
   sudo systemctl status gcode-monitor.service > service_status.txt

   # Recent logs (last 100 lines)
   tail -n 100 ~/.gcode_sync.log > app_log.txt
   journalctl -u gcode-monitor.service -n 100 > journal_log.txt

   # Configuration (remove sensitive info)
   cat config.local > config.txt

   # System info
   uname -a > system_info.txt
   python3 --version >> system_info.txt
   ```

2. **Open a GitHub issue** with:
   - Clear description of the problem
   - Steps to reproduce
   - Error messages from logs
   - System information
   - Diagnostic output

3. **Check existing issues**:
   - [GitHub Issues](https://github.com/mlugo-apx/pi-gcode-server/issues)
   - [GitHub Discussions](https://github.com/mlugo-apx/pi-gcode-server/discussions)

---

## Quick Reference: Common Error Messages

| Error Message | File Reference | Solution Section |
|---------------|----------------|------------------|
| Configuration file not found | `monitor_and_sync.py:121` | [Configuration File Not Found](#configuration-file-not-found) |
| REMOTE_PORT must be numeric | `monitor_and_sync.py:159` | [Invalid Port Number](#invalid-port-number) |
| contains invalid characters | `monitor_and_sync.py:171-179` | [Invalid Characters](#invalid-characters-in-configuration) |
| File outside watch directory | `monitor_and_sync.py:309` | [File Outside Watch Directory](#file-outside-watch-directory) |
| Refusing to sync symlink | `monitor_and_sync.py:320` | [Refusing to Sync Symlink](#refusing-to-sync-symlink) |
| File too large | `monitor_and_sync.py:343` | [File Too Large](#file-too-large) |
| Timeout syncing | `monitor_and_sync.py:432` | [Timeout Syncing File](#timeout-syncing-file) |
| Failed to sync | `monitor_and_sync.py:434` | [Failed to Sync File](#failed-to-sync-file) |
| USB gadget refresh timed out | `monitor_and_sync.py:500` | [USB Gadget Refresh Timeout](#usb-gadget-refresh-timeout) |
| USB gadget refresh failed | `monitor_and_sync.py:505` | [USB Gadget Refresh Failed](#usb-gadget-refresh-failed) |
| No USB gadget configuration | `refresh_usb_gadget.sh:68` | [USB Gadget Refresh Failed](#usb-gadget-refresh-failed) |

---

**Still stuck?** See [PI_SETUP.md](PI_SETUP.md) for initial setup or [ARCHITECTURE.md](ARCHITECTURE.md) for system internals.
