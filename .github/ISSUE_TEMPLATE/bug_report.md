---
name: Bug Report
about: Create a report to help us improve
title: '[BUG] '
labels: bug
assignees: ''
---

## Bug Description
A clear and concise description of what the bug is.

## Steps to Reproduce
1. Go to '...'
2. Run command '....'
3. See error

## Expected Behavior
A clear description of what you expected to happen.

## Actual Behavior
What actually happened instead.

## Environment
- **OS**: [e.g., Ubuntu 22.04, macOS 13, Windows 11 + WSL2]
- **Python Version**: [output of `python3 --version`]
- **Printer Model**: [e.g., Ender 3 V2, Prusa MK3S]
- **Pi Model**: [e.g., Pi Zero W, Pi Zero 2W]
- **Installation Method**: [setup wizard, manual, other]

## Logs
<details>
<summary>Click to expand logs</summary>

```
# Paste relevant logs here
# From ~/.gcode_sync.log or journalctl -u gcode-monitor.service
```
</details>

## Configuration
<details>
<summary>Click to expand config (redact sensitive info)</summary>

```bash
# Contents of config.local (REMOVE IP addresses, hostnames, usernames)
WATCH_DIR="..."
REMOTE_HOST="<redacted>"
# etc.
```
</details>

## Additional Context
Add any other context about the problem here (screenshots, related issues, etc.)

## Checklist
- [ ] I have checked existing issues for duplicates
- [ ] I am using the latest version from `main` branch
- [ ] I have included all requested information above
- [ ] I have redacted sensitive information (IPs, passwords, keys)
