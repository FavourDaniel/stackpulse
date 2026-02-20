# StackPulse

StackPulse is a cross-platform CLI tool (Linux & macOS) for auditing and monitoring system infrastructure from the terminal.

It provides fast visibility into ports, Docker, Nginx, users, and system activity — all in one command.

## Key Features
- **🔍 Port Discovery**
    StackPulse displays all active ports and associated services. It also provides detailed information about specific ports.
- **🐳 Docker Insights**
    Lists all Docker images with details (repository, tag, image ID, size, creation date), shows all containers (including exited ones), and allows detailed inspection of specific containers or images.
- **🌐 Nginx Mapper**
    Displays all Nginx domains and their corresponding ports and provides configuration details for specific domains.
- **👤 User Audit**
    Lists all system users along with their last login times and provides detailed information about specific users.
- **⏱️ Activity Logs**
    Allows filtering of activities within a specified time range.
- **🗂️ Log Rotation**
    It implements automatic log rotation using **logrotate** to manage log file sizes efficiently.


## Prerequisites
- Ubuntu 22.04+ (or equivalent Linux distro)
- macOS 12+
- Docker & Nginx (auto-checked during install)


## Installation
StackPulse uses a platform-aware installer that registers background monitoring tasks specific to your OS (systemd for Linux or LaunchAgents for Mac).

1. **Clone the Repository and make the installer executable**
```bash
git clone https://github.com/FavourDaniel/stackpulse.git
cd stackpulse
chmod +x install.sh
```

2. **Run the installer**
- On macOS: 
```bash
./install.sh
```
- On Linux: 
```bash
sudo ./install.sh
```

## Usage Guide
```bash
stackpulse [OPTION] [argument]
```

| Option         | Argument               | Description                                         |
| -------------- | ---------------------- | --------------------------------------------------- |
| `-p, --port`   | `[PORT]`               | Audit listening ports (Local vs. Public).           |
| `-d, --docker` | `[CONTAINER ID/NAME]`  | Show container status and live resource usage.      |
| `-n, --nginx`  | `[DOMAIN]`             | List virtual hosts and proxy configurations.        |
| `-u, --users`  | `[USER]`               | Audit human users vs. system accounts.              |
| `-t, --time`   | `[range]`              | Search system logs (e.g., '1h ago', 'yesterday').   |
| `-h, --help`   | `None`                 | Display the usage guide.                            |


## Examples

### 1. Help
```bash
stackpulse -h
stackpulse --help
```
This displays the help menu with usage instructions and available options.

### 2. Port Information
```bash
stackpulse -p
stackpulse -p [PORT]
stackpulse --port [PORT]
```
This displays information about the specified port (e.g., `8080`).
If no port is specified, it shows all active listening ports and associated services.

### 3. Docker Information
```bash
stackpulse -d
stackpulse -d [CONTAINER ID/NAME]
stackpulse --docker [CONTAINER ID/NAME]
```
This displays information about the specified Docker container.
If no container is specified, it shows all containers and Docker images.

### 4. Nginx Information
```bash
stackpulse -n
stackpulse -n [DOMAIN]
stackpulse --nginx [DOMAIN]
```
This displays Nginx configuration details for the specified domain.
If no domain is specified, it shows all configured virtual hosts and mapped ports.

### 5. User Information
```bash
stackpulse -u
stackpulse -u [USER]
stackpulse --users [USER]
stackpulse --users all
```
This displays detailed information about the specified user.
If no user is specified, it shows all regular system users and their last login times.

### 6. Time Range Filtering
```bash
stackpulse -t [DATE or TIME]
stackpulse --time [DATE or TIME]
```

**Examples**:
```bash
stackpulse -t "1 hour ago"
stackpulse -t "yesterday"
stackpulse -t 2026-02-20
```

You can also pipe results:

```bash
stackpulse -t "yesterday" | head
stackpulse -t "1 hour ago" | tail
```

## Background Monitoring & Log Rotation

StackPulse includes an optional 60-second heartbeat service that continuously audits system health.
When enabled, it runs as a background service.

### Linux (systemd)
StackPulse runs using `stackpulse.timer` and `stackpulse.service`.

#### Service Management:
```bash
sudo systemctl start stackpulse.service
sudo systemctl stop stackpulse.service
sudo systemctl status stackpulse.service
sudo systemctl enable stackpulse.service
```
-----
### macOS (launchctl)
StackPulse runs using `com.stackpulse.monitor.plist` LaunchAgent.

#### Service Management:
```bash
launchctl load ~/Library/LaunchAgents/com.stackpulse.monitor.plist
launchctl unload ~/Library/LaunchAgents/com.stackpulse.monitor.plist
launchctl list | grep stackpulse
```

-----
### Log Files

Monitoring output is written to:

- **Linux**: `/var/log/stackpulse.log`
- **macOS**: `~/Library/Logs/stackpulse.log`
-----

### Log Rotation Policy

To prevent uncontrolled log growth, StackPulse enforces automatic log rotation:

- **Retention**: 7 days
- **Linux**: Uses `logrotate` (daily rotation and compression)
- **macOS**: Uses `newsyslog` (rotates at 1MB)
Old logs beyond the retention window are automatically removed.



## Troubleshooting

If you encounter any issues:

### 1. Check Logs
```bash
#Linux
cat /var/log/stackpulse.log

#macOs
cat ~/Library/Logs/stackpulse.log
```

### 2. Verify permissions
Ensure you have sudo/root access.


### 3. Verify dependencies
Check Docker/Nginx if related modules return empty.
