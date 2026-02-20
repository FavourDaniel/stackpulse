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

elif [ "$OS" = "Darwin" ]; then
        # --- NEW MACOS LOGIC ---
        (
          printf "Port\tProto\tBind\tScope\tUser\tPID\tProcess\tState\n"
          # Standardizing lsof output to ensure we capture all active sockets
          sudo lsof -i -P -n | grep -Ei "LISTEN|UDP|ESTABLISHED" | awk -v target="$target_port" '
          {
              # macOS lsof output: $9 is NAME (e.g., 127.0.0.1:5007 or *:80)
              split($9, addr, ":"); 
              p = addr[length(addr)];
              
              # Handle cases where lsof shows "*" for the port
              if (p == "*") p = "0";

              # Filter by target port if provided
              if (target != "" && p != target) next;
              
              proto = tolower($8);
              bind = addr[1]; 
              gsub(/\*/, "0.0.0.0", bind);
              
              # Scope Logic matching your Linux style
              clean_bind = bind;
              scope = (clean_bind ~ /^127\./ || clean_bind == "::1" || clean_bind == "localhost" || clean_bind == "[::1]") ? "Local" : (clean_bind ~ /^10\./ || clean_bind ~ /^192\.168\./ || clean_bind ~ /^172\.(1[6-9]|2[0-9]|3[0-1])\./) ? "Private" : "Public";
              
              user = $3;
              pid = $2;
              proc = $1;
              
              # Improved state detection for macOS
              state = "N/A";
              if ($0 ~ /LISTEN/) state = "LISTEN";
              else if (proto ~ /udp/) state = "UNCONN";
              else if ($0 ~ /ESTABLISHED/) state = "ESTAB";
              
              printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", p, proto, bind, scope, user, pid, proc, state
          }' | sort -nu -k1,1
        ) | format_table 22
    fi
}




