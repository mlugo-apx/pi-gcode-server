#!/bin/bash
# Shared error handling library for shell scripts
# Source this file at the top of your scripts:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/error_handler.sh"

# Enable strict error handling
set -euo pipefail

# Color codes for output
readonly ERROR_COLOR='\033[0;31m'
readonly WARN_COLOR='\033[1;33m'
readonly INFO_COLOR='\033[0;32m'
readonly DEBUG_COLOR='\033[0;36m'
readonly NC='\033[0m'

# Log levels
readonly LOG_LEVEL_ERROR=0
readonly LOG_LEVEL_WARN=1
readonly LOG_LEVEL_INFO=2
readonly LOG_LEVEL_DEBUG=3

# Default log level (can be overridden)
: "${SCRIPT_LOG_LEVEL:=$LOG_LEVEL_INFO}"

# Global error trap handler
error_trap() {
    local exit_code=$1
    local line_number=$2
    local bash_lineno=${3:-}
    local command="${BASH_COMMAND}"
    local func_name="${FUNCNAME[1]:-main}"

    log_error "Command failed with exit code $exit_code at line $line_number"
    log_error "Function: $func_name"
    log_error "Command: $command"

    # Log to syslog if available
    if command -v logger &>/dev/null; then
        logger -t "${SCRIPT_NAME:-gcode-sync}" -p user.err \
            "Script failed: $command (exit $exit_code, line $line_number)"
    fi

    # Don't exit if we're already exiting
    if [ $exit_code -ne 0 ]; then
        exit $exit_code
    fi
}

# Install error trap
trap 'error_trap $? $LINENO $BASH_LINENO' ERR

# Exit handler for cleanup
cleanup_trap() {
    local exit_code=$?

    # Call user-defined cleanup function if it exists
    if declare -f cleanup_on_exit &>/dev/null; then
        cleanup_on_exit $exit_code
    fi
}

trap cleanup_trap EXIT

# Logging functions
log_error() {
    local message="$1"
    if [ $SCRIPT_LOG_LEVEL -ge $LOG_LEVEL_ERROR ]; then
        echo -e "${ERROR_COLOR}[ERROR]${NC} $message" >&2

        # Also log to syslog
        if command -v logger &>/dev/null; then
            logger -t "${SCRIPT_NAME:-gcode-sync}" -p user.err "$message"
        fi
    fi
}

log_warn() {
    local message="$1"
    if [ $SCRIPT_LOG_LEVEL -ge $LOG_LEVEL_WARN ]; then
        echo -e "${WARN_COLOR}[WARN]${NC} $message" >&2

        if command -v logger &>/dev/null; then
            logger -t "${SCRIPT_NAME:-gcode-sync}" -p user.warning "$message"
        fi
    fi
}

log_info() {
    local message="$1"
    if [ $SCRIPT_LOG_LEVEL -ge $LOG_LEVEL_INFO ]; then
        echo -e "${INFO_COLOR}[INFO]${NC} $message"

        if command -v logger &>/dev/null; then
            logger -t "${SCRIPT_NAME:-gcode-sync}" -p user.info "$message"
        fi
    fi
}

log_debug() {
    local message="$1"
    if [ $SCRIPT_LOG_LEVEL -ge $LOG_LEVEL_DEBUG ]; then
        echo -e "${DEBUG_COLOR}[DEBUG]${NC} $message"

        if command -v logger &>/dev/null; then
            logger -t "${SCRIPT_NAME:-gcode-sync}" -p user.debug "$message"
        fi
    fi
}

# Die function - log error and exit
die() {
    local message="$1"
    local exit_code="${2:-1}"

    log_error "$message"
    exit "$exit_code"
}

# Check if command exists
require_command() {
    local cmd="$1"
    local install_hint="${2:-}"

    if ! command -v "$cmd" &>/dev/null; then
        log_error "Required command not found: $cmd"
        if [ -n "$install_hint" ]; then
            log_info "Install with: $install_hint"
        fi
        exit 1
    fi
}

# Validate file exists and is readable
require_file() {
    local file="$1"
    local description="${2:-file}"

    if [ ! -f "$file" ]; then
        die "Required $description not found: $file"
    fi

    if [ ! -r "$file" ]; then
        die "Required $description not readable: $file"
    fi
}

# Validate directory exists and is writable
require_writable_dir() {
    local dir="$1"
    local description="${2:-directory}"

    if [ ! -d "$dir" ]; then
        die "Required $description not found: $dir"
    fi

    if [ ! -w "$dir" ]; then
        die "Required $description not writable: $dir"
    fi
}

# Run command with retry logic
retry_command() {
    local max_attempts="${1:-3}"
    local delay="${2:-2}"
    local backoff_multiplier="${3:-2}"
    shift 3
    local command=("$@")

    local attempt=1
    local current_delay=$delay

    while [ $attempt -le $max_attempts ]; do
        log_debug "Attempt $attempt of $max_attempts: ${command[*]}"

        if "${command[@]}"; then
            return 0
        fi

        local exit_code=$?

        if [ $attempt -eq $max_attempts ]; then
            log_error "Command failed after $max_attempts attempts: ${command[*]}"
            return $exit_code
        fi

        log_warn "Attempt $attempt failed, retrying in ${current_delay}s..."
        sleep "$current_delay"

        current_delay=$((current_delay * backoff_multiplier))
        attempt=$((attempt + 1))
    done
}

# Timeout wrapper for commands
timeout_command() {
    local timeout_seconds="$1"
    shift
    local command=("$@")

    if command -v timeout &>/dev/null; then
        timeout "$timeout_seconds" "${command[@]}"
    else
        # Fallback if timeout command not available
        log_warn "timeout command not available, running without timeout"
        "${command[@]}"
    fi
}

# Validate network connectivity
check_network() {
    local host="$1"
    local port="${2:-22}"
    local timeout_seconds="${3:-5}"

    log_debug "Checking network connectivity to $host:$port"

    if command -v nc &>/dev/null; then
        if timeout "$timeout_seconds" nc -z "$host" "$port" &>/dev/null; then
            return 0
        else
            return 1
        fi
    elif command -v timeout &>/dev/null; then
        if timeout "$timeout_seconds" bash -c "echo >/dev/tcp/$host/$port" &>/dev/null; then
            return 0
        else
            return 1
        fi
    else
        log_warn "Cannot check network connectivity (nc and timeout not available)"
        return 0  # Assume OK
    fi
}

# Print usage information and exit
usage() {
    local message="${1:-}"

    if [ -n "$message" ]; then
        log_error "$message"
        echo
    fi

    if declare -f print_usage &>/dev/null; then
        print_usage
    else
        echo "Usage: $0 [options]"
    fi

    exit 1
}

# Export functions so they're available to subshells
export -f log_error log_warn log_info log_debug
export -f die require_command require_file require_writable_dir
export -f retry_command timeout_command check_network usage
