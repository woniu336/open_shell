#!/bin/bash
# =========================================================
# firewall_ufw_china_dual_update.sh (修复版)
# 功能：UFW + IPSet 双栈（IPv4 + IPv6）
#       仅允许中国大陆与 Cloudflare 访问 80/443
#       自动每日更新（含动态 Cloudflare IP 段）
# 修复：规则添加逻辑更可靠
# =========================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

CN_IP_FILE="/tmp/cn.zone"
CN_IPSET_NAME="china"
CN_IPSET6_NAME="china6"
HTTP_PORT=80
HTTPS_PORT=443
UPDATE_SCRIPT="/usr/local/bin/update_china_ipset.sh"
CRON_JOB="0 4 * * * $UPDATE_SCRIPT >/dev/null 2>&1"

echo -e "${GREEN}========== 防火墙配置脚本（UFW 双栈 + 自动更新）修复版 ==========${NC}"

# === 安装依赖 ===
check_install() {
    local pkg=$1
    if ! command -v $pkg &>/dev/null; then
        echo -e "${YELLOW}[INFO] 未检测到 $pkg，正在安装...${NC}"
        apt-get update -y && apt-get install -y $pkg
    else
        echo -e "${GREEN}[OK] 已安装：$pkg${NC}"
    fi
}

check_install ufw
check_install ipset
check_install curl
check_install cron

# === 启用 UFW ===
ufw_status=$(ufw status | grep -i "Status" | awk '{print $2}')
if [ "$ufw_status" != "active" ]; then
    echo -e "${YELLOW}[INFO] UFW 未启用，正在启用...${NC}"
    ufw --force enable
else
    echo -e "${GREEN}[OK] UFW 已启用${NC}"
fi

# === 检测 SSH 端口 ===
SSH_PORT=$(grep -E "^[[:space:]]*Port[[:space:]]+[0-9]+" /etc/ssh/sshd_config | awk '{print $2}' | tail -n1)
if [ -z "$SSH_PORT" ]; then
    SSH_PORT=$(ss -tnlp | grep sshd | awk -F: '{print $2}' | awk '{print $1}' | head -n1)
fi
[ -z "$SSH_PORT" ] && SSH_PORT=22
echo -e "${GREEN}[INFO] 检测到 SSH 端口：$SSH_PORT${NC}"

# 放行 SSH
if ! ufw status numbered | grep -q "$SSH_PORT/tcp"; then
    ufw allow $SSH_PORT/tcp comment 'Allow SSH'
fi

# === 下载中国 IPv4 段 ===
echo -e "${YELLOW}[INFO] 正在下载中国大陆 IPv4 段数据...${NC}"
curl -s https://www.ipdeny.com/ipblocks/data/countries/cn.zone -o "$CN_IP_FILE"
if [ $? -ne 0 ] || [ ! -s "$CN_IP_FILE" ]; then
    echo -e "${RED}[ERROR] 无法下载中国IP列表！${NC}"
    exit 1
fi

# === 创建/刷新 IPv4 集合 ===
if ipset list $CN_IPSET_NAME &>/dev/null; then
    echo -e "${YELLOW}[INFO] 刷新现有 IPv4 集合...${NC}"
    ipset flush $CN_IPSET_NAME
else
    echo -e "${YELLOW}[INFO] 创建新 IPv4 集合...${NC}"
    ipset create $CN_IPSET_NAME hash:net family inet maxelem 100000
fi

while read ip; do ipset add $CN_IPSET_NAME "$ip" 2>/dev/null; done < "$CN_IP_FILE"

