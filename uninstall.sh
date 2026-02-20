#!/bin/bash

# [HARDENING] stop on error | error on unset vars
set -eu

# ============================================================
# [PRE-FLIGHT] Environment Audit
# ============================================================
OS="$(uname -s)"
[[ "$OS" == "Linux"* ]] && PLATFORM="linux" || PLATFORM="mac"
REAL_USER="${SUDO_USER:-$(whoami)}"

# ---------- UI Elements ----------
BOLD="\033[1m"
DIM="\033[2m"
RED="\033[1;31m"
CYAN="\033[1;36m"
RESET="\033[0m"
INFO="${CYAN}➜${RESET}"

print_step() { printf "  ${INFO}  %-45s" "$1"; }
print_done() { printf "${BOLD}${RED}[ REMOVED ]${RESET}\n"; }

# Privilege Check
if [[ "$EUID" -ne 0 ]]; then
    printf "\n  ${RED}❌ Error:${RESET} Uninstallation requires sudo.\n\n"
    exit 1
fi

clear
printf "  ${BOLD}┌────────────────────────────────────────────────────────────────────┐${RESET}\n"
printf "  ${BOLD}│  ${RED}🗑️  StackPulse${RESET}${BOLD} — Universal Uninstaller v1.5                    │${RESET}\n"
printf "  ${BOLD}└────────────────────────────────────────────────────────────────────┘${RESET}\n"

printf "\n  ${BOLD}Cleanup Progress:${RESET}\n"
printf "  ${DIM}────────────────────────────────────────────────────────────────────${RESET}\n"

# 1. Stop and Remove Background Services
print_step "De-registering background tasks..."
if [[ "$PLATFORM" == "linux" ]]; then
    if command -v systemctl &>/dev/null; then
        systemctl stop stackpulse.timer >/dev/null 2>&1 || true
        systemctl disable stackpulse.timer >/dev/null 2>&1 || true
        rm -f /etc/systemd/system/stackpulse.service /etc/systemd/system/stackpulse.timer
        systemctl daemon-reload
    fi
else
    USER_HOME=$(eval echo "~$REAL_USER")
    PLIST="$USER_HOME/Library/LaunchAgents/com.stackpulse.monitor.plist"
    if [[ -f "$PLIST" ]]; then
        sudo -u "$REAL_USER" launchctl unload "$PLIST" >/dev/null 2>&1 || true
        rm -f "$PLIST"
    fi
fi
print_done

# 2. Remove Binary
print_step "Deleting StackPulse binary..."
BIN_DIR="/usr/local/bin"
[[ "$PLATFORM" == "mac" && -d "/opt/homebrew/bin" ]] && BIN_DIR="/opt/homebrew/bin"
rm -f "$BIN_DIR/stackpulse"
print_done

# 3. Cleanup Logs and Rotation Configs
print_step "Purging telemetry logs & rotation configs..."
if [[ "$PLATFORM" == "linux" ]]; then
    rm -f /var/log/stackpulse.log*
    rm -f /etc/logrotate.d/stackpulse
else
    USER_HOME=$(eval echo "~$REAL_USER")
    rm -f "$USER_HOME/Library/Logs/stackpulse.log"*
    rm -f /etc/newsyslog.d/stackpulse.conf
fi
print_done

# 4. Remove Temp Files
print_step "Cleaning temporary artifacts..."
rm -f /tmp/sp_raw_* /tmp/sp_clean_* /tmp/sp_t_counts
print_done

printf "  ${DIM}────────────────────────────────────────────────────────────────────${RESET}\n"
printf "\n  ✨  ${BOLD}StackPulse has been completely removed from your system.${RESET}\n"
printf "      ${DIM}Note: Docker and Nginx were left intact as they are external deps.${RESET}\n\n"