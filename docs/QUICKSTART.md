# Quick Start Guide

## Automated Setup (Recommended)

```bash
cd /home/milugo/Claude_Code/Send_To_Printer
./setup_wizard.sh
```

The wizard will guide you through:
1. Choosing monitor type (Bash or Python - Python recommended)
2. Testing SSH connection
3. Running diagnostic
4. Installing refresh script on Pi
5. Configuring permissions
6. Testing the system
7. (Optional) Installing as systemd service

**Note**: After setup, the system includes enterprise-grade security hardening with:
- Command injection prevention
- Path traversal protection
- TOCTOU race condition mitigation
- Systemd sandboxing with network/filesystem isolation
- File size validation and resource limits

## Manual Quick Start

### 1. Diagnose Your Pi Setup
```bash
ssh -p 9702 milugo@localhost 'bash -s' < pi_scripts/diagnose_usb_gadget.sh > diagnostic.txt
cat diagnostic.txt
```

### 2. Install Refresh Script on Pi
```bash
scp -P 9702 pi_scripts/refresh_usb_gadget.sh milugo@localhost:/tmp/
ssh -p 9702 milugo@localhost
sudo mv /tmp/refresh_usb_gadget.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/refresh_usb_gadget.sh

# Add to sudoers
echo "milugo ALL=(ALL) NOPASSWD: /usr/local/bin/refresh_usb_gadget.sh" | sudo tee /etc/sudoers.d/usb_gadget_refresh
sudo chmod 0440 /etc/sudoers.d/usb_gadget_refresh
exit
```

### 3. Enable Auto-Refresh in Monitor Script

Edit `monitor_and_sync.sh` or `monitor_and_sync.py` and uncomment:
```bash
# In monitor_and_sync.sh (line ~26):
ssh -p "$REMOTE_PORT" "${REMOTE_USER}@${REMOTE_HOST}" "sudo /usr/local/bin/refresh_usb_gadget.sh"

# In monitor_and_sync.py (line ~65):
self.refresh_usb_gadget()
```

### 4. Test It
```bash
# Start monitor
./monitor_and_sync.py

# In another terminal, create test file
echo "test" > ~/Desktop/test.gcode

# Watch the logs
tail -f ~/.gcode_sync.log
```

### 5. Install as Service (Optional)
```bash
sudo cp gcode-monitor.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable gcode-monitor.service
sudo systemctl start gcode-monitor.service
```

### 6. Run Tests (Recommended)
```bash
# Run comprehensive test suite
./run_tests.sh

# This validates:
# - Unit tests (18 tests): Validation logic, retry behavior
# - Security tests (20 tests): OWASP Top 10, injection, traversal
# - Integration tests (24 tests): End-to-end workflows
```

### 7. Deploy Updates
```bash
# After making changes, deploy with:
./deploy.sh

# This automatically:
# - Reloads systemd configuration
# - Restarts service with new security settings
# - Verifies service is running correctly
```

## Quick Commands

### Check Status
```bash
# Local monitor status
sudo systemctl status gcode-monitor.service

# View logs
tail -f ~/.gcode_sync.log
journalctl -u gcode-monitor.service -f
```

### Manual Operations
```bash
# Manually sync a file
rsync -avz -e "ssh -p 9702" ~/Desktop/myprint.gcode milugo@localhost:/mnt/usb_share/

# Manually refresh USB gadget
ssh -p 9702 milugo@localhost "sudo /usr/local/bin/refresh_usb_gadget.sh"

# Check Pi logs
ssh -p 9702 milugo@localhost "tail /var/log/usb_gadget_refresh.log"
```

### Troubleshooting
```bash
# Re-run diagnostic
ssh -p 9702 milugo@localhost 'bash -s' < pi_scripts/diagnose_usb_gadget.sh

# Stop service
sudo systemctl stop gcode-monitor.service

# Check for errors
journalctl -u gcode-monitor.service -n 50
```

## Files Location

- **Local monitor**: `/home/milugo/Claude_Code/Send_To_Printer/`
- **Pi refresh script**: `/usr/local/bin/refresh_usb_gadget.sh`
- **Local logs**: `~/.gcode_sync.log`
- **Pi logs**: `/var/log/usb_gadget_refresh.log`

## Connection Settings

Current setup uses SSH port forwarding:
- **Host**: localhost
- **Port**: 9702
- **User**: milugo
- **Destination**: /mnt/usb_share

To change to direct connection (192.168.1.6), edit the REMOTE_HOST and REMOTE_PORT variables in the monitor scripts.

## Security Features

The system includes comprehensive security hardening:

### Input Validation
- **Path traversal prevention**: Files validated within home directory bounds
- **Symlink attack detection**: Symlinks rejected before processing
- **Extension validation**: Only `.gcode` files processed (case-sensitive)
- **File size limits**: 1 byte minimum, 1 GB maximum

### Attack Prevention
- **Command injection**: All shell variables properly quoted
- **TOCTOU mitigation**: Re-validation immediately before rsync
- **DoS protection**: File size limits + dynamic timeouts

### Systemd Sandboxing
- **Network isolation**: Restricted to 192.168.1.0/24 subnet only
- **Filesystem protection**: Read-only system directories, isolated home
- **Syscall filtering**: Allowlist of safe system calls only
- **Resource limits**: Memory (500M), CPU (50%), Tasks (20)

### Resilience
- **Retry logic**: Exponential backoff (2s, 4s, 8s) for transient failures
- **Supply chain security**: SHA256 hashes verify dependency integrity

For complete security documentation, see the [Security Architecture](../README.md#-security-architecture) section in README.md.
