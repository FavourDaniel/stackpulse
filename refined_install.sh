#!/bin/bash

# [HARDENING] stop on error | error on unset vars | catch pipe errors
set -euo pipefail

# ============================================================
# [PRE-FLIGHT] Environment & Resource Audit
# ============================================================
OS="$(uname -s)"
[[ "$OS" == "Linux"* ]] && PLATFORM="linux" || PLATFORM="mac"
REAL_USER="${SUDO_USER:-$(whoami)}"

# 1. EARLY DISTRO DETECTION (Enterprise Polish)
if [[ "$PLATFORM" == "linux" ]]; then
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        DISTRO_DISPLAY="${PRETTY_NAME:-$ID}"
    else
        DISTRO_DISPLAY="linux"
    fi
else
    DISTRO_DISPLAY="macOS"
fi

# 2. PRIVILEGE CHECK
if [[ "$PLATFORM" == "linux" && "$EUID" -ne 0 ]]; then
    printf "\n  \033[1;31m❌ Error:\033[0m Linux installation requires sudo.\n"
    printf "     Please run: \033[1msudo $0\033[0m\n\n"
    exit 1
fi

# 3. RESOURCE AUDIT
check_network() {
    if ! curl -Is --connect-timeout 5 https://google.com >/dev/null; then
        printf "\n  \033[1;31m❌ Error:\033[0m No internet connection detected.\n\n"
        exit 1
    fi
}

check_disk() {
    if [[ "$PLATFORM" == "linux" ]]; then
        local free_kb=$(df /var --output=avail | tail -n1)
        if [ "$free_kb" -lt 512000 ]; then
            printf "\n  \033[1;33m⚠  Warning:\033[0m Less than 500MB disk space available on /var.\n"
        fi
    fi
}

# ---------- Professional UI Elements ----------
BOLD="\033[1m"
DIM="\033[2m"
CYAN="\033[1;36m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
RESET="\033[0m"

INFO="${CYAN}➜${RESET}"
SUCCESS="✨"
DOCKER_STATUS="Pending"

print_step() { printf "  ${INFO}  %-42s" "$1"; }
print_done() { printf "${BOLD}${GREEN}[ DONE ]${RESET}\n"; }
print_fail() { printf "${BOLD}${RED}[ FAIL ]${RESET}\n"; }

# ============================================================
# Helper Functions
# ============================================================

detect_pkg_manager() {
    if command -v apt-get &>/dev/null; then echo "apt";
    elif command -v dnf &>/dev/null; then echo "dnf";
    elif command -v pacman &>/dev/null; then echo "pacman";
    else echo "unknown"; fi
}

safe_systemctl() {
    if command -v systemctl &>/dev/null && [[ -d /run/systemd/system ]]; then
        systemctl "$@" >/dev/null 2>&1 || true
    fi
}

# ============================================================
# Core Logic Functions
# ============================================================

