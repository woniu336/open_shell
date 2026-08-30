#!/usr/bin/env bash
set -u

########################################
# NFTables DDNS/URL/IPv4 端口转发管理器
# IPv4-only
########################################

RED='\033[0;31m'
GREEN='\033[0;36m'
BLUE='\033[0;34m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
YELLOW='\033[1;33m'
NC='\033[0m'

RULES_DB='/etc/forward2jp-ddns.rules'
NFT_MANAGED_FILE='/etc/nftables-forward2jp.conf'
NFT_MAIN_FILE='/etc/nftables.conf'
SYSCTL_DROPIN='/etc/sysctl.d/99-forward2jp.conf'
LOCK_FILE='/run/forward2jp-ddns.lock'
SCRIPT_INSTALL_PATH='/usr/local/sbin/nftables.sh'
SERVICE_FILE='/etc/systemd/system/forward2jp-ddns-refresh.service'
TIMER_FILE='/etc/systemd/system/forward2jp-ddns-refresh.timer'
DEFAULT_TIMER_SECONDS='60'

PUBLIC_DNS_SERVERS=("1.1.1.1" "8.8.8.8" "223.5.5.5" "119.29.29.29")

QUIET=0

log() {
    [ "$QUIET" -eq 1 ] && return 0
    echo -e "$*"
}

err() {
    echo -e "${RED}$*${NC}" >&2
}

need_root() {
    if [ "${EUID:-$(id -u)}" -ne 0 ]; then
        err '请使用 root 权限运行此脚本'
        exit 1
    fi
}

pause() {
    [ "$QUIET" -eq 1 ] && return 0
    echo -e "\n${WHITE}按回车键继续...${NC}"
    read -r _ || true
}

