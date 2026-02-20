#!/bin/bash

# ----------------------------------
# OS Detection & Global Setup
# ----------------------------------
OS="$(uname)"
RESET="\033[0m"
BOLD="\033[1m"
DIM="\033[2m"
CYAN="\033[36m"
YELLOW="\033[33m"
RED="\033[31m"
HEADER_COLOR="\033[36m" 

format_table() {
    local max_col_width="$1"
    awk -v COLOR="$HEADER_COLOR" -v BOLD='\033[1m' -v RESET='\033[0m' -v MAX_WIDTH="$max_col_width" '
    function print_horiz_line(corner, tee, dash,    i) {
        printf corner
        for (i=1; i<=NF; i++) {
            printf "%s", repeat(dash, widths[i] + 2)
            printf (i==NF) ? corner : tee
        }
        printf "\n"
    }
    function repeat(str, n,    result, i) {
        result = ""
        for (i = 0; i < n; i++) { result = result str }
        return result
    }
    function truncate(str, width) {
        gsub(/^[ \t]+|[ \t]+$/, "", str)
        if (length(str) <= width) return str
        return substr(str, 1, width - 3) "..."
    }
    BEGIN {
        FS="\t"; OFS="|"
        if (MAX_WIDTH == "") MAX_WIDTH = 25
    }
    NR==1 {
        for (i=1; i<=NF; i++) {
            gsub(/^[ \t]+|[ \t]+$/, "", $i)
            widths[i] = length($i)
        }
        header = $0; next
    }
    /^$/ {next}
    {
        for (i=1; i<=NF; i++) {
            gsub(/^[ \t]+|[ \t]+$/, "", $i)
            if (length($i) > widths[i]) {
                widths[i] = (length($i) > MAX_WIDTH) ? MAX_WIDTH : length($i)
            }
        }
        rows[++datarows] = $0
    }
    END {
        if (datarows == 0) { exit }
        print_horiz_line("+", "+", "-")
        split(header, header_fields)
        printf "|"
        for (i=1; i<=NF; i++) {
            printf " %s%s%-*s%s |", COLOR, BOLD, widths[i], truncate(header_fields[i], widths[i]), RESET
        }
        printf "\n"
        print_horiz_line("+", "+", "-")
        for (row=1; row<=datarows; row++) {
            split(rows[row], fields)
            printf "|"
            for (i=1; i<=NF; i++) { printf " %-*s |", widths[i], truncate(fields[i], widths[i]) }
            printf "\n"
        }
        print_horiz_line("+", "+", "-")
    }
    '
}

# ----------------------------------
# Core Logic Functions
# ----------------------------------