# === 动态获取 Cloudflare IPv4 ===
echo -e "${YELLOW}[INFO] 正在获取 Cloudflare IPv4 段...${NC}"
for net in $(curl -fsSL https://www.cloudflare.com/ips-v4); do
    ipset add $CN_IPSET_NAME "$net" 2>/dev/null
done

echo -e "${GREEN}[OK] IPv4 集合加载完成，共 $(ipset list $CN_IPSET_NAME | wc -l) 条${NC}"

# === 创建/刷新 IPv6 集合 ===
if ipset list $CN_IPSET6_NAME &>/dev/null; then
    echo -e "${YELLOW}[INFO] 刷新现有 IPv6 集合...${NC}"
    ipset flush $CN_IPSET6_NAME
else
    echo -e "${YELLOW}[INFO] 创建新 IPv6 集合...${NC}"
    ipset create $CN_IPSET6_NAME hash:net family inet6 maxelem 10000
fi

echo -e "${YELLOW}[INFO] 正在获取 Cloudflare IPv6 段...${NC}"
for net in $(curl -fsSL https://www.cloudflare.com/ips-v6); do
    ipset add $CN_IPSET6_NAME "$net" 2>/dev/null
done

echo -e "${GREEN}[OK] IPv6 集合加载完成 (含 Cloudflare IPv6 段)${NC}"

# ========================================
# 关键修复：先清理旧规则，再添加新规则
# ========================================

echo -e "${YELLOW}[INFO] 清理旧的 80/443 防火墙规则...${NC}"

# 清理 IPv4 旧规则 (只删除 80/443 相关的规则)
clean_old_rules_v4() {
    local max_iter=50
    local iter=0
    local cleaned=0
    
    while [ $iter -lt $max_iter ]; do
        local found=0
        
        # 1. 删除包含 match-set china 且端口是 80/443 的规则
        local line=$(iptables -L ufw-user-input -n --line-numbers 2>/dev/null | \
                    grep -E "match-set.*china" | \
                    grep -E "dpt:(80|443)" | \
                    head -1 | awk '{print $1}')
        if [ -n "$line" ]; then
            echo "   删除 IPv4 match-set 规则 #$line"
            iptables -D ufw-user-input "$line" 2>/dev/null && found=1 && cleaned=1
        fi
        
        # 2. 删除 DROP 80/443 规则
        local line=$(iptables -L ufw-user-input -n --line-numbers 2>/dev/null | \
                    grep -E "DROP.*tcp" | \
                    grep -E "dpt:(80|443)" | \
                    head -1 | awk '{print $1}')
        if [ -n "$line" ]; then
            echo "   删除 IPv4 DROP 规则 #$line"
            iptables -D ufw-user-input "$line" 2>/dev/null && found=1 && cleaned=1
        fi
        
        # 3. 删除无条件 ACCEPT 80/443 规则 (不带 match-set 的)
        local line=$(iptables -L ufw-user-input -n --line-numbers 2>/dev/null | \
                    grep -E "ACCEPT.*tcp" | \
                    grep -E "dpt:(80|443)" | \
                    grep -v "match-set" | \
                    head -1 | awk '{print $1}')
        if [ -n "$line" ]; then
            echo "   删除 IPv4 无条件 ACCEPT 规则 #$line"
            iptables -D ufw-user-input "$line" 2>/dev/null && found=1 && cleaned=1
        fi
        
        [ $found -eq 0 ] && break
        iter=$((iter + 1))
    done
    
    [ $cleaned -eq 0 ] && echo "   IPv4: 没有需要清理的规则"
}

# 清理 IPv6 旧规则 (只删除 80/443 相关的规则)
clean_old_rules_v6() {
    local max_iter=50
    local iter=0
    local cleaned=0
    
    while [ $iter -lt $max_iter ]; do
        local found=0
        
        # 1. 删除包含 match-set china6 且端口是 80/443 的规则
        local line=$(ip6tables -L ufw6-user-input -n --line-numbers 2>/dev/null | \
                    grep -E "match-set.*china" | \
                    grep -E "dpt:(80|443)" | \
                    head -1 | awk '{print $1}')
        if [ -n "$line" ]; then
            echo "   删除 IPv6 match-set 规则 #$line"
            ip6tables -D ufw6-user-input "$line" 2>/dev/null && found=1 && cleaned=1
        fi
        
        # 2. 删除 DROP 80/443 规则
        local line=$(ip6tables -L ufw6-user-input -n --line-numbers 2>/dev/null | \
                    grep -E "DROP.*tcp" | \
                    grep -E "dpt:(80|443)" | \
                    head -1 | awk '{print $1}')
        if [ -n "$line" ]; then
            echo "   删除 IPv6 DROP 规则 #$line"
            ip6tables -D ufw6-user-input "$line" 2>/dev/null && found=1 && cleaned=1
        fi
        
        # 3. 删除无条件 ACCEPT 80/443 规则 (不带 match-set 的)
        local line=$(ip6tables -L ufw6-user-input -n --line-numbers 2>/dev/null | \
                    grep -E "ACCEPT.*tcp" | \
                    grep -E "dpt:(80|443)" | \
                    grep -v "match-set" | \
                    head -1 | awk '{print $1}')
        if [ -n "$line" ]; then
            echo "   删除 IPv6 无条件 ACCEPT 规则 #$line"
            ip6tables -D ufw6-user-input "$line" 2>/dev/null && found=1 && cleaned=1
        fi
        
        [ $found -eq 0 ] && break
        iter=$((iter + 1))
    done
    
    [ $cleaned -eq 0 ] && echo "   IPv6: 没有需要清理的规则"
}

clean_old_rules_v4
clean_old_rules_v6

echo -e "${GREEN}[OK] 旧规则清理完成${NC}"

# === 添加新的 IPv4 防火墙规则 ===
echo -e "${YELLOW}[INFO] 添加新的 IPv4 防火墙规则...${NC}"
iptables -I ufw-user-input 1 -p tcp -m set --match-set $CN_IPSET_NAME src --dport $HTTP_PORT -j ACCEPT
iptables -I ufw-user-input 1 -p tcp -m set --match-set $CN_IPSET_NAME src --dport $HTTPS_PORT -j ACCEPT
iptables -A ufw-user-input -p tcp --dport $HTTP_PORT -j DROP
iptables -A ufw-user-input -p tcp --dport $HTTPS_PORT -j DROP
echo -e "${GREEN}[OK] IPv4 规则添加完成${NC}"

# === 添加新的 IPv6 防火墙规则 ===
echo -e "${YELLOW}[INFO] 添加新的 IPv6 防火墙规则...${NC}"
ip6tables -I ufw6-user-input 1 -p tcp -m set --match-set $CN_IPSET6_NAME src --dport $HTTP_PORT -j ACCEPT
ip6tables -I ufw6-user-input 1 -p tcp -m set --match-set $CN_IPSET6_NAME src --dport $HTTPS_PORT -j ACCEPT
ip6tables -A ufw6-user-input -p tcp --dport $HTTP_PORT -j DROP
ip6tables -A ufw6-user-input -p tcp --dport $HTTPS_PORT -j DROP
echo -e "${GREEN}[OK] IPv6 规则添加完成${NC}"

# === 保存规则 ===
echo -e "${YELLOW}[INFO] 保存 IPSet 规则...${NC}"
mkdir -p /etc/iptables
ipset save > /etc/iptables/ipset.rules

cat >/etc/systemd/system/ipset-restore.service <<'EOF'
[Unit]
Description=Restore IP sets for firewall
Before=ufw.service

[Service]
Type=oneshot
ExecStart=/sbin/ipset restore -f /etc/iptables/ipset.rules

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ipset-restore.service
echo -e "${GREEN}[OK] IPSet 开机自启已配置${NC}"

# === 创建自动更新脚本 ===
cat >"$UPDATE_SCRIPT" <<'UPDATEEOF'
#!/bin/bash
CN_IP_FILE="/tmp/cn.zone"
CN_IPSET_NAME="china"
CN_IPSET6_NAME="china6"

curl -s https://www.ipdeny.com/ipblocks/data/countries/cn.zone -o "$CN_IP_FILE"
[ $? -ne 0 ] || [ ! -s "$CN_IP_FILE" ] && exit 1

ipset flush $CN_IPSET_NAME
while read ip; do ipset add $CN_IPSET_NAME "$ip" 2>/dev/null; done < "$CN_IP_FILE"

# 动态 Cloudflare IPv4
for net in $(curl -fsSL https://www.cloudflare.com/ips-v4); do
    ipset add $CN_IPSET_NAME "$net" 2>/dev/null
done

# 动态 Cloudflare IPv6
ipset flush $CN_IPSET6_NAME
for net in $(curl -fsSL https://www.cloudflare.com/ips-v6); do
    ipset add $CN_IPSET6_NAME "$net" 2>/dev/null
done

ipset save > /etc/iptables/ipset.rules
UPDATEEOF

chmod +x "$UPDATE_SCRIPT"
echo -e "${GREEN}[OK] 自动更新脚本已创建：$UPDATE_SCRIPT${NC}"

# === 检查并添加定时任务 ===
if crontab -l 2>/dev/null | grep -q "$UPDATE_SCRIPT"; then
    echo -e "${YELLOW}[INFO] 已存在每日更新任务，跳过添加${NC}"
else
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    echo -e "${GREEN}[OK] 已添加每日凌晨4点自动更新任务${NC}"
fi


# === 输出结果 ===
echo -e "\n${GREEN}╔═══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   ✅ 防火墙（UFW IPv4+IPv6 + 自动更新）    ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════╝${NC}"
echo -e "${GREEN}[✓] SSH 端口：${NC}$SSH_PORT"
echo -e "${GREEN}[✓] 中国 + Cloudflare IPv4：${NC}$(ipset list $CN_IPSET_NAME | wc -l) 条"
echo -e "${GREEN}[✓] IPv6 Cloudflare 集合：${NC}$CN_IPSET6_NAME"
echo -e "${GREEN}[✓] Web端口：${NC}80/443 (仅中国大陆 + Cloudflare 可访问)"
echo -e "${GREEN}[✓] 每日更新任务：${NC}$(crontab -l 2>/dev/null | grep -q "$UPDATE_SCRIPT" && echo "已启用" || echo "未启用")"
echo ""
echo -e "${YELLOW}[查看集合]${NC} ipset list china"
echo -e "${YELLOW}[查看 IPv4 规则]${NC} iptables -L ufw-user-input -n -v"
echo -e "${YELLOW}[查看 IPv6 规则]${NC} ip6tables -L ufw6-user-input -n -v"
echo -e "${YELLOW}[查看计划任务]${NC} crontab -l"
echo -e "${YELLOW}[手动更新]${NC} $UPDATE_SCRIPT"
echo ""