clear_screen() {
    [ "$QUIET" -eq 1 ] && return 0
    clear
    echo -e "${CYAN}┌────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│${WHITE}       NFTables DDNS 端口转发管理器      ${CYAN}│${NC}"
    echo -e "${CYAN}└────────────────────────────────────────┘${NC}"
    echo
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

valid_ipv4() {
    local ip="$1"
    local IFS=.
    local a b c d n

    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    read -r a b c d <<< "$ip"

    for n in "$a" "$b" "$c" "$d"; do
        [[ "$n" =~ ^[0-9]+$ ]] || return 1
        [ "$n" -ge 0 ] && [ "$n" -le 255 ] || return 1
    done

    return 0
}

valid_port() {
    [[ "${1:-}" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

normalize_target_host() {
    local input="$1"
    local host

    # 去掉首尾空白
    input="${input#"${input%%[![:space:]]*}"}"
    input="${input%"${input##*[![:space:]]}"}"

    if [ -z "$input" ]; then
        return 1
    fi

    # 如果是 URL，提取 host 部分
    if [[ "$input" =~ ^[a-zA-Z][a-zA-Z0-9+.-]*:// ]]; then
        host="${input#*://}"
        host="${host%%/*}"
        host="${host%%\?*}"
        host="${host%%#*}"
    else
        host="$input"
        host="${host%%/*}"
        host="${host%%\?*}"
        host="${host%%#*}"
    fi

    # 去掉 userinfo
    host="${host##*@}"

    # 去掉 IPv6 方括号；本脚本不支持 IPv6，但这里用于给出更清晰报错
    if [[ "$host" =~ ^\[(.*)\](:[0-9]+)?$ ]]; then
        host="${BASH_REMATCH[1]}"
    else
        # 普通域名:端口，仅去掉最后一个 :port
        if [[ "$host" =~ ^([^:]+):[0-9]+$ ]]; then
            host="${BASH_REMATCH[1]}"
        fi
    fi

    # 去掉末尾点
    host="${host%.}"

    [ -n "$host" ] || return 1
    printf '%s\n' "$host"
}

first_valid_ipv4_from_text() {
    local line token
    while IFS= read -r line; do
        for token in $line; do
            token="${token%,}"
            token="${token%;}"
            token="${token#Address:}"
            if valid_ipv4 "$token"; then
                printf '%s\n' "$token"
                return 0
            fi
        done
    done
    return 1
}

resolve_ipv4() {
    local raw_host="$1"
    local host ip server output

    host=$(normalize_target_host "$raw_host") || return 1

    if valid_ipv4 "$host"; then
        printf '%s\n' "$host"
        return 0
    fi

    # 明显的 IPv6 输入，直接拒绝；本脚本为 IPv4-only。
    if [[ "$host" == *:* ]]; then
        return 1
    fi

    # 1. 系统 resolver：优先使用机器自己的 DNS 设置，适合内网 DNS/DDNS。
    if command_exists getent; then
        ip=$(getent ahostsv4 "$host" 2>/dev/null | awk '{print $1}' | while read -r candidate; do
            if [[ "$candidate" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
                echo "$candidate"
                break
            fi
        done)
        if valid_ipv4 "${ip:-}"; then
            printf '%s\n' "$ip"
            return 0
        fi

        ip=$(getent hosts "$host" 2>/dev/null | awk '{print $1}' | while read -r candidate; do
            if [[ "$candidate" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
                echo "$candidate"
                break
            fi
        done)
        if valid_ipv4 "${ip:-}"; then
            printf '%s\n' "$ip"
            return 0
        fi
    fi

    # 2. dig：如果本机 DNS 失败，尝试公共 DNS。公共 DNS 只适合公网可解析域名。
    if command_exists dig; then
        output=$(dig +time=2 +tries=1 +short A "$host" 2>/dev/null || true)
        ip=$(printf '%s\n' "$output" | first_valid_ipv4_from_text || true)
        if valid_ipv4 "${ip:-}"; then
            printf '%s\n' "$ip"
            return 0
        fi

        for server in "${PUBLIC_DNS_SERVERS[@]}"; do
            output=$(dig @"$server" +time=2 +tries=1 +short A "$host" 2>/dev/null || true)
            ip=$(printf '%s\n' "$output" | first_valid_ipv4_from_text || true)
            if valid_ipv4 "${ip:-}"; then
                printf '%s\n' "$ip"
                return 0
            fi
        done
    fi

    # 3. host / nslookup：兼容一些没有 dig 的系统。
    if command_exists host; then
        output=$(host -t A "$host" 2>/dev/null || true)
        ip=$(printf '%s\n' "$output" | first_valid_ipv4_from_text || true)
        if valid_ipv4 "${ip:-}"; then
            printf '%s\n' "$ip"
            return 0
        fi
    fi

    if command_exists nslookup; then
        output=$(nslookup -type=A "$host" 2>/dev/null || true)
        ip=$(printf '%s\n' "$output" | awk '/^Address: / {print $2}' | while read -r candidate; do
            if [[ "$candidate" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
                echo "$candidate"
                break
            fi
        done)
        if valid_ipv4 "${ip:-}"; then
            printf '%s\n' "$ip"
            return 0
        fi
    fi

    return 1
}

diagnose_dns() {
    local raw_host="$1"
    local host
    host=$(normalize_target_host "$raw_host" 2>/dev/null || true)

    echo -e "${YELLOW}DNS 诊断：${NC}"
    echo "  输入目标：$raw_host"
    echo "  解析主机：${host:-无法提取主机名}"

    if [ -z "${host:-}" ]; then
        return 1
    fi

    echo
    echo "  请在服务器上执行以下命令确认是否有 IPv4 A 记录："
    echo "    getent ahostsv4 $host"
    if command_exists dig; then
        echo "    dig +short A $host"
        echo "    dig +short AAAA $host"
        echo "    dig +short CNAME $host"
        echo "    dig @1.1.1.1 +short A $host"
        echo "    dig @8.8.8.8 +short A $host"
    else
        echo "    apt-get update && apt-get install -y dnsutils"
        echo "    dig +short A $host"
        echo "    dig @1.1.1.1 +short A $host"
    fi
    echo
    echo "  如果 A 记录没有输出，这个目标暂时不能用于 IPv4 nftables DNAT。"
}

install_dependencies() {
    log "${WHITE}正在检查依赖...${NC}"

    local packages=()
    command_exists nft || packages+=("nftables")
    # dig 不是强制依赖，但有它可以绕过本机 resolver 问题并做公共 DNS 回退。
    command_exists dig || packages+=("dnsutils")

    if [ "${#packages[@]}" -eq 0 ]; then
        log "nftables / DNS 工具: ${GREEN}已安装${NC}"
    else
        log "需要安装：${packages[*]}"
        if command_exists apt-get; then
            apt-get update && apt-get install -y "${packages[@]}"
        elif command_exists dnf; then
            # Red Hat 系列中 dig 属于 bind-utils
            local dnf_packages=()
            for p in "${packages[@]}"; do
                [ "$p" = "dnsutils" ] && dnf_packages+=("bind-utils") || dnf_packages+=("$p")
            done
            dnf install -y "${dnf_packages[@]}"
        elif command_exists yum; then
            local yum_packages=()
            for p in "${packages[@]}"; do
                [ "$p" = "dnsutils" ] && yum_packages+=("bind-utils") || yum_packages+=("$p")
            done
            yum install -y "${yum_packages[@]}"
        elif command_exists apk; then
            local apk_packages=()
            for p in "${packages[@]}"; do
                [ "$p" = "dnsutils" ] && apk_packages+=("bind-tools") || apk_packages+=("$p")
            done
            apk add --no-cache "${apk_packages[@]}"
        else
            err "无法自动安装依赖，请手动安装 nftables 和 dig/nslookup 工具"
            return 1
        fi
    fi

    if command_exists systemctl; then
        systemctl enable nftables >/dev/null 2>&1 || true
        systemctl start nftables >/dev/null 2>&1 || true
    fi

    return 0
}

enable_ip_forward() {
    mkdir -p /etc/sysctl.d
    cat > "$SYSCTL_DROPIN" <<'SYSCTL'
# forward2jp nftables port forwarding
net.ipv4.ip_forward = 1
SYSCTL
    sysctl -w net.ipv4.ip_forward=1 >/dev/null
    sysctl -p "$SYSCTL_DROPIN" >/dev/null 2>&1 || true
    log "IPv4 转发: ${GREEN}已启用${NC}"
}

optimize_system() {
    log "${WHITE}正在写入系统优化参数...${NC}"

    mkdir -p /etc/sysctl.d
    cat > "$SYSCTL_DROPIN" <<'SYSCTL'
# forward2jp nftables port forwarding
net.ipv4.ip_forward = 1

# TCP congestion control; only takes effect if kernel supports BBR.
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# Conservative memory preference.
vm.swappiness = 1

# TCP buffers.
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 212992 16777216
net.ipv4.tcp_wmem = 4096 212992 16777216

# Conntrack. Adjust manually if this is too large for small-memory VPS.
net.netfilter.nf_conntrack_max = 2000000
net.netfilter.nf_conntrack_tcp_timeout_established = 7200
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 120
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 60
net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 120
SYSCTL

    if ! sysctl -p "$SYSCTL_DROPIN"; then
        err '部分 sysctl 参数应用失败。可能是内核不支持 BBR 或未加载 conntrack 模块。'
        return 1
    fi

    log "${GREEN}系统优化参数已应用：$SYSCTL_DROPIN${NC}"
}

ensure_rules_db() {
    mkdir -p "$(dirname "$RULES_DB")"
    touch "$RULES_DB"
    chmod 600 "$RULES_DB" 2>/dev/null || true
}

ensure_main_nft_include() {
    local include_line="include \"$NFT_MANAGED_FILE\""
    local backup tmp other_tables

    if [ ! -f "$NFT_MAIN_FILE" ]; then
        cat > "$NFT_MAIN_FILE" <<EOF
#!/usr/sbin/nft -f

$include_line
EOF
        return 0
    fi

    if grep -Fq "$NFT_MANAGED_FILE" "$NFT_MAIN_FILE"; then
        return 0
    fi

    backup="${NFT_MAIN_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
    cp "$NFT_MAIN_FILE" "$backup"

    # 如果是旧版脚本生成的简单配置，只保留 include，避免旧 table forward2jp 和新文件重复。
    other_tables=$(grep -E '^[[:space:]]*table[[:space:]]+' "$NFT_MAIN_FILE" | grep -vE '^[[:space:]]*table[[:space:]]+ip[[:space:]]+forward2jp([[:space:]]|\{)' || true)
    if grep -qE '^[[:space:]]*table[[:space:]]+ip[[:space:]]+forward2jp([[:space:]]|\{)' "$NFT_MAIN_FILE" && [ -z "$other_tables" ]; then
        cat > "$NFT_MAIN_FILE" <<EOF
#!/usr/sbin/nft -f

$include_line
EOF
        log "已迁移旧 nftables.conf，备份：$backup"
        return 0
    fi

    # 多表配置：尝试只移除旧 forward2jp 表块，再追加 include。
    if grep -qE '^[[:space:]]*table[[:space:]]+ip[[:space:]]+forward2jp([[:space:]]|\{)' "$NFT_MAIN_FILE"; then
        tmp=$(mktemp)
        awk '
        BEGIN {skip=0; depth=0}
        /^[[:space:]]*table[[:space:]]+ip[[:space:]]+forward2jp([[:space:]]|\{)/ {
            skip=1
            depth=0
        }
        skip==1 {
            for (i=1; i<=length($0); i++) {
                c=substr($0,i,1)
                if (c=="{") depth++
                if (c=="}") depth--
            }
            if (depth<=0 && $0 ~ /}/) skip=0
            next
        }
        {print}
        ' "$NFT_MAIN_FILE" > "$tmp"
        printf '\n%s\n' "$include_line" >> "$tmp"
        mv "$tmp" "$NFT_MAIN_FILE"
        log "已移除旧 forward2jp 表块并加入 include，备份：$backup"
    else
        printf '\n%s\n' "$include_line" >> "$NFT_MAIN_FILE"
        log "已加入 nftables include：$NFT_MANAGED_FILE，备份：$backup"
    fi
}

build_nft_config() {
    local output_file="$1"
    local update_db_file="${2:-}"
    local local_port target_host target_port proto last_ip target_ip use_ip line
    local key
    declare -A post_rules=()
    declare -A filter_rules=()

    ensure_rules_db

    {
        echo '#!/usr/sbin/nft -f'
        echo
        echo 'table ip forward2jp {'
        echo '    chain prerouting {'
        echo '        type nat hook prerouting priority -100; policy accept;'
    } > "$output_file"

    [ -n "$update_db_file" ] && : > "$update_db_file"

    while IFS= read -r line || [ -n "$line" ]; do
        if [[ "$line" =~ ^[[:space:]]*$ ]] || [[ "$line" =~ ^[[:space:]]*# ]]; then
            [ -n "$update_db_file" ] && printf '%s\n' "$line" >> "$update_db_file"
            continue
        fi

        # 支持空格或 tab 分隔；格式：local_port host target_port proto [last_ip]
        read -r local_port target_host target_port proto last_ip _ <<< "$line"
        proto="${proto:-both}"
        last_ip="${last_ip:-}"

        if ! valid_port "${local_port:-}" || ! valid_port "${target_port:-}"; then
            err "跳过无效规则：$line"
            continue
        fi

        case "$proto" in
            tcp|udp|both) ;;
            *)
                err "跳过无效协议规则：$line"
                continue
                ;;
        esac

        target_ip=$(resolve_ipv4 "$target_host" 2>/dev/null || true)
        if valid_ipv4 "${target_ip:-}"; then
            use_ip="$target_ip"
        elif valid_ipv4 "${last_ip:-}"; then
            use_ip="$last_ip"
            err "${target_host} 当前无法解析，临时沿用上次 IPv4：$last_ip"
        else
            err "${target_host} 无法解析 IPv4，且没有可用的上次 IP，已跳过此规则：本地端口 $local_port"
            [ -n "$update_db_file" ] && printf '%s\t%s\t%s\t%s\t%s\n' "$local_port" "$target_host" "$target_port" "$proto" "$last_ip" >> "$update_db_file"
            continue
        fi

        if [ "$proto" = 'tcp' ] || [ "$proto" = 'both' ]; then
            echo "        tcp dport $local_port dnat to $use_ip:$target_port" >> "$output_file"
            key="tcp-$use_ip-$target_port"
            post_rules["$key"]="        ip protocol tcp ip daddr $use_ip tcp dport $target_port masquerade"
            filter_rules["$key"]="        ip protocol tcp ip daddr $use_ip tcp dport $target_port accept"
        fi

        if [ "$proto" = 'udp' ] || [ "$proto" = 'both' ]; then
            echo "        udp dport $local_port dnat to $use_ip:$target_port" >> "$output_file"
            key="udp-$use_ip-$target_port"
            post_rules["$key"]="        ip protocol udp ip daddr $use_ip udp dport $target_port masquerade"
            filter_rules["$key"]="        ip protocol udp ip daddr $use_ip udp dport $target_port accept"
        fi

        [ -n "$update_db_file" ] && printf '%s\t%s\t%s\t%s\t%s\n' "$local_port" "$target_host" "$target_port" "$proto" "$use_ip" >> "$update_db_file"
    done < "$RULES_DB"

    {
        echo '    }'
        echo
        echo '    chain postrouting {'
        echo '        type nat hook postrouting priority 100; policy accept;'
        for key in "${!post_rules[@]}"; do
            echo "${post_rules[$key]}"
        done
        echo '    }'
        echo '}'
        echo
        echo 'table inet forward2jp_filter {'
        echo '    chain forward {'
        echo '        type filter hook forward priority 0; policy accept;'
        echo '        ct state established,related accept'
        for key in "${!filter_rules[@]}"; do
            echo "${filter_rules[$key]}"
        done
        echo '    }'
        echo '}'
    } >> "$output_file"
}

refresh_rules() {
    local tmp_config tmp_db apply_file

    need_root
    install_dependencies || return 1
    enable_ip_forward
    ensure_rules_db
    ensure_main_nft_include

    exec 9>"$LOCK_FILE"
    if ! flock -x 9; then
        err '无法获取锁，可能已有另一个刷新任务正在运行'
        return 1
    fi

    tmp_config=$(mktemp /tmp/forward2jp-nft.XXXXXX)
    tmp_db=$(mktemp /tmp/forward2jp-db.XXXXXX)
    apply_file=$(mktemp /tmp/forward2jp-apply.XXXXXX)

    build_nft_config "$tmp_config" "$tmp_db"

    : > "$apply_file"
    if nft list table ip forward2jp >/dev/null 2>&1; then
        echo 'delete table ip forward2jp' >> "$apply_file"
    fi
    if nft list table inet forward2jp_filter >/dev/null 2>&1; then
        echo 'delete table inet forward2jp_filter' >> "$apply_file"
    fi
    cat "$tmp_config" >> "$apply_file"

    if ! nft -c -f "$apply_file" >/tmp/forward2jp-nft-check.log 2>&1; then
        err 'nftables 配置检查失败，未应用新规则：'
        cat /tmp/forward2jp-nft-check.log >&2
        rm -f "$tmp_config" "$tmp_db" "$apply_file"
        return 1
    fi

    cp "$tmp_config" "$NFT_MANAGED_FILE"
    chmod 600 "$NFT_MANAGED_FILE" 2>/dev/null || true
    cp "$tmp_db" "$RULES_DB"
    chmod 600 "$RULES_DB" 2>/dev/null || true

    if ! nft -f "$apply_file" >/tmp/forward2jp-nft-apply.log 2>&1; then
        err 'nftables 规则应用失败：'
        cat /tmp/forward2jp-nft-apply.log >&2
        rm -f "$tmp_config" "$tmp_db" "$apply_file"
        return 1
    fi

    rm -f "$tmp_config" "$tmp_db" "$apply_file"
    log "${GREEN}nftables 转发规则已刷新${NC}"
    return 0
}

add_forward_rule() {
    local target_input target_host target_ip local_port target_port proto

    echo -e "${WHITE}请输入转发规则信息：${NC}"
    echo -e "${BLUE}----------------------------------------${NC}"
    echo -n '目标 DDNS 域名 / URL / IPv4: '
    read -r target_input

    target_host=$(normalize_target_host "$target_input" 2>/dev/null || true)
    if [ -z "${target_host:-}" ]; then
        err '目标格式无效'
        return 1
    fi

    target_ip=$(resolve_ipv4 "$target_host" 2>/dev/null || true)
    if ! valid_ipv4 "${target_ip:-}"; then
        err "无法解析 IPv4：$target_host"
        diagnose_dns "$target_host"
        err '目标无法解析为 IPv4，请检查 DDNS / DNS 配置。'
        return 1
    fi

    echo -e "当前解析结果：${GREEN}${target_host} -> ${target_ip}${NC}"
    echo -n '本地端口: '
    read -r local_port
    echo -n '目标端口: '
    read -r target_port
    echo -n '协议 tcp/udp/both [默认 both]: '
    read -r proto
    echo -e "${BLUE}----------------------------------------${NC}"

    proto="${proto:-both}"

    if ! valid_port "$local_port"; then
        err '本地端口无效，范围必须是 1-65535'
        return 1
    fi

    if ! valid_port "$target_port"; then
        err '目标端口无效，范围必须是 1-65535'
        return 1
    fi

    case "$proto" in
        tcp|udp|both) ;;
        *)
            err '协议无效，只能是 tcp、udp、both'
            return 1
            ;;
    esac

    ensure_rules_db

    if awk '!/^[[:space:]]*($|#)/ {print $1}' "$RULES_DB" | grep -qx "$local_port"; then
        err "本地端口 $local_port 已存在规则"
        return 1
    fi

    printf '%s\t%s\t%s\t%s\t%s\n' "$local_port" "$target_host" "$target_port" "$proto" "$target_ip" >> "$RULES_DB"

    if refresh_rules; then
        log "${GREEN}转发规则添加成功！${NC}"
    else
        err '规则刷新失败，正在回滚刚添加的配置'
        sed -i '$d' "$RULES_DB"
        refresh_rules >/dev/null 2>&1 || true
        return 1
    fi
}

show_rules() {
    local i=0 line local_port target_host target_port proto last_ip current_ip status

    ensure_rules_db
    echo -e "${BLUE}----------------------------------------${NC}"

    if ! awk '!/^[[:space:]]*($|#)/ {found=1} END {exit !found}' "$RULES_DB"; then
        echo -e "  ${WHITE}当前没有配置任何转发规则${NC}"
        echo -e "${BLUE}----------------------------------------${NC}"
        return 0
    fi

    echo -e "${WHITE}当前转发规则：${NC}"
    while IFS= read -r line || [ -n "$line" ]; do
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        read -r local_port target_host target_port proto last_ip _ <<< "$line"
        proto="${proto:-both}"
        last_ip="${last_ip:-}"
        current_ip=$(resolve_ipv4 "$target_host" 2>/dev/null || true)
        if valid_ipv4 "${current_ip:-}"; then
            status="当前解析: $current_ip"
        elif valid_ipv4 "${last_ip:-}"; then
            status="当前无法解析，沿用: $last_ip"
        else
            status='当前无法解析'
        fi
        i=$((i + 1))
        printf '%d. 本地端口: %s, 目标: %s, 目标端口: %s, 协议: %s, %s\n' \
            "$i" "$local_port" "$target_host" "$target_port" "$proto" "$status"
    done < "$RULES_DB"

    echo -e "${BLUE}----------------------------------------${NC}"
}

delete_single_rule() {
    local rule_number total tmp

    ensure_rules_db
    show_rules

    if ! awk '!/^[[:space:]]*($|#)/ {found=1} END {exit !found}' "$RULES_DB"; then
        return 0
    fi

    echo -n -e "\n${WHITE}请输入要删除的规则序号：${NC} "
    read -r rule_number

    if [[ ! "$rule_number" =~ ^[0-9]+$ ]]; then
        err '无效的规则序号'
        return 1
    fi

    total=$(awk '!/^[[:space:]]*($|#)/ {i++} END {print i+0}' "$RULES_DB")
    if [ "$rule_number" -lt 1 ] || [ "$rule_number" -gt "$total" ]; then
        err '规则序号不存在'
        return 1
    fi

    tmp=$(mktemp)
    awk -v del="$rule_number" '
    /^[[:space:]]*$/ {print; next}
    /^[[:space:]]*#/ {print; next}
    {i++; if (i != del) print}
    ' "$RULES_DB" > "$tmp"
    mv "$tmp" "$RULES_DB"

    refresh_rules && log "${GREEN}规则删除成功！${NC}"
}

delete_all_rules() {
    echo -n '确定要删除所有转发规则吗？(y/n): '
    read -r confirm
    case "$confirm" in
        y|Y|yes|YES)
            : > "$RULES_DB"
            refresh_rules && log "${GREEN}所有转发规则已删除！${NC}"
            ;;
        *)
            log '取消删除操作'
            ;;
    esac
}

delete_rules_menu() {
    clear_screen
    echo -e "${CYAN}=== 删除转发规则 ===${NC}\n"
    show_rules
    echo -e "\n${WHITE}删除选项：${NC}"
    echo '1. 删除单个转发规则'
    echo '2. 删除所有转发规则'
    echo '3. 返回主菜单'
    echo -n -e "\n${WHITE}请选择操作 [1-3]${NC}: "
    read -r delete_choice

    case "$delete_choice" in
        1) delete_single_rule ;;
        2) delete_all_rules ;;
        3) return 0 ;;
        *) err '无效的选择' ;;
    esac
}

install_timer() {
    local seconds="${1:-$DEFAULT_TIMER_SECONDS}"

    if ! [[ "$seconds" =~ ^[0-9]+$ ]] || [ "$seconds" -lt 10 ]; then
        err '刷新间隔必须是 >= 10 的秒数'
        return 1
    fi

    install_dependencies || return 1

    if [ "$(readlink -f "$0")" != "$SCRIPT_INSTALL_PATH" ]; then
        install -m 700 "$0" "$SCRIPT_INSTALL_PATH"
        log "已安装脚本到：$SCRIPT_INSTALL_PATH"
    fi

    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Refresh nftables DDNS port forwarding rules
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$SCRIPT_INSTALL_PATH --refresh --quiet
EOF

    cat > "$TIMER_FILE" <<EOF
[Unit]
Description=Periodic refresh for nftables DDNS port forwarding rules

[Timer]
OnBootSec=30s
OnUnitActiveSec=${seconds}s
AccuracySec=10s
Unit=forward2jp-ddns-refresh.service

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable --now forward2jp-ddns-refresh.timer

    log "${GREEN}DDNS 定时刷新已启用，每 ${seconds} 秒刷新一次${NC}"
}

disable_timer() {
    if command_exists systemctl; then
        systemctl disable --now forward2jp-ddns-refresh.timer >/dev/null 2>&1 || true
        systemctl daemon-reload >/dev/null 2>&1 || true
    fi
    log "${GREEN}DDNS 定时刷新已停用${NC}"
}

status_info() {
    echo -e "${CYAN}系统状态：${NC}"
    echo "  IPv4 转发: $(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null || echo unknown)"
    echo "  规则数据库: $RULES_DB"
    echo "  nftables 托管配置: $NFT_MANAGED_FILE"

    if command_exists systemctl; then
        if systemctl is-enabled forward2jp-ddns-refresh.timer >/dev/null 2>&1; then
            echo '  DDNS 定时刷新: 已启用'
            systemctl list-timers --all forward2jp-ddns-refresh.timer 2>/dev/null || true
        else
            echo '  DDNS 定时刷新: 未启用'
        fi
    fi

    echo
    show_rules
}

init_environment() {
    clear_screen
    echo -e "${CYAN}=== 初始化环境 / 应用当前规则 ===${NC}\n"
    log '正在初始化环境...'
    install_dependencies || return 1
    enable_ip_forward
    refresh_rules
}

main_menu() {
    while true; do
        clear_screen
        echo -e "${CYAN}可用操作：${NC}"
        echo -e "${BLUE}┌────────────────────────────────────────┐${NC}"
        echo -e "${BLUE}│${NC}  ${WHITE}1${NC}. 初始化环境 / 应用当前规则             ${BLUE}│${NC}"
        echo -e "${BLUE}│${NC}  ${WHITE}2${NC}. 添加转发规则                         ${BLUE}│${NC}"
        echo -e "${BLUE}│${NC}  ${WHITE}3${NC}. 删除转发规则                         ${BLUE}│${NC}"
        echo -e "${BLUE}│${NC}  ${WHITE}4${NC}. 显示当前规则 / 状态                  ${BLUE}│${NC}"
        echo -e "${BLUE}│${NC}  ${WHITE}5${NC}. 系统性能优化                         ${BLUE}│${NC}"
        echo -e "${BLUE}│${NC}  ${WHITE}6${NC}. 安装 / 更新 DDNS 定时刷新             ${BLUE}│${NC}"
        echo -e "${BLUE}│${NC}  ${WHITE}7${NC}. 停用 DDNS 定时刷新                    ${BLUE}│${NC}"
        echo -e "${BLUE}│${NC}  ${WHITE}0${NC}. 退出程序                             ${BLUE}│${NC}"
        echo -e "${BLUE}└────────────────────────────────────────┘${NC}"
        echo
        echo -n -e "${CYAN}请选择操作 [0-7]${NC}: "
        read -r choice

        case "$choice" in
            1) init_environment; pause ;;
            2) clear_screen; echo -e "${CYAN}=== 添加转发规则 ===${NC}\n"; add_forward_rule; pause ;;
            3) delete_rules_menu; pause ;;
            4) clear_screen; echo -e "${CYAN}=== 当前转发规则 / 状态 ===${NC}\n"; status_info; pause ;;
            5) clear_screen; echo -e "${CYAN}=== 系统性能优化 ===${NC}\n"; optimize_system; pause ;;
            6)
                clear_screen
                echo -e "${CYAN}=== 安装 / 更新 DDNS 定时刷新 ===${NC}\n"
                echo -n "刷新间隔秒数 [默认 $DEFAULT_TIMER_SECONDS]: "
                read -r seconds
                seconds="${seconds:-$DEFAULT_TIMER_SECONDS}"
                install_timer "$seconds"
                pause
                ;;
            7) clear_screen; echo -e "${CYAN}=== 停用 DDNS 定时刷新 ===${NC}\n"; disable_timer; pause ;;
            0) clear_screen; echo -e "${GREEN}感谢使用，再见！${NC}"; exit 0 ;;
            *) echo -e "\n${RED}无效的选择，请重试${NC}"; sleep 1 ;;
        esac
    done
}

