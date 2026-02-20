#!/bin/bash

# ----------------------------------
# OS Detection & Global Setup
# ----------------------------------
OS="$(uname)"

# Centralized Color Definitions
RESET="\033[0m"
BOLD="\033[1m"
GRAY="\033[90m"
HEADER_COLOR="\033[36m" 

# ----------------------------------
# Table Formatter Engine
# ----------------------------------
format_table() {
    local default_width="$1"
    awk -v COLOR="$HEADER_COLOR" -v BOLD='\033[1m' -v RESET='\033[0m' -v DEFAULT_WIDTH="$default_width" '
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
        if (DEFAULT_WIDTH == "") DEFAULT_WIDTH = 25
    }
    NR==1 {
        for (i=1; i<=NF; i++) {
            gsub(/^[ \t]+|[ \t]+$/, "", $i)
            widths[i] = length($i) > DEFAULT_WIDTH ? DEFAULT_WIDTH : length($i)
        }
        header = $0; next
    }
    /^$/ {next}
    {
        for (i=1; i<=NF; i++) {
            gsub(/^[ \t]+|[ \t]+$/, "", $i)
            if (length($i) > widths[i]) {
                widths[i] = (length($i) > DEFAULT_WIDTH) ? DEFAULT_WIDTH : length($i)
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
          # 1. Gather raw data and normalize formatting
          raw_data=$(sudo ss -tulpn | grep -E "LISTEN|UNCONN" | awk -v target="$target_port" '
          NR > 1 {
              # Extract Protocol (tcp/udp)
              proto = ($1 ~ "tcp") ? "tcp" : "udp";

              split($5, addr, ":");
              p = addr[length(addr)];
              if (target != "" && p != target) next;

              # Rebuild Bind Address
              bind = addr[1];
              for(i=2; i<length(addr); i++) bind = bind ":" addr[i];
              if (bind == "*" || bind == "") bind = "0.0.0.0";

              # Normalize Bind (Remove interface suffixes and IPv6 brackets)
              gsub(/%.*/, "", bind);
              clean_bind = bind;
              gsub(/^\[|\]$/, "", clean_bind);

              # Scope Logic
              scope = "Public";
              if (clean_bind ~ /^127\./ || clean_bind == "::1" || clean_bind == "localhost") {
                  scope = "Local";
              } else if (clean_bind ~ /^10\./ || clean_bind ~ /^192\.168\./ || clean_bind ~ /^172\.(1[6-9]|2[0-9]|3[0-1])\./) {
                  scope = "Private";
              }

              # Process Metadata
              user = "N/A"; pid = "N/A"; proc = "N/A"; notes = "-";
              if (match($0, /users:\(\("([^"]+)",pid=([0-9]+)/, arr)) {
                  proc = arr[1]; pid = arr[2];
                  "ps -o user= -p " pid | getline user; close("ps -o user= -p " pid);
              }
              
              # Security Heuristics
              if (scope == "Public") {
                  if (p ~ /^(3306|6379|5432|27017|9200)$/) notes = "⚠ Exposed DB";
                  else if (user == "root" && p != "22") notes = "⚠ Root-Owned Pub";
              }

              printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", p, proto, bind, scope, user, pid, proc, $2, notes
          }' | sort -n -k1,1 -k2,2)

          # --- Dynamic UI Logic ---
          if echo "$raw_data" | grep -q "⚠"; then
              printf "Port\tProto\tBind\tScope\tUser\tPID\tProcess\tState\tNotes\n"
              echo "$raw_data"
          else
              printf "Port\tProto\tBind\tScope\tUser\tPID\tProcess\tState\n"
              echo "$raw_data" | cut -f1-8
          fi
        ) | format_table 22
    else
        # --- MAC SECTION: UNTOUCHED ---
        ( echo -e "Port\tUser\tPID\tType\tState"
          sudo lsof -nP -i -sTCP:LISTEN | grep "${target_port:+:$target_port}" | awk 'NR>1 {
              split($9, a, ":"); p=a[length(a)]; 
              print p "\t" $3 "\t" $2 "\t" tolower($8) "\t" "(" $10 ")"
          }' | sort -u ) | format_table
    fi
}




get_docker_info() {
    local container=$1
    local DOCKER_CMD="docker"

    # Transparent Permission Check: If standard access fails, try sudo.
    if ! docker ps >/dev/null 2>&1; then
        DOCKER_CMD="sudo docker"
    fi

    if [ -n "$container" ]; then
        ( echo -e "ID\tName\tStatus\tStats"
          $DOCKER_CMD ps -a --filter "name=$container" --format "{{.ID}}\t{{.Names}}\t{{.Status}}" | while read line; do
              stats=$($DOCKER_CMD stats $container --no-stream --format "CPU: {{.CPUPerc}}; MEM: {{.MemPerc}}")
              echo -e "${line}\t${stats}"
          done ) | format_table 40
    else
        ( echo -e "ID\tType\tName\tCreated"
          $DOCKER_CMD images -a --format "{{.ID}}\tImage\t{{.Repository}}\t{{.CreatedAt}}"
          $DOCKER_CMD ps -a --format "{{.ID}}\tContainer\t{{.Names}}\t{{.CreatedAt}}" ) | format_table 30
    fi
}



get_nginx_info() {
    local search_name="$1"
    local nginx_cmd
    
    # 1. FIXED: Correct Binary Fallback Logic
    nginx_cmd=$(command -v nginx)
    [ -z "$nginx_cmd" ] && [ -x /opt/homebrew/bin/nginx ] && nginx_cmd="/opt/homebrew/bin/nginx"
    [ -z "$nginx_cmd" ] && [ -x /usr/local/bin/nginx ] && nginx_cmd="/usr/local/bin/nginx"

    if [ ! -x "$nginx_cmd" ]; then
        echo -e "  ${RED}❌ Error:${RESET} Nginx binary not found."
        return
    fi

    # Global syntax check
    local syntax_check
    sudo "$nginx_cmd" -t >/dev/null 2>&1 && syntax_check="Active" || syntax_check="Error"

    (
    printf "Server Name\tPort\tStatus\tProxy Pass\tConfig Path\n"

    sudo "$nginx_cmd" -T 2>/dev/null | awk -v search="$search_name" -v status="$syntax_check" '
    # Track the current configuration file
    /configuration file / {
        current_file = $NF;
        gsub(/:$/, "", current_file);
    }
    
    # Ignore comments
    /^[ \t]*#/ { next }

    # Handle block contexts
    /[ \t]*server[ \t]*\{/ { 
        in_server = 1; 
        current_port = "80"; 
        current_proxy = "None";
        s_names = ""; 
    }
    
    in_server && /[ \t]*location.*\{/ { in_location = 1 }
    
    /^[ \t]*\}/ { 
        if (in_location) {
            in_location = 0; 
        } else if (in_server) {
            # 2. FIXED: Block-End Print Logic
            if (s_names != "") {
                split(s_names, names, " ");
                for (i in names) {
                    if (names[i] != "" && (search == "" || names[i] ~ search)) {
                        printf "%s\t%s\t%s\t%s\t%s\n", names[i], current_port, status, current_proxy, current_file
                    }
                }
            }
            in_server = 0; s_names = ""; current_proxy = "None";
        }
    }

    # 3. FIXED: Improved Port Detection (handles IPs and IPv6)
    in_server && /[ \t]*listen[ \t]+/ {
        line = $0;
        sub(/^[ \t]*listen[ \t]+/, "", line);
        sub(/[ \t]*;.*$/, "", line);
        # Split by colon and take the last part
        split(line, parts, ":");
        p = parts[length(parts)];
        # Remove "ssl", "default_server", etc.
        split(p, clean_p, " ");
        if (clean_p[1] ~ /^[0-9]+$/) current_port = clean_p[1];
    }

    # 4. FIXED: Capture Proxy Pass (List multiple if they exist)
    in_server && /[ \t]*proxy_pass[ \t]+/ {
        p_line = $0;
        sub(/^[ \t]*proxy_pass[ \t]+/, "", p_line);
        sub(/[ \t]*;.*$/, "", p_line);
        if (current_proxy == "None") current_proxy = p_line;
        else current_proxy = current_proxy ", " p_line; # Append multiple
    }

    # 5. FIXED: Append multiple server_name lines instead of overwriting
    in_server && /[ \t]*server_name[ \t]+/ {
        line = $0;
        sub(/^[ \t]*server_name[ \t]+/, "", line);
        sub(/[ \t]*;.*$/, "", line);
        s_names = s_names " " line;
    }
    ' | sort -u
    ) | format_table 60
}



get_user_info() {
    local target_user="$1"
    local second_arg="$2"
    local show_all=false
    
    # Flag parsing
    if [[ "$target_user" == "all" || "$target_user" == "--all" || "$second_arg" == "--all" ]]; then
        show_all=true
        target_user="."
    elif [[ -z "$target_user" ]]; then
        target_user="."
    fi

    (
    # --- [1] HEADER LOGIC ---
    if [[ "$show_all" == "true" || ("$target_user" != "." && "$target_user" != "") ]]; then
        printf "User\tType\tUID\tGroup\tHome\tShell\tLast Login\tSudo\tSessions\n"
    else
        printf "User\tLast Login\tFrom\n"
    fi
    
    if [ "$OS" = "Linux" ]; then
        local sudo_users=$(grep -Po '^sudo:.*:\K.*' /etc/group | tr ',' '|')
        
        # Buffer Active Sessions & robust timestamps from 'who'
        local tmp_sessions="/tmp/sp_sessions"
        who | awk '{
            ip=$5; gsub(/[()]/, "", ip);
            # Convert "who" date to YYYY-MM-DD format
            "date -d \"" $3 " " $4 "\" +\"%Y-%m-%d %H:%M UTC\"" | getline dstr; close("date -d ...");
            print $1 ":" dstr ":" (ip==""?"local":ip)
        }' | sort | awk -F: '{
            count[$1]++; 
            if(!t[$1]){t[$1]=$2; f[$1]=$3}
        } END {for(u in count) print u ":" count[u] ":" t[u] ":" f[u]}' > "$tmp_sessions"

        awk -F: -v u="${target_user:-.}" -v all="$show_all" -v sudo_list="$sudo_users" -v sess_file="$tmp_sessions" '
        BEGIN { 
            # D. Robust lastlog parser
            while ("lastlog" | getline > 0) {
                if ($0 ~ /Username/ || $0 ~ /Never logged in/) continue;
                
                n = split($0, a, " ");
                user = a[1];
                
                # FIXED SYNTAX: Space out concatenation and use explicit variables
                # Rebuilding date: YYYY-Month-Day Time UTC
                if (n >= 4) {
                   y = a[n];
                   m = a[n-4];
                   d = a[n-3];
                   tm = substr(a[n-2], 1, 5);
                   logins[user] = y "-" m "-" d " " tm " UTC";
                }
                
                if (n > 6) froms[user] = a[3];
                else froms[user] = "local";
            }
            close("lastlog");

            while ((getline < sess_file) > 0) {
                split($0, s, ":");
                act_cnt[s[1]]=s[2]; act_time[s[1]]=s[3]; act_from[s[1]]=s[4];
            }
            close(sess_file);
        }

        # Filter & Transformation Logic
        ($1 ~ u) && (all == "true" || u != "." || ($3 >= 1000 && $1 != "nobody")) {
            
            # Login Fallback Logic
            last = logins[$1];
            if (last == "" && act_time[$1] != "") last = act_time[$1];
            if (last == "") last = "Never";

            from = froms[$1];
            if (from == "" || from ~ /tty|pts/) from = (act_from[$1] != "" ? act_from[$1] : "local");
            if (from ~ /^[A-Z][a-z][a-z]$|^[0-9]+$/) from = "local";

            s_access = ($1 ~ "^(" sudo_list ")$" || $1 == "root" ? "Yes" : "No");
            s_count = (act_cnt[$1] ? act_cnt[$1] : "0");
            type = ($3 == 0 ? "Root" : ($3 >= 1000 && $1 != "nobody" ? "Human" : "System"));
            prio = ($3 == 0 ? 0 : ($3 >= 1000 && $1 != "nobody" ? 1 : 2));

            "id -gn " $1 | getline grp; close("id -gn " $1);

            if (all == "true" || (u != "." && u != "")) {
                printf "%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", prio, $1, type, $3, grp, $6, $7, last, s_access, s_count
            } else {
                printf "%d\t%s\t%s\t%s\n", prio, $1, last, from
            }
        }' /etc/passwd | sort -n -t$'\t' -k1,1 -k3,3n | cut -f2-
        
        rm -f "$tmp_sessions"
    fi
    ) | format_table 30

    # --- [2] SYSTEM TOTALS ---
    if [ "$OS" = "Linux" ]; then
        if [[ "$target_user" == "." || "$show_all" == "true" ]]; then
            local real=$(awk -F: '$3 >= 1000 && $1 != "nobody" {c++} END {print c+0}' /etc/passwd)
            local total=$(awk -F: '{c++} END {print c+0}' /etc/passwd)
            printf "\n${BOLD}System Totals:${RESET}\n"
            printf "${GRAY}  Total Accounts:  ${RESET}%s\n" "$total"
            printf "${GRAY}  Real Users:      ${RESET}%s\n" "$real"
            printf "${GRAY}  System Services: ${RESET}%s\n" "$((total - real))"
        fi
    fi
}



time_range_activity() {
    local start="$1"
    local end="$2"
    if [ -z "$start" ]; then echo "Usage: stackpulse -t YYYY-MM-DD"; return; fi
    echo -e "\n--- Activity Log ---"
    local tmp_logs="/tmp/stackpulse_events.txt"
    if [ "$OS" = "Linux" ]; then
        local until_cmd=""
        [ -n "$end" ] && until_cmd="--until=$end"
        sudo journalctl --since="$start" $until_cmd --no-pager -n 50 | \
        awk 'NR>1 {
            ts=$1 " " $2 " " $3; user="root"; proc=$4; sub(/:$/, "", proc);
            msg=$0; sub(/.*: /, "", msg);
            print ts "\t" user "\t" proc "\t" msg
        }' > "$tmp_logs"
    else
        local log_end=""
        [ -n "$end" ] && log_end="--end $end 23:59:59"
        log show --start "$start" $log_end --style syslog --info --last 1h 2>/dev/null | \
        awk 'BEGIN { split("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec", months, " ") }
        /launchd|backupd|loginwindow/ {
            split($1, d, "-"); ts=months[d[2]+0] " " d[3] " " substr($2,1,8);
            print ts "\troot\t"$4"\t"$0
        }' > "$tmp_logs"
    fi
    ( echo -e "Timestamp\tUser\tProcess\tMessage"; cat "$tmp_logs" ) | format_table 80
    rm -f "$tmp_logs"
}

# ----------------------------------
# Main Execution
# ----------------------------------
case "$1" in
    -p|--port)   get_ports "$2" ;;
    -d|--docker) get_docker_info "$2" ;;
    -n|--nginx)  get_nginx_info "$2" ;;
    -u|--users)  get_user_info "$2" "$3" ;;
    -t|--time)   shift; time_range_activity "$1" ;;
    -h|--help)   echo "Use -p, -d, -n, -u, or -t." ;;
    *) echo "Invalid option."; exit 1 ;;
esac