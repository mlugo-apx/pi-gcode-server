# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- GitHub Actions CI/CD workflow for automated testing and linting
- Python linting with flake8 and security scanning with bandit
- Shellcheck validation for all bash scripts
- Example configuration files for common setups:
  - `examples/config.ender3` - Creality Ender 3 series
  - `examples/config.prusa` - Prusa MK3S/MK3S+/MK4
  - `examples/config.wsl2` - Windows + WSL2 configuration
  - `examples/config.macos` - macOS configuration
- Comprehensive printer compatibility matrix in README.md
- Community infrastructure files:
  - `CODE_OF_CONDUCT.md` - Contributor Covenant v2.1
  - `CONTRIBUTING.md` - Contribution guidelines
  - `SECURITY.md` - Security policy and reporting
  - GitHub issue templates for bugs and features
  - Pull request template
- Automatic detection of `uv` package manager for faster dependency installation
- USB refresh retry logic with exponential backoff (3 attempts: 0s, 2s, 4s delays)
- Detailed sync session summary logging with statistics

### Changed
- Service file converted to template format with placeholder substitution
- Install script now auto-detects and substitutes user paths dynamically
- Configuration parsing replaced unsafe `source` with safe key=value parser
- Auto-install for dependencies now continues execution after successful install
- Project naming standardized to "pi-gcode-server" across all documentation
- Improved rsync transfer statistics logging

### Fixed
- Invalid SHA256 hash in `requirements.txt` for watchdog package
- Auto-install exit code bug preventing script continuation after dependency installation
- Command injection vulnerability in bash config file parsing
- TOCTOU (Time-of-Check-Time-of-Use) race condition in file validation
- Insecure file permissions recommendation (chmod 777 → 755) in troubleshooting docs
- Missing script integrity verification documentation for Pi setup
- Hardcoded paths in systemd service file

### Security
- Implemented 8-layer defense-in-depth security architecture:
  1. Input validation (path bounds, symlink detection, file type validation)
  2. TOCTOU mitigation (re-validation before operations)
  3. Command injection prevention (parameterized commands only)
  4. Network security (systemd IP restrictions to local subnet)
  5. Filesystem protection (read-only mounts, minimal write access)
  6. Syscall filtering (systemd allowlists/blocklists)
  7. Resource limits (memory, CPU, process caps)
  8. Capability dropping (zero Linux capabilities)
- Enhanced systemd service hardening with comprehensive sandboxing
- SHA256 hash verification for all Python dependencies (supply chain security)
- Added security reporting policy and vulnerability disclosure process
- Security scanning integrated into CI/CD pipeline (bandit)

## [1.0.0] - 2025-01-XX (Initial Public Release)

### Added
- Real-time G-code file monitoring and sync from local machine to Raspberry Pi
- Automatic USB gadget refresh for immediate printer detection
- Cross-platform support (Linux, macOS, Windows via WSL2)
- Systemd service for automatic startup
- Comprehensive documentation:
  - Quick start guide
  - Architecture overview
  - Raspberry Pi setup instructions
  - Troubleshooting guide
  - Network optimization results
- Setup wizard for easy configuration
- Bash and Python monitoring scripts
- Error handling and logging system

### Technical Details
- Python-based file monitoring using watchdog library
- Rsync for efficient file transfers
- SSH-based secure communication with Raspberry Pi
- USB gadget mode configuration for Pi Zero W/2W
- FAT32 filesystem support for printer compatibility

---

## Version History Summary

- **v1.0.0** - Initial public release with core functionality
- **Unreleased** - Security hardening, CI/CD automation, community infrastructure

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on reporting issues, requesting features, and submitting pull requests.

## Security

See [SECURITY.md](SECURITY.md) for security policy, vulnerability reporting, and best practices.

---

*This changelog is maintained by humans. For detailed commit history, see `git log`.*