install_deps() {
  if [[ "$PLATFORM" == "linux" ]]; then
    local PKG=$(detect_pkg_manager)
    
    # 1. SMART DOCKER AUDIT
    local NEED_INSTALL=true
    if command -v docker &>/dev/null; then
        safe_systemctl start docker
        if docker info &>/dev/null; then
            DOCKER_VER=$(docker --version | awk '{print $3}' | sed 's/,//')
            DOCKER_STATUS="v$DOCKER_VER"
            NEED_INSTALL=false
        fi
    fi

    if [[ "$NEED_INSTALL" == "true" ]]; then
        case "$PKG" in
            "apt")
                CODENAME="${VERSION_CODENAME:-$(lsb_release -cs 2>/dev/null || echo "stable")}"
                rm -f /etc/apt/sources.list.d/docker.list /etc/apt/keyrings/docker.gpg
                apt-get update -qq && apt-get install -y ca-certificates curl gnupg >/dev/null
                install -m 0755 -d /etc/apt/keyrings
                curl -fsSL "https://download.docker.com/linux/$ID/gpg" | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
                echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$ID $CODENAME stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
                apt-get update -qq
                NEEDRESTART_MODE=a apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" docker-ce docker-ce-cli containerd.io >/dev/null
                ;;
            "dnf")
                dnf -y install dnf-plugins-core >/dev/null
                dnf config-manager --add-repo "https://download.docker.com/linux/$ID/docker-ce.repo" >/dev/null
                dnf -y install docker-ce docker-ce-cli containerd.io >/dev/null
                ;;
            "pacman")
                pacman -Sy --noconfirm docker >/dev/null
                ;;
            *) printf "\n  ${RED}Error: Unsupported Distro.${RESET}\n"; exit 1 ;;
        esac
        # Post-install version verification
        DOCKER_VER=$(docker --version | awk '{print $3}' | sed 's/,//')
        DOCKER_STATUS="v$DOCKER_VER"
    fi
    
    # 2. COMMON UTILS
    case "$PKG" in
        "apt")    apt-get install -y nginx coreutils gawk >/dev/null ;;
        "dnf")    dnf -y install nginx coreutils gawk >/dev/null ;;
        "pacman") pacman -Sy --noconfirm nginx coreutils gawk >/dev/null ;;
    esac

    getent group docker >/dev/null || groupadd docker
    usermod -aG docker "$REAL_USER"
    safe_systemctl enable --now docker
  else
    # macOS Logic
    if ! sudo -u "$REAL_USER" command -v brew &>/dev/null; then return 1; fi
    sudo -u "$REAL_USER" brew install curl nginx coreutils gawk grep gnu-sed >/dev/null 2>&1 || true
    DOCKER_STATUS="macOS-Managed"
  fi
}

# ============================================================
# Main Execution
# ============================================================

check_network
check_disk

clear
printf "  ${BOLD}┌────────────────────────────────────────────────────────────┐${RESET}\n"
printf "  ${BOLD}│  ${CYAN}⚡ StackPulse${RESET}${BOLD} — Universal Installer v1.5                   │${RESET}\n"
printf "  ${BOLD}└────────────────────────────────────────────────────────────┘${RESET}\n"

printf "  ${DIM}●  Platform    ${RESET} %s\n" "$PLATFORM"
printf "  ${DIM}●  Distro      ${RESET} %s\n" "$DISTRO_DISPLAY"
printf "  ${DIM}●  User        ${RESET} %s\n" "$REAL_USER"

printf "\n  ${BOLD}Progress:${RESET}\n"
printf "  ${DIM}────────────────────────────────────────────────────────────${RESET}\n"

# [1/4] Dependencies
print_step "Syncing system dependencies..."
if install_deps; then
    printf "${DIM}(Docker %s)${RESET} " "$DOCKER_STATUS"
    print_done
else
    print_fail; exit 1
fi


# [2/4] Log Configuration
print_step "Initializing telemetry logs..."

# Assign platform-correct log paths
if [[ "$PLATFORM" == "linux" ]]; then
    LOG_FILE="/var/log/stackpulse.log"
    # Ensure file exists and is writable by the system
    touch "$LOG_FILE" && chmod 644 "$LOG_FILE"

    # 🔄 Linux Log Rotation (logrotate)
    cat << EOF | sudo tee /etc/logrotate.d/stackpulse >/dev/null
/var/log/stackpulse.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
    su root root
}
EOF
else
    # macOS: Use the real user's Library path for better compatibility
    USER_HOME=$(eval echo "~$REAL_USER")
    LOG_FILE="$USER_HOME/Library/Logs/stackpulse.log"
    
    # Create the directory if it doesn't exist
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # Create the log and ensure the User owns it
    touch "$LOG_FILE" && chmod 644 "$LOG_FILE" && chown "$REAL_USER" "$LOG_FILE"

    # 🔄 macOS Log Rotation (newsyslog)
    # This keeps 7 logs of 1MB each, rotated when they hit that size
    cat << EOF | sudo tee /etc/newsyslog.d/stackpulse.conf >/dev/null
