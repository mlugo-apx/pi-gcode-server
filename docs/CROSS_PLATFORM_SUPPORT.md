# Cross-Platform Deployment Options

This project was designed and hardened primarily for Linux (Ubuntu/Debian)
environments. Bringing the same functionality to Windows and macOS requires
some deliberate compromises and packaging work. Below is a survey of the most
practical paths along with their trade-offs.

---

## Windows

### 1. Windows Subsystem for Linux (WSL2)  ✅ Recommended
- **Approach**: Distribute the existing Linux workflow inside WSL2.
- **Pros**:
  - Reuses the hardened Linux implementation with minimal changes.
  - Provides access to systemd (with recent WSL releases) and native bash.
  - Keeps all security validation and tests intact.
- **Cons**:
  - Requires users to enable WSL2 and install an Ubuntu image.
  - USB gadget functionality still needs to happen on the Raspberry Pi, so WSL
    only covers the desktop monitor side.
- **Actions**:
  1. Create a step-by-step WSL setup guide (install WSL, enable systemd,
     clone repo, run setup).
  2. Provide a PowerShell bootstrap script that installs dependencies and
     launches the install wizard inside WSL.

### 2. Native Windows Port  ⚠️ High Effort / Limited Parity
- **Approach**: Port the monitor to a Windows-native service.
- **Pros**:
  - No WSL dependency; integrates with the Windows ecosystem.
- **Cons**:
  - Need to replace inotify/systemd tooling.
  - Reimplement secure config parsing, logging, and service sandboxing with
    Windows equivalents (task scheduler, event log, etc.).
  - Requires a different security test suite.
- **Actions**:
  - Prototype a PowerShell service or a Python script running as a
    Windows service using `pywin32`.
  - Replace rsync with robocopy/WinSCP or ship rsync via Cygwin.
  - Significant QA pass to ensure parity.

### 3. Docker Desktop  ⚠️ Not Ideal
- **Approach**: Run the Linux monitor inside a Docker container on Windows.
- **Pros**:
  - Reuses Linux artifacts.
- **Cons**:
  - Desktop file system access through Docker for Desktop is slower and more
    brittle (file watchers do not always trigger reliably).
  - Increased setup complexity for end users.

---

## macOS

### 1. Native Python Service with launchd  ✅ Recommended
- **Approach**: Package the Python monitor for macOS and manage it with `launchd`.
- **Pros**:
  - Python + watchdog works natively on macOS (watchdog uses FSEvents).
  - No virtualization needed; simpler install story than Windows.
- **Cons**:
  - Need to rewrite systemd sandboxing rules as `launchd` plist options.
  - rsync + ssh tooling exists but requires Homebrew/Xcode CLT for installation.
- **Actions**:
  1. Write a Homebrew formula or installer script to install dependencies
     (`python3`, `rsync`, etc.).
  2. Create a `launchd` plist that invokes `monitor_and_sync.py`.
  3. Update the security hardening checklist for macOS equivalents
     (sandbox/permissions).
  4. Document notarization steps if distributing as an app bundle.

### 2. Multipass/VM  ⚠️ Backup Option
- **Approach**: Run the existing Linux workflow inside Canonical Multipass or
  VirtualBox.
- **Pros**:
  - Exact Linux environment.
- **Cons**:
  - Virtualization overhead; users must keep VM running.

---

## Packaging & Distribution Recommendations

| Target    | Primary Option           | Tooling                     |
|-----------|--------------------------|-----------------------------|
| Linux     | Current approach         | systemd service             |
| Windows   | WSL2 (preferred)         | PowerShell bootstrap + WSL  |
| Windows   | Native port (stretch)    | PowerShell service + rsync  |
| macOS     | launchd-based service    | Homebrew installer + plist  |

---

## Next Steps Checklist

1. **Author WSL install guide** (`docs/WSL_SETUP.md`) and companion PowerShell script.
2. **Prototype macOS launchd plist** and document dependency installation.
3. **Evaluate native Windows service** feasibility (time-box spike).
4. **Decide on distribution channel**:
   - GitHub releases with platform-specific installers/scripts.
   - Optional Homebrew tap (macOS) and winget package (Windows/WSL bootstrap).
5. **Update README** with a platform matrix and point to the new guides.
6. **Gather beta feedback** from Windows/macOS users to refine automation.

By starting with WSL2 and macOS launchd support, we extend reach to the
major desktop platforms with manageable effort while preserving the security
hardening baked into the Linux solution.