get_ports() {
    local target_port=$1
    if [ "$OS" = "Linux" ]; then
        ( 
          printf "Port\tProto\tBind\tScope\tUser\tPID\tProcess\tState\n"
          sudo ss -tulpn | grep -E "LISTEN|UNCONN" | awk -v target="$target_port" '
          NR > 1 {
              proto = ($1 ~ "tcp") ? "tcp" : "udp";
              split($5, addr, ":"); p = addr[length(addr)];
              if (target != "" && p != target) next;
              bind = addr[1]; for(i=2; i<length(addr); i++) bind = bind ":" addr[i];
              if (bind == "*" || bind == "") bind = "0.0.0.0";
              gsub(/%.*/, "", bind); clean_bind = bind; gsub(/^\[|\]$/, "", clean_bind);
              scope = (clean_bind ~ /^127\./ || clean_bind == "::1" || clean_bind == "localhost") ? "Local" : (clean_bind ~ /^10\./ || clean_bind ~ /^192\.168\./ || clean_bind ~ /^172\.(1[6-9]|2[0-9]|3[0-1])\./) ? "Private" : "Public";
              user = "N/A"; pid = "N/A"; proc = "N/A";
              if (match($0, /users:\(\("([^"]+)",pid=([0-9]+)/, arr)) {
                  proc = arr[1]; pid = arr[2];
                  "ps -o user= -p " pid | getline user; close("ps -o user= -p " pid);
              }
              printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", p, proto, bind, scope, user, pid, proc, $2
          }' | sort -n -k1,1 -k2,2
        ) | format_table 22
    fi
}

get_docker_info() {
    local target=$1
    local DOCKER_CMD="docker"
    ! docker ps >/dev/null 2>&1 && DOCKER_CMD="sudo docker"

    if [ -z "$target" ]; then
        ( echo -e "ID\tType\tName/Repo\tCreated/Status"
          $DOCKER_CMD images --format "{{.ID}}\tImage\t{{.Repository}}\t{{.CreatedAt}}"
          $DOCKER_CMD ps -a --format "{{.ID}}\tContainer\t{{.Names}}\t{{.Status}}" ) | format_table 30
    else
        local raw_data=$($DOCKER_CMD ps -a --format "{{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" | grep -E "$target" | head -n 1)
        if [ -z "$raw_data" ]; then
            local img_data=$($DOCKER_CMD images --format "{{.ID}}\t{{.Repository}}\t{{.Tag}}\t{{.Size}}" | grep -E "$target" | head -n 1)
            if [ -n "$img_data" ]; then
                printf "\n${YELLOW}${BOLD}Storage Context (Image Match):${RESET}\n"
                ( echo -e "ID\tRepository\tTag\tDisk Size" ; echo "$img_data" ) | format_table 30
                return
            fi
            echo -e "  ${RED}❌ Error:${RESET} No container or image matching '$target'"
            return
        fi
        id=$(echo "$raw_data" | cut -f1); name=$(echo "$raw_data" | cut -f2); image=$(echo "$raw_data" | cut -f3); status_raw=$(echo "$raw_data" | cut -f4)
        ports=$(echo "$raw_data" | cut -f5); [ -z "$ports" ] && ports="None"
        network=$($DOCKER_CMD inspect "$id" --format '{{range .NetworkSettings.Networks}}{{.NetworkID}}{{end}}' | cut -c1-12)
        [ -z "$network" ] && network="Bridge"
        if [[ "$status_raw" =~ ^Up ]]; then
            status="Up"; uptime=$(echo "$status_raw" | awk '{print $2$3}' | sed 's/minutes/m/;s/hours/h/;s/seconds/s/')
            stats_raw=$($DOCKER_CMD stats "$id" --no-stream --format "{{.CPUPerc}}\t{{.MemPerc}}" 2>/dev/null || echo -e "0.00%\t0.00%")
            stats="CPU: $(echo "$stats_raw" | cut -f1); MEM: $(echo "$stats_raw" | cut -f2)"
        else
            status="Exited"; uptime=$(echo "$status_raw" | awk '{print $(NF-2)$(NF-1)}' | sed 's/minutes/m/;s/hours/h/'); stats="N/A (Stopped)"
        fi
        ( echo -e "ID\tName\tImage\tStatus\tPorts\tNetwork\tUptime\tStats"
          echo -e "$id\t$name\t$image\t$status\t$ports\t$network\t$uptime\t$stats" ) | format_table 50
    fi
}

get_user_info() {
    local target_user="${1:-}"
    if [[ "$OS" == "Darwin" ]]; then
        ( printf "User\tUID\tHome\tShell\tLast Login\n"
        dscl . -list /Users UniqueID | while read user uid; do
            if [[ "$target_user" != "all" && "$target_user" != "" ]]; then [[ "$user" != *"$target_user"* ]] && continue; fi
            if [[ "$target_user" == "" && "$uid" -lt 500 && "$user" != "root" ]]; then continue; fi
            home=$(dscl . -read "/Users/$user" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
            shell=$(dscl . -read "/Users/$user" UserShell 2>/dev/null | awk '{print $2}')
            last=$(lastlog -u "$user" 2>/dev/null | tail -n 1 | awk '{print $4,$5,$6}' | grep -v "Never" || echo "")
            printf "%s\t%s\t%s\t%s\t%s\n" "$user" "$uid" "$home" "$shell" "$last"
        done ) | format_table 30
    else
        ( printf "User\tType\tUID\tGroup\tHome\tLast Login\tSudo\n"
        local sudo_users=$(grep -Po '^sudo:.*:\K.*' /etc/group | tr ',' '|')
        awk -F: -v u="$target_user" -v sudo_list="$sudo_users" '
        BEGIN { while ("lastlog" | getline > 0) { if ($0 ~ /Never logged in/) continue; n=split($0, a, " "); logins[a[1]] = a[n-4] "-" a[n-3] "-" a[n] } }
        { is_root = ($3 == 0); is_human = ($3 >= 1000 && $3 < 60000 && $1 != "nobody"); is_service = !is_human && !is_root
          g_total++; if (is_human || is_root) { g_real++ } else { g_system++ }
          show = 0; if (u == "all" || u == "--all") { show = 1 } else if (u != "" && $1 ~ u) { show = 1 } else if (u == "" && (is_human || is_root)) { show = 1 }
          if (show) { last = (logins[$1] ? logins[$1] : "Never"); s_access = ($1 ~ "^(" sudo_list ")$" || $1 == "root" ? "Yes" : "No")
                type = (is_root ? "Root" : (is_service ? "Service" : "Human")); cmd = "id -gn " $1 " 2>/dev/null";
                if ((cmd | getline grp) <= 0) { grp = "N/A" }; close(cmd)
                printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n", $1, type, $3, grp, $6, last, s_access
          } }
        END { if (u == "all" || u == "--all" || u == "") { print "---" > "/tmp/sp_counts"
                printf "Total Users:     %d\n", g_total > "/tmp/sp_counts"
                printf "Real Users:      %d\n", g_real > "/tmp/sp_counts"
                printf "System Accounts: %d\n", g_system > "/tmp/sp_counts" } }' /etc/passwd ) | format_table 30
        if [ -f /tmp/sp_counts ]; then cat /tmp/sp_counts && rm /tmp/sp_counts; fi
    fi
}



time_range_activity() {
    local start="$1"

    if [ -z "$start" ]; then
        echo -e "\n  ${YELLOW}${BOLD}ℹ  StackPulse Log Guide${RESET}"
        echo -e "     Please provide a time range argument to audit system events."
        echo -e "     ${DIM}──────────────────────────────────────────────────${RESET}"
        echo -e "     ${BOLD}Examples:${RESET}"
        echo -e "     - ${CYAN}stackpulse -t \"1 minute ago\"${RESET}"
        echo -e "     - ${CYAN}stackpulse -t \"1 hour ago\"${RESET}"
        echo -e "     - ${CYAN}stackpulse -t \"yesterday\"${RESET}"
        echo -e "     - ${CYAN}stackpulse -t \"2026-02-20\"${RESET}"
        echo -e "     ${DIM}──────────────────────────────────────────────────${RESET}\n"
        return
    fi

    (
    printf "Timestamp\tUser\tProcess\tMessage\n"
    
    sudo journalctl --since="$start" --no-pager -n 50 2>/dev/null | awk '
    NR > 1 {
        # 1. Capture Alert/Auth Flags
        is_error = ($0 ~ /[Ee]rror|[Ff]ail|[Cc]ritical|[Aa]lert/);
        is_auth = ($0 ~ /session opened|session closed|Accepted password/);
        total++; if (is_error) { errors++ } if (is_auth) { sessions++ }

        # 2. Extract Basic Metadata
        ts = $1 " " $2 " " $3;
        proc = $5; sub(/:$/, "", proc);
        if (proc == "") { proc = $4; sub(/:$/, "", proc); }
        
        # 3. PRECISION SLICE: Find the content AFTER the process name
        # We find the position of the process name
        pos = index($0, proc);
        if (pos > 0) {
            # Slice the string starting exactly after "ProcessName[PID]: "
            # length(proc) + 2 accounts for the colon and the following space
            msg = substr($0, pos + length(proc) + 2);
            # Clean up any remaining leading/trailing spaces
            gsub(/^[ \t]+|[ \t]+$/, "", msg);
        } else {
            msg = $0; # Fallback
        }
        
        # 4. Final Formatting & Truncation
        if (length(msg) > 80) msg = substr(msg, 1, 77) "...";

        printf "%s\t%s\t%s\t%s\n", ts, "root", proc, msg
    }
    END {
        if (total > 0) {
            print "---" > "/tmp/sp_t_counts"
            printf "Total Events:   %d\n", total > "/tmp/sp_t_counts"
            printf "System Alerts:  %d\n", errors > "/tmp/sp_t_counts"
            printf "Auth Sessions:  %d\n", sessions > "/tmp/sp_t_counts"
        }
    }'
    ) | format_table 100

    if [ -f /tmp/sp_t_counts ]; then
        cat /tmp/sp_t_counts && rm /tmp/sp_t_counts
    fi
}



# ----------------------------------
# Main Execution
# ----------------------------------


show_help() {
    cat << EOF

Usage:  stackpulse [OPTIONS] [QUERY/TIME]

A unified audit suite for Ports, Docker, Nginx, and System Logs

Options:
  -p, --port [port]      Audit listening ports (Local vs. Public)
  -d, --docker [id/name] Show container/image dashboard or detail view
  -n, --nginx [query]    List virtual hosts and proxy configurations
  -u, --users [user/all] Audit human users vs. system accounts
  -t, --time [range]     Search system logs (e.g., '1h ago', 'yesterday')
  -h, --help             Show this help menu

Examples:
  stackpulse -p 80
  stackpulse -d my_web_app
  stackpulse -u all
  stackpulse -t "2 hours ago"
  stackpulse -n dev.local

Note: Root privileges (sudo) may be required for Port and Log modules.

EOF
}


case "${1:-}" in
    -p|--port)   get_ports "${2:-}" ;;
    -d|--docker) get_docker_info "${2:-}" ;;
    -n|--nginx)  get_nginx_info "${2:-}" ;;
    -u|--users)  get_user_info "${2:-}" ;;
    -t|--time)   shift; time_range_activity "$*" ;;
    -h|--help)   show_help ;;
    *)           show_help; exit 1 ;;
esac