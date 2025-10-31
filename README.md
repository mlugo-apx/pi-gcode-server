# pi-gcode-server

**Auto-sync GCode files from your desktop to 3D printer via Raspberry Pi USB gadget**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/platform-Raspberry%20Pi-red.svg)](https://www.raspberrypi.org/)

Automatically monitor your desktop for `.gcode` files and wirelessly sync them to your 3D printer through a Raspberry Pi configured as a USB mass storage device. No manual file transfers, no printer reboots required!

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

### 1. Clone Repository
```bash
git clone https://github.com/mlugo-apx/pi-gcode-server.git
cd pi-gcode-server
```

### 2. Configure Your Setup
```bash
# Copy example config and customize
cp config.example config.local
nano config.local  # Edit with your Pi's IP, username, etc.
```

### 3. Setup Raspberry Pi
See [Pi Setup Guide](docs/PI_SETUP.md) for detailed instructions on:
- Configuring USB gadget mode
- Creating FAT32 backing storage
- Installing refresh scripts
- Optimizing network performance (CRITICAL!)

### 4. Install Local Monitor
```bash
# Option A: Automated installation
chmod +x install_and_start.sh
./install_and_start.sh

# Option B: Manual setup
chmod +x monitor_and_sync.sh
./monitor_and_sync.sh  # Test manually first
```

### 5. Enable as Service (Optional but Recommended)
```bash
sudo cp gcode-monitor.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable gcode-monitor.service
sudo systemctl start gcode-monitor.service
```

### 6. Test It!
```bash
# Copy a test gcode file to your Desktop
cp test.gcode ~/Desktop/

# Check logs
tail -f ~/.gcode_sync.log

# Verify file reached the Pi
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

## 🛠️ How It Works

1. **File Monitor** watches your `~/Desktop` directory for `.gcode` files using `inotifywait` or Python's `watchdog`
2. **rsync** efficiently transfers new files to the Raspberry Pi over SSH
3. **USB Gadget Refresh Script** on the Pi unbinds/rebinds the USB gadget, forcing the printer to re-enumerate
4. **3D Printer** sees the new files immediately without any reboot!

```
Desktop → inotify/watchdog → rsync → Raspberry Pi → USB gadget → 3D Printer
           (monitors)       (transfers)  (serves)     (refreshes)   (prints!)
```

---

## 📁 Project Structure

```
pi-gcode-server/
├── monitor_and_sync.sh          # Bash file monitor (simple)
├── monitor_and_sync.py          # Python file monitor (recommended)
├── gcode-monitor.service        # Systemd service file
├── config.example               # Configuration template
├── install_and_start.sh         # Automated installation script
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

## 🔒 Security Notes

- This project uses **SSH key-based authentication** (passwordless sudo for refresh script)
- `config.local` is git-ignored to prevent accidentally committing sensitive info
- All communication is encrypted via SSH
- USB gadget operates on local network only (no internet exposure)

---

## 🤝 Contributing

Contributions welcome! Please:
1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

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

## 🎯 Roadmap

- [ ] Web interface for file management
- [ ] Support for multiple 3D printers
- [ ] OctoPrint integration option
- [ ] Windows/macOS support
- [ ] Automatic WiFi channel optimization
- [ ] Print queue management

---

**Happy Printing!** 🖨️✨