usage() {
    cat <<EOF
用法：$0 [选项]

无参数                 进入交互式菜单
--refresh              解析 DDNS 并刷新 nftables 规则
--show                 显示当前规则和状态
--install-timer [秒]   安装/更新 systemd 定时刷新，默认 ${DEFAULT_TIMER_SECONDS} 秒
--disable-timer        停用 systemd 定时刷新
--optimize             写入系统优化参数
--diagnose HOST        诊断某个 DDNS/URL/IPv4 的 IPv4 解析
--quiet                静默模式，通常配合 --refresh 使用
-h, --help             显示帮助
EOF
}

main() {
    need_root

    local args=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --quiet) QUIET=1; shift ;;
            *) args+=("$1"); shift ;;
        esac
    done

    set -- "${args[@]}"

    case "${1:-}" in
        '') main_menu ;;
        --refresh) refresh_rules ;;
        --show) status_info ;;
        --install-timer) install_timer "${2:-$DEFAULT_TIMER_SECONDS}" ;;
        --disable-timer) disable_timer ;;
        --optimize) optimize_system ;;
        --diagnose)
            if [ -z "${2:-}" ]; then
                err '请提供要诊断的域名 / URL / IPv4'
                exit 1
            fi
            diagnose_dns "$2"
            ;;
        -h|--help) usage ;;
        *) usage; exit 1 ;;
    esac
}

main "$@"
