# Security Policy

## Supported Versions

We release security updates for the following versions:

| Version | Supported          |
| ------- | ------------------ |
| main    | :white_check_mark: |
| < 1.0   | :x:                |

**Note**: As this project is in active development, we recommend always using the latest `main` branch for the most recent security fixes.

## Security Architecture

This project implements defense-in-depth security with 8 layers of protection:

1. **Input Validation** - Path bounds checking, symlink detection, file type validation
2. **TOCTOU Mitigation** - Re-validation before file operations
3. **Command Injection Prevention** - Parameterized commands, no shell execution of user input
4. **Network Security** - systemd IP restrictions (local subnet only)
5. **Filesystem Protection** - Read-only system mounts, minimal write access
6. **Syscall Filtering** - systemd syscall allowlists/blocklists
7. **Resource Limits** - Memory, CPU, and process caps
8. **Capability Dropping** - Zero Linux capabilities

For technical details, see [ARCHITECTURE.md](docs/ARCHITECTURE.md#security-architecture).

## Reporting a Vulnerability

We take security seriously. If you discover a vulnerability, please report it responsibly.

### How to Report

**DO NOT open a public GitHub issue for security vulnerabilities.**

Instead, report security issues privately using one of these methods:

1. **GitHub Security Advisories (Preferred)**:
   - Navigate to the [Security tab](https://github.com/mlugo-apx/pi-gcode-server/security)
   - Click "Report a vulnerability"
   - Fill out the security advisory form

2. **Private Issue**:
   - Email details to the maintainer via GitHub
   - Include "SECURITY" in the subject line

### What to Include

Please provide:

- **Description** of the vulnerability
- **Steps to reproduce** the issue
- **Impact assessment** - what can an attacker do?
- **Affected versions** (if known)
- **Suggested fix** (if you have one)
- **Your contact information** for follow-up

### What to Expect

**Response Timeline**:
- **Initial response**: Within 48 hours
- **Vulnerability assessment**: Within 7 days
- **Fix timeline**: Depends on severity
  - **Critical**: Patch within 7 days
  - **High**: Patch within 14 days
  - **Medium**: Patch within 30 days
  - **Low**: Next regular release

**Process**:
1. We'll acknowledge receipt of your report
2. We'll investigate and assess severity
3. We'll develop and test a fix
4. We'll release the fix and credit you (unless you prefer anonymity)
5. We'll publish a security advisory (if applicable)

### Disclosure Policy

- We ask that you **do not publicly disclose** the vulnerability until we've released a fix
- We'll coordinate disclosure timing with you
- We credit security researchers in release notes and advisories (unless you prefer anonymity)

## Security Best Practices for Users

### Installation Security

1. **Verify Installation Source**:
   ```bash
   # Clone from official repository only
   git clone https://github.com/mlugo-apx/pi-gcode-server.git
   ```

2. **Verify SSH Keys**:
   - Use SSH keys (not passwords) for Pi authentication
   - Protect private keys with passphrases
   - Use `ssh-keygen -t ed25519` for new keys

3. **Secure Configuration**:
   ```bash
   # config.local should be readable only by you
   chmod 600 config.local
   ```

4. **Verify Script Integrity** (on Pi):
   ```bash
   # After installing refresh script, create checksum
   sha256sum /usr/local/bin/refresh_usb_gadget.sh > ~/refresh_usb_gadget.sha256

   # Periodically verify
   sha256sum -c ~/refresh_usb_gadget.sha256
   ```

### Runtime Security

1. **Network Isolation**:
   - The systemd service restricts connections to your local subnet
   - Default: `192.168.1.0/24` (edit `gcode-monitor.service` if different)
   - Never expose the Pi directly to the internet

2. **Filesystem Protection**:
   - Service runs with minimal filesystem access
   - Only watched directory and log file are writable
   - System directories are read-only

3. **Monitor Logs**:
   ```bash
   # Check for suspicious activity
   journalctl -u gcode-monitor.service | grep -i error
   tail -f ~/.gcode_sync.log
   ```

4. **Keep Updated**:
   ```bash
   # Pull latest security fixes
   git pull origin main

   # Restart service
   sudo systemctl restart gcode-monitor.service
   ```

### Configuration Security

**DO**:
- ✅ Use SSH keys (not passwords)
- ✅ Keep `config.local` mode 600 (owner read/write only)
- ✅ Use non-root users on both desktop and Pi
- ✅ Limit sudoers entry to specific script only
- ✅ Keep software updated

**DON'T**:
- ❌ Commit `config.local` to git (it's gitignored)
- ❌ Use world-writable permissions (`chmod 777`)
- ❌ Disable SSH `StrictHostKeyChecking`
- ❌ Run monitor as root
- ❌ Expose Pi's SSH port to internet

## Known Security Considerations

### By Design

1. **SSH Required**: This project requires SSH access to the Pi. Secure your SSH configuration.

2. **Passwordless Sudo**: The Pi user needs passwordless sudo for the USB refresh script. This is scoped to a single script, but verify script integrity regularly.

3. **Local Network Only**: Designed for trusted local networks. Do not expose to untrusted networks.

### Attack Surface

**Minimal by Design**:
- No web server or HTTP endpoints
- No deserialization of untrusted data
- No database
- No external API calls
- Single dependency: `watchdog` (file system monitoring library)

**Potential Risks**:
- **Compromised SSH keys**: Protect your private keys
- **Malicious config.local**: Validate after editing
- **Network sniffing**: Use encrypted WiFi (WPA2/WPA3)

## Security Testing

This project includes security-focused tests:

```bash
# Run security test suite
python3 -m pytest tests/security/

# Tests include:
# - Command injection prevention
# - Path traversal attacks
# - Symlink attacks
# - TOCTOU race conditions
# - Input validation
```

## Security Audit History

| Date       | Type          | Summary                                    |
|------------|---------------|--------------------------------------------|
| 2025-11-20 | Self-audit    | OWASP Top 10 compliance, 8-layer defense   |

## Security Tools

Recommended tools for users and contributors:

- **bandit**: Python security linter
  ```bash
  pip install bandit
  bandit -r monitor_and_sync.py
  ```

- **shellcheck**: Bash script linter
  ```bash
  shellcheck monitor_and_sync.sh
  ```

- **systemd-analyze security**: Analyze service hardening
  ```bash
  systemd-analyze security gcode-monitor.service
  ```

## References

- [OWASP Top 10](https://owasp.org/Top10/)
- [systemd Security Hardening](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#Security)
- [SSH Best Practices](https://www.ssh.com/academy/ssh/keygen#creating-an-ssh-key-pair-for-user-authentication)

## Contact

For non-security issues, please use [GitHub Issues](https://github.com/mlugo-apx/pi-gcode-server/issues).

For security concerns, please follow the [Reporting a Vulnerability](#reporting-a-vulnerability) process above.
