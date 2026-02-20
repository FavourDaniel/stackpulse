#!/bin/bash

# Stop on first error
set -e

# ============================================================
# [PRE-FLIGHT] Self-Elevate to Sudo
# ============================================================
# This handles authentication BEFORE clearing the screen or drawing UI.
# If the password was recently entered, sudo caching allows it to pass silently.
if [ "$EUID" -ne 0 ]; then
  echo "Authenticating with sudo..."
  exec sudo "$0" "$@"
fi

# ---------- Professional UI Elements ----------
BOLD="\033[1m"
DIM="\033[2m"
CYAN="\033[1;36m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
RESET="\033[0m"

# Symbols
INFO="${CYAN}➜${RESET}"
SUCCESS="✨"
ERROR="❌"

# Helper: Print aligned steps (locked to a 42-character column)
print_step() {
    printf "  ${INFO}  %-42s" "$1"
}

print_done() {
    printf "${BOLD}${GREEN}[ DONE ]${RESET}\n"
}

print_fail() {
    printf "${BOLD}${RED}[ FAIL ]${RESET}\n"
}

# ============================================================
# Header & Environment Detection
# ============================================================

clear
# Recalculated Box: 60 dashes wide. 
# Emoji '⚡' is treated as 2 chars wide by the terminal renderer.
printf "  ${BOLD}┌────────────────────────────────────────────────────────────┐${RESET}\n"
printf "  ${BOLD}│  ${CYAN}⚡ StackPulse${RESET}${BOLD} — Universal Installer v1.0                  │${RESET}\n"
printf "  ${BOLD}└────────────────────────────────────────────────────────────┘${RESET}\n"
printf "\n"

OS="$(uname -s)"
case "$OS" in
  Linux*)  PLATFORM="linux" ; OS_DISPLAY="Linux" ;;
  Darwin*) PLATFORM="mac"   ; OS_DISPLAY="macOS" ;;
  *) printf "  ${ERROR} Unsupported OS: $OS\n"; exit 1 ;;
esac

# Identify the original user (not root) for pathing
REAL_USER="${SUDO_USER:-$(whoami)}"

printf "  ${DIM}●  Environment  ${RESET} %s\n" "$OS_DISPLAY"
printf "  ${DIM}●  User         ${RESET} %s\n" "$REAL_USER"
printf "  ${DIM}●  Privileges   ${RESET} Authenticated\n"

# ============================================================
# Main Progress UI
# ============================================================

printf "\n  ${BOLD}Progress:${RESET}\n"
printf "  ${DIM}────────────────────────────────────────────────────────────${RESET}\n"

# [1/4] Dependencies
print_step "Installing dependencies..."
install_deps() {
  if [[ "$PLATFORM" == "linux" ]]; then
    apt-get update -qq >/dev/null 2>&1
    apt-get install -y curl nginx coreutils gawk grep sed docker.io >/dev/null 2>&1
  else
    # Homebrew MUST be run as the real user, not root
    if ! sudo -u "$REAL_USER" command -v brew &>/dev/null; then return 1; fi
    sudo -u "$REAL_USER" brew install curl nginx coreutils gawk grep gnu-sed >/dev/null 2>&1 || true
  fi
}
install_deps || { print_fail; exit 1; }
print_done

# [2/4] Log Configuration
print_step "Configuring system logs..."
if [[ "$PLATFORM" == "linux" ]]; then
  LOG_FILE="/var/log/stackpulse.log"
  touch "$LOG_FILE" && chmod 644 "$LOG_FILE"
else
  USER_HOME=$(eval echo "~$REAL_USER")
  LOG_FILE="$USER_HOME/Library/Logs/stackpulse.log"
  mkdir -p "$(dirname "$LOG_FILE")"
  touch "$LOG_FILE"
  chmod 644 "$LOG_FILE"
  chown "$REAL_USER" "$LOG_FILE"
fi
print_done

# [3/4] Binary Installation
print_step "Installing binary..."
if [[ ! -f stackpulse.sh ]]; then
  print_fail
  printf "  ${RED}Error: stackpulse.sh not found in current directory.${RESET}\n"
  exit 1
fi

if [[ "$PLATFORM" == "mac" ]]; then
  [[ -d "/opt/homebrew/bin" ]] && BIN_DIR="/opt/homebrew/bin" || BIN_DIR="/usr/local/bin"
else
  BIN_DIR="/usr/local/bin"
fi
BINARY_PATH="$BIN_DIR/stackpulse"

mkdir -p "$BIN_DIR"
cp stackpulse.sh "$BINARY_PATH"
chmod +x "$BINARY_PATH"
print_done

# [4/4] Background Service
print_step "Registering monitoring service..."
if [[ "$PLATFORM" == "linux" ]]; then
    cat << EOF | tee /etc/systemd/system/stackpulse.service >/dev/null
[Unit]
Description=StackPulse Monitoring
After=network.target

[Service]
ExecStart=/bin/bash -c 'while true; do $BINARY_PATH -t 1m >> $LOG_FILE 2>&1; sleep 60; done'
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable stackpulse.service >/dev/null 2>&1
    systemctl start stackpulse.service >/dev/null 2>&1
else
    USER_HOME=$(eval echo "~$REAL_USER")
    PLIST="$USER_HOME/Library/LaunchAgents/com.stackpulse.monitor.plist"
    mkdir -p "$USER_HOME/Library/LaunchAgents"
    
    cat << EOF | tee "$PLIST" >/dev/null
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.stackpulse.monitor</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>-c</string>
    <string>while true; do $BINARY_PATH -t 1m >> $LOG_FILE 2>&1; sleep 60; done</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$LOG_FILE</string>
  <key>StandardErrorPath</key><string>$LOG_FILE</string>
</dict>
</plist>
EOF
    chown "$REAL_USER" "$PLIST"
    chmod 644 "$PLIST"
    # Execute launchctl as the user
    sudo -u "$REAL_USER" launchctl unload "$PLIST" 2>/dev/null || true
    sudo -u "$REAL_USER" launchctl load "$PLIST" >/dev/null 2>&1
fi
print_done

# ============================================================
# Final Success Summary
# ============================================================

printf "  ${DIM}────────────────────────────────────────────────────────────${RESET}\n"
printf "\n"
printf "  ${SUCCESS}  ${BOLD}Installation Complete!${RESET}\n"
printf "\n"
printf "  ${BOLD}Access Points:${RESET}\n"
printf "  ${DIM}●  Binary ${RESET}  %s\n" "$BINARY_PATH"
printf "  ${DIM}●  Logs   ${RESET}  %s\n" "$LOG_FILE"
printf "\n"
printf "  ${BOLD}Next Steps:${RESET}\n"
printf "  1. View live metrics:  ${CYAN}tail -f %s${RESET}\n" "$LOG_FILE"
printf "  2. System help:        ${CYAN}stackpulse -h${RESET}\n"
printf "\n"