# logfilename                      [owner:group]    mode count size when  flags [/pid_file] [sig_num]
$LOG_FILE                          $REAL_USER:staff 644  7     1000 * J
EOF
fi

print_done

# [3/4] Binary Installation
print_step "Deploying StackPulse binary..."

# Standardize binary location
BIN_DIR="/usr/local/bin"
# Adjust for Apple Silicon / Homebrew environments if necessary
[[ "$PLATFORM" == "mac" && -d "/opt/homebrew/bin" ]] && BIN_DIR="/opt/homebrew/bin"

BINARY_PATH="$BIN_DIR/stackpulse"

if [[ ! -f stackpulse.sh ]]; then 
    printf "\n  ${RED}❌ Error:${RESET} stackpulse.sh not found in current directory.\n"
    exit 1
fi

cp stackpulse.sh "$BINARY_PATH" && chmod +x "$BINARY_PATH"
print_done


# [4/4] Background Service & Timer
print_step "Registering background timer..."
if [[ "$PLATFORM" == "linux" ]]; then
    if command -v systemctl &>/dev/null && [[ -d /run/systemd/system ]]; then
        cat << EOF | tee /etc/systemd/system/stackpulse.service >/dev/null
[Unit]
Description=StackPulse Monitoring Task
After=network.target docker.service
Requires=docker.service

[Service]
Type=oneshot
ExecStart=$BINARY_PATH -t "1 minute ago"
StandardOutput=append:$LOG_FILE
StandardError=append:$LOG_FILE
User=root

[Install]
WantedBy=multi-user.target
EOF

        cat << EOF | tee /etc/systemd/system/stackpulse.timer >/dev/null
[Unit]
Description=Run StackPulse every minute

[Timer]
OnBootSec=1min
OnUnitActiveSec=1min
Unit=stackpulse.service

[Install]
WantedBy=timers.target
EOF

        systemctl daemon-reload
        systemctl enable --now stackpulse.timer >/dev/null 2>&1
        print_done
    else
        printf "${YELLOW}[ SKIPPED ]${RESET}\n"
        printf "     ${DIM}Note: No Systemd detected. Background task disabled.${RESET}\n"
    fi
else
    # macOS LaunchAgent
    USER_HOME=$(eval echo "~$REAL_USER")
    PLIST="$USER_HOME/Library/LaunchAgents/com.stackpulse.monitor.plist"
    cat << EOF | tee "$PLIST" >/dev/null
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.stackpulse.monitor</string>
  <key>ProgramArguments</key><array><string>$BINARY_PATH</string><string>-t</string><string>1 minute ago</string></array>
  <key>StartInterval</key><integer>60</integer>
  <key>RunAtLoad</key><true/>
</dict></plist>
EOF
    chown "$REAL_USER" "$PLIST"
    sudo -u "$REAL_USER" launchctl load "$PLIST" >/dev/null 2>&1
    print_done
fi




# ============================================================
# Final Success Summary
# ============================================================
printf "  ${DIM}────────────────────────────────────────────────────────────${RESET}\n"
printf "\n  ${SUCCESS}  ${BOLD}Installation Complete!${RESET}\n"

if [[ "$PLATFORM" == "linux" ]] && ! id -nG "$REAL_USER" | grep -qw docker; then
    printf "\n  ${YELLOW}ℹ  Permissions Notice:${RESET}\n"
    printf "     User added to 'docker' group, but session is not yet active.\n"
    printf "     ${DIM}Note: StackPulse CLI has built-in sudo-fallback for now.${RESET}\n"
fi

printf "\n  ${BOLD}Access Points:${RESET}\n"
printf "  ● Binary   ${DIM}%s${RESET}\n" "$BINARY_PATH"
printf "  ● Logs     ${DIM}%s${RESET}\n" "$LOG_FILE"

printf "\n  ${BOLD}Next Steps:${RESET}\n"
printf "  1. Finalize:  ${DIM}Log out and back in (only required if this is your first Docker setup).${RESET}\n"
printf "  2. Get Started: Run '${CYAN}${BOLD}stackpulse --help${RESET}' to see available commands.\n\n"