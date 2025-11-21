# Example Configurations

This directory contains example configurations for common setups. These are templates to help you get started quickly.

## How to Use

1. **Copy the relevant example** to `config.local` in the project root:
   ```bash
   cp examples/config.ender3 config.local
   ```

2. **Edit with your details**:
   - Change `REMOTE_HOST` to your Pi's IP address
   - Change `REMOTE_USER` if you're not using `pi`
   - Adjust `WATCH_DIR` if you want to monitor a different folder

3. **Secure the file**:
   ```bash
   chmod 600 config.local
   ```

4. **Test the connection**:
   ```bash
   ./test_sync.sh  # If available
   # Or manually test SSH:
   ssh -p 22 pi@192.168.1.100
   ```

## Available Examples

### By Printer
- **config.ender3** - Creality Ender 3 / Ender 3 V2 / Ender 3 Pro
- **config.prusa** - Prusa MK3S / MK3S+ / MK4

### By Platform
- **config.wsl2** - Windows 10/11 with WSL2
- **config.macos** - macOS (Monterey, Ventura, Sonoma)

### Universal
- **config.example** (in project root) - Generic template for any setup

## Common Customizations

### Different Watch Directory
```bash
# Instead of Desktop:
WATCH_DIR="$HOME/Downloads"          # Linux/macOS
WATCH_DIR="/mnt/c/Users/You/Downloads"  # WSL2
```

### Multiple Slicers
If you use multiple slicers, create separate watch directories:
```bash
WATCH_DIR="$HOME/3DPrinting/ToSync"
```

Then configure your slicers to save to this folder.

### Non-Standard SSH Port
If you changed your Pi's SSH port for security:
```bash
REMOTE_PORT="2222"  # Your custom port
```

### Different Pi Username
If you created a custom user instead of using `pi`:
```bash
REMOTE_USER="myuser"
```

## Need Help?

- **Full documentation**: See main [README.md](../README.md)
- **Troubleshooting**: See [docs/TROUBLESHOOTING.md](../docs/TROUBLESHOOTING.md)
- **Pi setup**: See [docs/PI_SETUP.md](../docs/PI_SETUP.md)
- **Report issues**: [GitHub Issues](https://github.com/mlugo-apx/pi-gcode-server/issues)

## Contributing

Have a working setup with a different printer or platform? Please contribute an example config via pull request!