get_nginx_info() {
    local query="${1:-}"
    local conf_dir="/etc/nginx"
    [[ "$OS" == "Darwin" ]] && conf_dir="/opt/homebrew/etc/nginx"
    
    if [[ ! -d "$conf_dir" ]]; then
        echo -e "  ${RED}❌ Error:${RESET} Nginx directory not found."
        return
    fi

    local exclude_pattern="--exclude=fastcgi_params --exclude=mime.types --exclude=koi-win --exclude=koi-utf --exclude=win-utf --exclude=*.default"

    if [[ -z "$query" ]]; then
        # --- DASHBOARD VIEW ---
        (
            printf "Server Name\tProxy Pass\tPort\tConfig Path\n"
            local files=$(sudo grep -rl "listen" "$conf_dir" $exclude_pattern --include="*.conf" --include="nginx.conf" --include="default" 2>/dev/null || true)
            
            for f in $files; do
                # Strip comments and capture content
                local active_lines=$(grep -v "^[ \t]*#" "$f")
                
                # 1. Port extraction
                local p_port=$(echo "$active_lines" | grep -w "listen" | head -n1 | awk '{print $2}' | tr -d ';' | sed 's/.*://')
                [[ -z "$p_port" ]] && p_port="80"
                
                # 2. Server Name (Hardened regex: grep -w ensures we dont catch server_names_hash_...)
                local s_name=$(echo "$active_lines" | grep -w "server_name" | head -n1 | awk '{print $2}' | tr -d ';')
                [[ -z "$s_name" ]] && s_name="localhost"
                
                # 3. Proxy/Static extraction
                local s_proxy=$(echo "$active_lines" | grep -w "proxy_pass" | head -n1 | awk '{print $2}' | tr -d ';')
                local s_root=$(echo "$active_lines" | grep -w "root" | head -n1 | awk '{print $2}' | tr -d ';')
                
                local p_pass="static:default"
                if [[ -n "$s_proxy" ]]; then p_pass="proxy:$s_proxy"
                elif [[ -n "$s_root" ]]; then p_pass="static:$s_root"
                fi
                
                printf "%s\t%s\t%s\t%s\n" "$s_name" "$p_pass" "$p_port" "$f"
            done
        ) | sort -u | format_table 60
    else
        # --- DETAIL VIEW ---
        # Find the file, ensuring we match the exact word server_name
        local target_conf=""
        if [[ "$query" == "default" || "$query" == "localhost" || "$query" == "_" ]]; then
            target_conf=$(sudo grep -l "listen" "$conf_dir/sites-available/default" 2>/dev/null || sudo grep -rl "listen" "$conf_dir" $exclude_pattern | head -n 1)
        else
            target_conf=$(sudo grep -rlw "server_name" "$conf_dir" $exclude_pattern | xargs grep -l "$query" | head -n 1)
        fi
        
        if [[ -z "$target_conf" ]]; then
            echo -e "  ${RED}❌ Error:${RESET} No configuration found matching '$query'"
            return
        fi

        local active_content=$(grep -v '^[[:space:]]*#' "$target_conf")
        local mode="Static"; echo "$active_content" | grep -qw "proxy_pass" && mode="Proxy"
        local backend=$(echo "$active_content" | grep -Ew "proxy_pass|root" | head -n 1 | awk '{print $2}' | tr -d ';')
        local listen_port=$(echo "$active_content" | grep -w "listen" | head -n 1 | awk '{print $2}' | tr -d ';' | sed 's/.*://')

        # --- SAFE LOG DISCOVERY ---
        local access_log=$(echo "$active_content" | grep -w "access_log" | head -n 1 | awk '{print $2}' | tr -d ';')
        [[ -z "$access_log" ]] && access_log=$(sudo grep -w "access_log" "$conf_dir/nginx.conf" | grep -v "#" | head -n 1 | awk '{print $2}' | tr -d ';' 2>/dev/null)
        
        if [[ -z "$access_log" || "$access_log" == "off" || "$access_log" == "logs/"* ]]; then
            if [[ "$OS" == "Darwin" ]]; then
                access_log="/opt/homebrew/var/log/nginx/access.log"
            else
                access_log="/var/log/nginx/access.log"
            fi
        fi

        local reach="N/A"
        if [[ "$mode" == "Proxy" ]]; then
            curl -Is --connect-timeout 2 "$(echo "$backend" | sed 's/\$host/127.0.0.1/')" >/dev/null 2>&1 && reach="Healthy" || reach="Unreachable"
        fi

        local tls="None"; echo "$active_content" | grep -qE "ssl|443" && tls="Active"
        local test_res=$(sudo nginx -t 2>&1 | grep -q "successful" && echo "Valid" || echo "Invalid")

        printf "\n${CYAN}${BOLD}Detailed Audit: $query${RESET}\n"
        (
            printf "Property\tValue\n"
            printf "Mode\t%s\n" "$mode"
            printf "Root/Backend\t%s\n" "$backend"
            printf "Port(s)\t%s\n" "$listen_port"
            printf "TLS Status\t%s\n" "$tls"
            printf "Reachability\t%s\n" "$reach"
            printf "Config File\t%s\n" "$target_conf"
            printf "Test Result\t%s\n" "$test_res"
            printf "Access Log\t%s\n" "$access_log"
        ) | format_table 80
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
        # Global counters (outside subshell)
        local g_total=0 g_real=0 g_system=0
        local tmp_file="/tmp/sp_mac_counts"
        
        (
          printf "User\tType\tUID\tGroup\tHome\tLast Login\tSudo\n"
          
          local sudo_list=$(dscl . -read /Groups/admin GroupMembership 2>/dev/null | cut -d: -f2)
          local t=0 r=0 s=0

          while read -r user uid; do
              # Type Logic (0=Root, 501-1000=Human, others=Service)
              local is_root=0; local is_human=0; local is_service=0;
              [[ "$uid" -eq 0 ]] && is_root=1
              [[ "$uid" -ge 501 && "$uid" -lt 1000 ]] && is_human=1
              [[ $is_root -eq 0 && $is_human -eq 0 ]] && is_service=1
              
              ((t++))
              if [[ $is_human -eq 1 || $is_root -eq 1 ]]; then ((r++)); else ((s++)); fi
              echo "$t:$r:$s" > "$tmp_file"

              # Filtering Logic
              local show=0
              if [[ "$target_user" == "all" ]]; then show=1
              elif [[ -n "$target_user" && "$user" == "$target_user" ]]; then show=1
              elif [[ -z "$target_user" && ($is_human -eq 1 || $is_root -eq 1) ]]; then show=1
              fi

              if [[ $show -eq 1 ]]; then
                  type=$( [[ $is_root -eq 1 ]] && echo "Root" || ([[ $is_service -eq 1 ]] && echo "Service" || echo "Human") )
                  home=$(dscl . -read "/Users/$user" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
                  grp=$(id -gn "$user" 2>/dev/null || echo "N/A")
                  s_access="No"; [[ " $sudo_list " == *" $user "* || "$user" == "root" ]] && s_access="Yes"
                  
                  # Last Login Formatting (Translates 'Feb 20 14:18' to 'Feb-20-2026')
                  last_raw=$(last -1 -t console "$user" | head -n1 | awk '{print $4,$5}')
                  if [[ -n "$last_raw" && "$last_raw" != "wtmp"* ]]; then
                      last=$(echo "$last_raw" | awk '{printf "%s-%s-%s", $1, $2, "2026"}')
                  else
                      last="Never"
                  fi
                  
                  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "$user" "$type" "$uid" "$grp" "$home" "$last" "$s_access"
              fi
          done < <(dscl . -list /Users UniqueID)
        ) | format_table 30

        # Output summary only for 'all' or default audit
        if [[ "$target_user" == "all" || "$target_user" == "" ]]; then
            if [ -f "$tmp_file" ]; then
                IFS=':' read -r total real system < "$tmp_file"
                printf -- "---\n"
                printf "Total Users:     %d\n" "$total"
                printf "Real Users:      %d\n" "$real"
                printf "System Accounts: %d\n" "$system"
                rm -f "$tmp_file"
            fi
        fi

    else
        # --- LINUX LOGIC (UNTOUCHED) ---
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
    local current_os=$(uname -s)

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

    # 1. COLLISION-PROOF TEMP FILES
    local raw_logs=$(mktemp /tmp/sp_raw_XXXXXX)
    local clean_logs=$(mktemp /tmp/sp_clean_XXXXXX)

    if [[ "$current_os" == "Darwin" ]]; then
        # --- MACOS LOGIC ---
        local predicate="--predicate 'eventType == logEvent'"
        
        if [[ "$start" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
            LOG_CMD="sudo log show --start \"$start 00:00:00\" $predicate"
        else
            local mac_flag="1h" 
            case "$start" in
                "1 minute ago")                          mac_flag="1m"  ;;
                "5 minute ago"|"5 minutes ago")          mac_flag="5m"  ;;
                "30 minute ago"|"30 minutes ago")        mac_flag="30m" ;;
                "1 hour ago")                            mac_flag="1h"  ;;
                "yesterday")                             mac_flag="24h" ;; 
            esac
            LOG_CMD="sudo log show --last $mac_flag $predicate"
        fi
    else
        # --- LINUX LOGIC ---
        LOG_CMD="sudo journalctl --since=\"$start\" --no-pager"
    fi

    printf "  ${CYAN}⏳ Scanning log database for '%s' (this may take a moment)...${RESET}\r" "$start" >&2

    # 2. FETCH & PURIFY LOGS
    eval "$LOG_CMD 2>/dev/null" | tail -n 100 > "$raw_logs"
    grep -E "^[A-Z][a-z]{2} |^[0-9]{4}-" "$raw_logs" > "$clean_logs" 2>/dev/null

    printf "                                                                                \r" >&2

    if [ ! -s "$clean_logs" ]; then
        echo -e "  ${YELLOW}⚠  Notice:${RESET} No system events found for '$start'. The log window is empty."
        rm -f "$raw_logs" "$clean_logs"
        return
    fi

    # 3. EXACT COLUMN PARSING
    (
    printf "Timestamp\tUser\tProcess\tMessage\n"
    
    cat "$clean_logs" | awk -v os="$current_os" '
    {
        ts = ""; proc = ""; msg = "";
        
        if (os == "Darwin") {
            if (NF < 8) next; 
            ts = $1 " " substr($2, 1, 8);
            proc = $8; sub(/:$/, "", proc);
            for(i=9; i<=NF; i++) msg = msg $i " ";
        } else {
            ts = $1 " " $2 " " $3;
            proc = $5; sub(/:$/, "", proc);
            if (proc == "") { proc = $4; sub(/:$/, "", proc); }
            pos = index($0, proc);
            msg = (pos > 0) ? substr($0, pos + length(proc) + 2) : $0;
        }

        sub(/^[ \t]+/, "", msg);
        if (length(msg) > 75) msg = substr(msg, 1, 72) "...";
        
        if (msg != "" && proc != "") {
            total++;
            if (msg ~ /[Ee]rror|[Ff]ail|[Cc]ritical|[Aa]lert|[Ff]ault/) errors++;
            if (msg ~ /session opened|session closed|Accepted password/) sessions++;
            printf "%s\t%s\t%s\t%s\n", ts, "root", proc, msg
        }
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
    
    # 4. CLEANUP
    rm -f "$raw_logs" "$clean_logs"
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
  -u, --user  [user/all] Audit human users vs. system accounts
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
    -p|--port)            get_ports "${2:-}" ;;
    -d|--docker)          get_docker_info "${2:-}" ;;
    -n|--nginx)           get_nginx_info "${2:-}" ;;
    -u|--user| --users)   get_user_info "${2:-}" ;;
    -t|--time)            shift; time_range_activity "$*" ;;
    -h|--help)            show_help ;;
    *)                    show_help; exit 1 ;;
esac