#!/bin/bash
# Health check for gcode-monitor systemd service.
# Usage: ./check_gcode_monitor.sh
# Optional cron entry (runs every 15 minutes):
# */15 * * * * /home/milugo/Claude_Code/Send_To_Printer/check_gcode_monitor.sh

set -euo pipefail

SERVICE_NAME="gcode-monitor.service"
LOG_FILE="${HOME}/.gcode_sync.log"
MAX_LOG_MINUTES=30

timestamp() {
    date +"%Y-%m-%d %H:%M:%S"
}

print_header() {
    echo "[$(timestamp)] $1"
}

check_service_status() {
    if systemctl is-active --quiet "${SERVICE_NAME}"; then
        print_header "Service ${SERVICE_NAME} is active."
    else
        print_header "ERROR: Service ${SERVICE_NAME} is not active."
        systemctl status "${SERVICE_NAME}" --no-pager
        exit 1
    fi
}

check_recent_logs() {
    if [[ ! -f "${LOG_FILE}" ]]; then
        print_header "WARNING: Log file ${LOG_FILE} not found."
        return
    fi

    log_mtime=$(stat -c %Y "${LOG_FILE}")
    now=$(date +%s)
    diff_minutes=$(( (now - log_mtime) / 60 ))

    if (( diff_minutes > MAX_LOG_MINUTES )); then
        print_header "WARNING: Log file has not been updated in ${diff_minutes} minutes."
    else
        print_header "Log file updated ${diff_minutes} minutes ago."
    fi

    print_header "Last five log entries:"
    tail -n 5 "${LOG_FILE}"
}

check_recent_errors() {
    print_header "Scanning journal for recent errors..."
    if journalctl -u "${SERVICE_NAME}" --since "30 minutes ago" | grep -qi "error"; then
        print_header "ERROR: Recent errors detected in journal."
        journalctl -u "${SERVICE_NAME}" --since "30 minutes ago"
        exit 1
    else
        print_header "No errors detected in journal over the last 30 minutes."
    fi
}

check_service_status
check_recent_logs
check_recent_errors

print_header "Health check completed successfully."
