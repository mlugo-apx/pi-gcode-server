# Deprecated Scripts

This directory contains scripts that have been deprecated and replaced with more secure alternatives.

## Deprecated Files

### `scp_to_printer.py`
**Deprecated Date**: 2025-10-31
**Reason**: Hardcoded credentials, security vulnerabilities
**Replacement**: `monitor_and_sync.py` with `config.local`

**Issues**:
- Hardcoded IP addresses and credentials in source code
- No input validation
- No error handling
- Single-shot transfer (no monitoring)

**Migration**:
```bash
# Old (deprecated):
python3 scp_to_printer.py file.gcode

# New (secure):
cp file.gcode ~/Desktop/  # Automatically synced by monitor_and_sync.py
```

### `setup.sh`
**Deprecated Date**: 2025-10-31
**Reason**: Duplicate of setup_wizard.sh
**Replacement**: `setup_wizard.sh`

**Issues**:
- Duplicate functionality
- Less user-friendly than wizard
- Not maintained

**Migration**:
```bash
# Old (deprecated):
./setup.sh

# New:
./setup_wizard.sh
```

### `run_monitor.sh`
**Deprecated Date**: 2025-10-31
**Reason**: Superseded by systemd service
**Replacement**: `systemd` service or direct `monitor_and_sync.py` execution

**Issues**:
- Loads config but doesn't use error_handler.sh
- Less robust than systemd service
- No automatic restart on failure

**Migration**:
```bash
# Old (deprecated):
./run_monitor.sh

# New (preferred - systemd service):
sudo systemctl enable gcode-monitor.service
sudo systemctl start gcode-monitor.service

# New (manual execution):
python3 monitor_and_sync.py
# OR
./monitor_and_sync.sh
```

## Why These Files Are Kept

These files are retained in the `deprecated/` directory rather than deleted to:
1. Maintain git history
2. Allow users to reference old implementations
3. Document the evolution of the project
4. Provide migration examples

## Security Notice

⚠️ **DO NOT USE THESE SCRIPTS IN PRODUCTION** ⚠️

These scripts contain known security vulnerabilities and have been deprecated for security reasons. Always use the actively maintained alternatives listed above.

## Removal

These files may be completely removed in a future major version (v2.0.0+).
