# pi-gcode-server

## Stop Manually Transferring Files to Your 3D Printer

**Save a file → It appears on your printer. That's it.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![CI](https://github.com/mlugo-apx/pi-gcode-server/workflows/CI/badge.svg)](https://github.com/mlugo-apx/pi-gcode-server/actions)
[![Platform](https://img.shields.io/badge/platform-Raspberry%20Pi-red.svg)](https://www.raspberrypi.org/)
[![Python](https://img.shields.io/badge/python-3.8+-blue.svg)](https://www.python.org/)
[![Maintenance](https://img.shields.io/badge/Maintained%3F-yes-green.svg)](https://github.com/mlugo-apx/pi-gcode-server/graphs/commit-activity)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

> **⚠️ Platform Support:**
> - ✅ **Ubuntu 24.04 LTS**: Fully tested by maintainer
> - 🔍 **Other Linux distros**: Should work, testers needed ([report here](https://github.com/mlugo-apx/pi-gcode-server/issues))
> - 🔍 **Windows (WSL2)**: Documented but untested, testers needed
> - 🔍 **macOS**: Documented but untested, testers needed
>
> Example configs exist for multiple platforms ([see examples/](examples/)), but only Ubuntu 24.04 has been validated. Help us expand support by testing and reporting results!

Automatically sync `.gcode` files wirelessly to your 3D printer through a Raspberry Pi configured as a USB mass storage device. No SD card swapping, no manual transfers, no printer reboots.

### The Problem

**Before**: Save file → Unmount SD card → Walk to printer → Insert SD card → Wait for menu refresh → Navigate to file → Print

**After**: Save file → Print *(file appears in 10 seconds)*

### Why This Exists

Tired of the "SD card shuffle"? This project eliminates the most tedious part of 3D printing: getting gcode files onto your printer. Set it up once, forget about it forever.

---

## ✨ Features

- 🔄 **Automatic File Monitoring** - Watches your desktop for new gcode files
- ⚡ **Fast Transfers** - 21x speed improvement over basic setups (optimized networking)
- 🔌 **USB Gadget Mode** - Raspberry Pi acts as a USB mass storage device
- 🔁 **Auto-Refresh** - Printer sees new files instantly without rebooting Pi
- 🚀 **Optimized Performance** - Network tuning achieves 5-10 MB/s for real files
- 📦 **Complete Solution** - Includes both local monitor and Pi server scripts
- 🛠️ **Easy Setup** - Automated installation scripts included

---

## 📋 High-Level Requirements

### Hardware
- **Raspberry Pi Zero W** or **Pi Zero 2W** (recommended for better performance)
  - Other Pi models work but require USB OTG adapter
- **Micro-USB cable** (data-capable, not just power)
- **SD card** (8GB minimum, 16GB+ recommended)
- **3D Printer** with USB mass storage support
- **WiFi network** (2.4GHz minimum, 5GHz if Pi supports it)

### Software - Local Machine (Ubuntu/Linux)
- **Operating System**: Ubuntu 20.04+ or any modern Linux distro
- **Required Packages**:
  - `inotify-tools` (for Bash monitor) OR `python3` + `watchdog` (for Python monitor)
  - `rsync` - Efficient file transfer
  - `openssh-client` - SSH connectivity
  - `systemd` - Service management (usually pre-installed)
- **Network**: SSH access to Raspberry Pi (passwordless key auth recommended)

### Software - Raspberry Pi
- **Operating System**: Raspberry Pi OS (Lite or Desktop)
- **Kernel**: 4.9+ with USB gadget support
- **Required**:
  - USB gadget kernel modules (`dwc2`, `libcomposite` or `g_mass_storage`)
  - 2GB+ FAT32 image file for USB storage
  - SSH server enabled
  - NetworkManager (for WiFi power management optimization)
- **Network**: WiFi configured and connected to same network as local machine

### Network Requirements
- Both devices on same network/subnet
- SSH connectivity between local machine and Pi
- **CRITICAL**: WiFi power management must be disabled (provides 20x speed boost!)

---

## 🚀 Quick Start

The project runs natively on Linux today. Windows and macOS users can follow the
platform-specific guides below to get equivalent functionality.

### Linux (native)
```bash
git clone https://github.com/mlugo-apx/pi-gcode-server.git
cd pi-gcode-server

cp config.example config.local
nano config.local  # Configure WATCH_DIR, REMOTE_* values

./install_and_start.sh          # Installs dependencies, runs a sync test
./deploy.sh                     # Installs/refreshes the systemd service

# Smoke test
cp path/to/file.gcode ~/Desktop/
tail -f ~/.gcode_sync.log
```

> ℹ️  See [Pi Setup Guide](docs/PI_SETUP.md) for configuring the Raspberry Pi
> USB gadget environment. The Linux desktop component is already hardened with
> systemd sandboxing and security validation.
>
> 💡 Install [uv](https://github.com/astral-sh/uv) for faster, reproducible
> Python dependency management (`curl -Ls https://astral.sh/uv/install.sh | sh`).
> The installer will auto-detect and use `uv` when available.

### Windows (via WSL2)
1. Enable WSL2 and install Ubuntu (`wsl --install` on Windows 11).
2. Inside Ubuntu:
   ```bash
   git clone https://github.com/mlugo-apx/pi-gcode-server.git
   cd pi-gcode-server
   cp config.example config.local
   ./install_and_start.sh
   ./deploy.sh
   ```
3. Configure Windows to launch the monitor at login (e.g., PowerShell script
   calling `wsl -d Ubuntu ./deploy.sh`).

> 📄 Detailed instructions and bootstrap ideas live in
> [Cross-Platform Support](docs/CROSS_PLATFORM_SUPPORT.md). The Raspberry Pi
> still performs the USB gadget duties; WSL only runs the desktop monitor.

### macOS (launchd)
1. Install prerequisites via Homebrew:
   ```bash
   brew install python rsync openssh
   ```
2. Clone and configure the project:
   ```bash
   git clone https://github.com/mlugo-apx/pi-gcode-server.git
   cd pi-gcode-server
   cp config.example config.local
   ./install_and_start.sh
   ```
3. Create a `launchd` plist (example template forthcoming in
   `docs/CROSS_PLATFORM_SUPPORT.md`) that runs `monitor_and_sync.py` at login.
4. Tail `~/.gcode_sync.log` to confirm end-to-end syncs.

> 🔒 macOS uses FSEvents under the hood via `watchdog`, so the Python monitor
> works natively. Replace systemd sandboxing with the appropriate `launchd`
> options (as documented in the cross-platform guide).
>
> 💡 `uv` is also supported on macOS. Install it via Homebrew
> (`brew install uv`) or the official installer; the setup script will pick it up
> automatically.

---

Regardless of platform, the Raspberry Pi setup remains the same. After the Pi
is prepared, confirm the desktop monitor reaches the Pi:
```bash
cp test.gcode ~/Desktop/
tail -f ~/.gcode_sync.log
ssh your_user@your_pi_ip "ls -lh /mnt/usb_share/"
```

---

## 📖 Documentation

- **[Quick Start Guide](docs/QUICKSTART.md)** - Get up and running fast
- **[Detailed Pi Setup](docs/PI_SETUP.md)** - Complete Raspberry Pi configuration
- **[Network Optimization](docs/NETWORK_OPTIMIZATION_RESULTS.md)** - Achieve 21x speed improvements!
- **[Troubleshooting](docs/TROUBLESHOOTING.md)** - Common issues and solutions
- **[Architecture](docs/ARCHITECTURE.md)** - How the system works

---

## ⚡ Performance

**Before Optimization**:
- Transfer speed: ~260 KB/s
- 55MB file: ~3 minutes 30 seconds

**After Optimization**:
- Transfer speed: ~5.5 MB/s
- 55MB file: **~10 seconds** ⚡
- **21x faster!**

See [Network Optimization Results](docs/NETWORK_OPTIMIZATION_RESULTS.md) for details on how we achieved this.

---

## 🖨️ Printer Compatibility

**Works with any 3D printer that supports USB mass storage mode**, which includes most modern printers.

### ✅ Confirmed Working (Maintainer Verified)

| Printer Model | Status | Notes | Tested By |
|--------------|--------|-------|-----------|
| **AnyCubic Kobra 2 Max** | ✅ Verified | USB mass storage fully supported, files appear immediately | @mlugo-apx |

### 🤔 Should Work (Community Reports Needed)

These printers support USB mass storage and should work, but haven't been tested by the maintainer yet:

**Creality Series**:
- Ender 3 / Ender 3 V2 / Ender 3 Pro
- CR-10 / CR-10 V2
- CR-6 SE, CR-30, Ender 5 series

**Prusa Series**:
- i3 MK3S / MK3S+ / MK4
- Mini, XL (with USB port)

**AnyCubic Series**:
- Kobra (standard)
- Vyper
- Mega series

**Other Brands**:
- Artillery: Sidewinder, Genius
- Elegoo: Neptune series
- Sovol: SV01, SV02, SV06
- Any printer with USB mass storage support

**📝 Have you tested this?** [Report your printer compatibility →](https://github.com/mlugo-apx/pi-gcode-server/issues/new?template=printer_compatibility.md)

### 📋 Requirements for Compatibility

Your printer **must have**:
- ✅ **USB-A port** (usually on front panel or side)
- ✅ **USB mass storage support** (can read files from USB flash drive)
- ✅ **FAT32 filesystem support** (standard for USB drives)
- ✅ **Menu system** to browse and select files

Your printer **does not need**:
- ❌ Network connectivity (WiFi/Ethernet)
- ❌ Special firmware modifications
- ❌ OctoPrint or other server software
- ❌ Touchscreen (basic LCD is fine)

### 🤔 Untested but Should Work

If your printer can read files from a USB flash drive, this project will work:

- **Creality**: CR-6, CR-30, Ender 5, Ender 5 Pro, Ender 7
- **Prusa**: Mini, XL (with USB port)
- **AnyCubic**: Mega series, Photon Mono (FDM models)
- **Artillery**: Sidewinder, Genius
- **Elegoo**: Neptune series
- **Sovol**: SV01, SV02, SV06
- **Monoprice**: Select Mini, Maker series
- **FlashForge**: Adventurer, Creator series
- **QIDI**: X-Plus, X-Max
- **Any printer with USB mass storage support**

### ❌ Not Compatible

- **Network-only printers** without USB ports
- **Proprietary USB protocols** (rare, mostly industrial printers)
- **Resin printers without USB mass storage** (some only support network)

### 📝 Report Your Printer

Help expand this list! If you've tested this with your printer:
1. [Open an issue](https://github.com/mlugo-apx/pi-gcode-server/issues/new?template=printer_compatibility.md) with your printer model
2. Include: Model name, firmware version (if known), and whether it worked
3. We'll add it to the compatibility matrix above

**Example config files available** in `examples/` directory:
- `config.ender3` - Creality Ender 3 series
- `config.prusa` - Prusa MK3S/MK3S+/MK4
- `config.wsl2` - Windows + WSL2 setup
- `config.macos` - macOS setup

See [examples/README.md](examples/README.md) for usage instructions.

**Raspberry Pi Requirements**:
- Raspberry Pi Zero W/2W (recommended for space/cost)
- Raspberry Pi 3/4 (works but overkill for this task)
- Must support USB OTG (USB gadget mode)
- See [docs/PI_SETUP.md](docs/PI_SETUP.md) for configuration

---

## ❓ FAQ

### How is this different from using a network-connected solution?
This uses direct USB connection through the Raspberry Pi, so your printer doesn't need network capabilities. The Pi acts as a "smart USB drive" that auto-updates.

### Can I use a different directory instead of Desktop?
Yes! The watch directory is fully configurable via `WATCH_DIR` in `config.local`. Monitor any folder you want.

### What if my printer doesn't have a USB port?
Unfortunately, this solution requires USB mass storage support. If your printer only has an SD card slot, you'll need to stick with SD cards.

### Does this work with Pi 3 or Pi 4?
Yes, but you'll need a USB OTG adapter since they don't have built-in USB gadget support via micro-USB. Pi Zero W/2W are recommended for simplicity.

### Is this secure?
Yes. The project includes 8 layers of security:
- Input validation (path traversal prevention, symlink rejection)
- TOCTOU mitigation (race condition prevention)
- Command injection prevention
- Network restrictions (local subnet only via systemd)
- Filesystem protection (read-only system directories)
- System call filtering
- Resource limits (memory, CPU, process count)
- Capability dropping (zero Linux capabilities)

See the [Security Architecture](#-security-architecture) section for details.

### How much does this cost?
- Raspberry Pi Zero W: ~$10-15
- Micro-USB cable (if you don't have one): ~$3-5
- **Total**: Under $20

### Can I run this alongside other Pi projects?
Yes, though the USB gadget mode will occupy the USB port. Other services (web servers, monitoring, etc.) can run simultaneously.

### Do I need to keep my computer on?
Yes, the file monitor runs on your computer and syncs files when they're created. The Pi stays on 24/7 connected to your printer.

---

## 🛠️ How It Works

1. **File Monitor** watches your configured directory for `.gcode` files using `inotifywait` or Python's `watchdog`
2. **rsync** efficiently transfers new files to the Raspberry Pi over SSH
3. **USB Gadget Refresh Script** on the Pi unbinds/rebinds the USB gadget, forcing the printer to re-enumerate
4. **3D Printer** sees the new files immediately without any reboot!

```
Local Dir → inotify/watchdog → rsync → Raspberry Pi → USB gadget → 3D Printer
            (monitors)       (transfers)  (serves)     (refreshes)   (prints!)
```

---

## 📁 Project Structure

```
pi-gcode-server/
├── monitor_and_sync.sh          # Bash file monitor (simple)
├── monitor_and_sync.py          # Python file monitor (recommended, security-hardened)
├── gcode-monitor.service        # Systemd service file (sandboxed)
├── config.example               # Configuration template
├── requirements.txt             # Python dependencies with SHA256 hashes
├── .editorconfig                # Code style configuration
├── install_and_start.sh         # Automated installation script
├── run_tests.sh                 # Test suite runner
├── lib/                         # Shared libraries
│   └── error_handler.sh         # Centralized error handling for shell scripts
├── tests/                       # Test suite
│   ├── unit/                    # Unit tests
│   │   └── test_validation.py   # Validation logic tests
│   ├── security/                # Security tests
│   │   └── test_security.py     # OWASP Top 10 vulnerability tests
│   └── integration/             # Integration tests
│       └── test_integration.py  # End-to-end workflow tests
├── pi_scripts/                  # Raspberry Pi server scripts
│   ├── diagnose_usb_gadget.sh   # Diagnostic tool
│   ├── refresh_usb_gadget.sh    # Universal USB refresh (auto-detects)
│   ├── refresh_usb_gadget_configfs.sh
│   └── refresh_usb_gadget_module.sh
└── docs/                        # Documentation
    ├── QUICKSTART.md
    ├── PI_SETUP.md
    ├── NETWORK_OPTIMIZATION_RESULTS.md
    ├── TROUBLESHOOTING.md
    └── ARCHITECTURE.md
```

---

## 🔒 Security Architecture

This project implements **defense-in-depth** security with multiple layers of protection against common attacks.

### Security Features

#### 🛡️ Input Validation & Sanitization
- **Path Traversal Prevention**: All file paths validated using Python `Path().resolve().relative_to()` to prevent `../` escapes
- **Symlink Attack Prevention**: Files validated as regular files, symlinks rejected before processing
- **Extension Validation**: Only `.gcode` files processed (case-sensitive)
- **File Size Limits**:
  - Minimum 1 byte (prevents empty file DoS)
  - Maximum 1 GB (prevents disk exhaustion DoS)
  - Warning threshold at 500 MB for large files

#### 🔐 Command Injection Prevention
- **Shell Variable Quoting**: All shell variables properly quoted in `monitor_and_sync.sh` and `test_sync.sh`
- **No User-Controlled Commands**: File paths never used in shell execution contexts
- **Error Handler Library**: Centralized error handling (`lib/error_handler.sh`) with strict mode (`set -euo pipefail`)

#### ⏱️ TOCTOU Race Condition Mitigation
- **Re-validation Before Use**: Files re-validated immediately before rsync execution
- **Minimal TOCTOU Window**: <20 lines of code between validation and use
- **Three-Layer Validation**:
  1. Initial validation (extension, size, type)
  2. Re-validation (symlink, file type, extension)
  3. Execution (rsync with timeout)

#### 🌐 Network Security
- **Systemd Sandboxing**:
  - `RestrictAddressFamilies=AF_INET AF_INET6` (network-only)
  - `IPAddressAllow=192.168.1.0/24` (local subnet only)
  - `IPAddressDeny=any` (deny by default)
- **SSH Key Authentication**: Passwordless authentication required
- **Encrypted Transport**: All data transfer over SSH
- **Timeout Protection**: Network operations have configured timeouts

#### 🔒 Filesystem Protection
- **Systemd Restrictions**:
  - `ProtectSystem=strict` (immutable system directories)
  - `ProtectHome=tmpfs` (isolated home directory)
  - `BindReadOnlyPaths` (read-only bind mounts)
  - `NoNewPrivileges=true` (prevents privilege escalation)
- **Path Bounds Checking**: Files must be within configured watch directory
- **Forbidden Paths**: `/etc`, `/var`, `/usr`, `/bin`, `/sbin`, `/boot` blocked

#### 🚫 System Call Filtering
- **Systemd Syscall Filtering**:
  - `SystemCallFilter=@system-service` (allowlist approach)
  - `SystemCallFilter=~@privileged @resources @obsolete` (deny dangerous calls)
  - `SystemCallArchitectures=native` (no foreign architectures)

#### 🔄 Resilience & DoS Prevention
- **Retry Logic**: Exponential backoff for transient failures (2s, 4s, 8s delays)
- **Dynamic Timeouts**: Timeout scales with file size (baseline 2min + 1min per 100MB)
- **Resource Limits**:
  - `MemoryMax=500M` (memory limit)
  - `CPUQuota=50%` (CPU throttling)
  - `TasksMax=20` (process limit)

#### 📦 Supply Chain Security
- **Dependency Hashing**: `requirements.txt` includes SHA256 hashes
- **Version Pinning**: All dependencies pinned to specific versions
- **Minimal Dependencies**: Only `watchdog==3.0.0` for file monitoring

### Attack Surface Reduction

| Attack Vector | Mitigation | Layer |
|---------------|-----------|-------|
| Command Injection | Quoted variables, no shell execution | Input Validation |
| Path Traversal | Bounds checking, relative_to() validation | Input Validation |
| Symlink Attacks | islink() checks, realpath validation | Input Validation |
| TOCTOU Races | Re-validation before use | Process |
| File Size DoS | MIN/MAX size limits, dynamic timeouts | Resource Limits |
| Network Attacks | Systemd IP restrictions, SSH encryption | Network |
| Privilege Escalation | NoNewPrivileges, capability dropping | Systemd |
| Syscall Exploits | SystemCallFilter allowlist | Systemd |

### Testing

Comprehensive test suite validates security controls:
- **Unit Tests** (`tests/unit/`): Validation logic, retry behavior
- **Security Tests** (`tests/security/`): OWASP Top 10, injection, traversal
- **Integration Tests** (`tests/integration/`): End-to-end workflows

Run tests with:
```bash
./run_tests.sh
```

### Security Considerations

- **SSH Keys**: Store private keys with permissions `0600`, never commit to version control
- **config.local**: Git-ignored to prevent credential exposure
- **Log Files**: Do not log sensitive data (credentials, file contents)
- **Network Isolation**: Run on trusted local network only (not internet-facing)
- **Principle of Least Privilege**: Service runs as non-root user with minimal capabilities

### Reporting Security Issues

Please report security vulnerabilities privately via GitHub Security Advisories or email maintainers directly. Do not open public issues for security bugs.

---

## 🤝 Contributing

Contributions are welcome! Here's how you can help:

### Ways to Contribute
- **Printer Compatibility Reports**: Test with your printer and report results
- **Documentation**: Improve setup guides, add troubleshooting tips
- **Bug Reports**: Found an issue? [Open an issue](https://github.com/mlugo-apx/pi-gcode-server/issues)
- **Feature Requests**: Have an idea? Share it in [Discussions](https://github.com/mlugo-apx/pi-gcode-server/discussions)
- **Code Improvements**: Security enhancements, performance optimizations, bug fixes

### Pull Request Process
1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes and add tests if applicable
4. Run the test suite: `./run_tests.sh`
5. Commit your changes (`git commit -m 'Add amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request with a clear description

### Code Style
- Python: Follow PEP 8, use type hints
- Bash: Use shellcheck, follow Google Shell Style Guide
- Security: All inputs must be validated, no shell injection vulnerabilities

---

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- Inspired by the need to eliminate manual file transfers to 3D printers
- Built with Raspberry Pi USB gadget mode (ConfigFS)
- Optimized through systematic network performance analysis

---

## 📧 Support

- **Issues**: [GitHub Issues](https://github.com/mlugo-apx/pi-gcode-server/issues)
- **Discussions**: [GitHub Discussions](https://github.com/mlugo-apx/pi-gcode-server/discussions)

---

## 🔍 Health Monitoring

Use the bundled health check to verify the service and logs are fresh:

```bash
./check_gcode_monitor.sh
```

For periodic checks, add a cron entry (every 15 minutes shown):

```cron
*/15 * * * * /home/your_username/pi-gcode-server/check_gcode_monitor.sh >> /home/your_username/pi-gcode-server/logs/health_check.log 2>&1
```

The script validates:
- `gcode-monitor.service` is active
- `~/.gcode_sync.log` has been updated within the last 30 minutes
- The systemd journal has no recent errors for the service

---

**Happy Printing!** 🖨️✨
