#!/bin/bash

# 日志文件路径
LOG_FILE="/var/log/block_censys.log"

# 函数：记录日志
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') : $1" | tee -a "$LOG_FILE"
}

log "开始执行脚本..."

# 更新并安装必要的软件包
log "更新软件包列表并安装ipset, iptables, netfilter-persistent..."
apt update && apt install ipset iptables netfilter-persistent ipset-persistent iptables-persistent -y
if [ $? -ne 0 ]; then
    log "软件包安装失败。"
    exit 1
fi
log "软件包安装完成。"

# 启用netfilter-persistent服务
log "启用netfilter-persistent服务..."
systemctl enable netfilter-persistent
if [ $? -ne 0 ]; then
    log "启用netfilter-persistent失败。"
    exit 1
fi
log "netfilter-persistent服务已启用。"

# 创建censys.zone文件并添加IPv4地址段
CENSYS_ZONE="/root/censys.zone"
log "创建$CENSYS_ZONE并添加IPv4地址段..."
cat <<EOL > "$CENSYS_ZONE"
162.142.125.0/24
167.94.138.0/24
167.94.145.0/24
167.94.146.0/24
167.248.133.0/24
199.45.154.0/24
199.45.155.0/24
206.168.34.0/24
EOL
if [ $? -ne 0 ]; then
    log "创建$censys_zone文件失败。"
    exit 1
fi
log "$CENSYS_ZONE 文件已创建。"

# 创建censys6.zone文件并添加IPv6地址段
CENSYS6_ZONE="/root/censys6.zone"
log "创建$CENSYS6_ZONE并添加IPv6地址段..."
cat <<EOL > "$CENSYS6_ZONE"
2602:80d:1000:b0cc:e::/80
2620:96:e000:b0cc:e::/80
2602:80d:1003::/112
2602:80d:1004::/112
EOL
if [ $? -ne 0 ]; then
    log "创建$censys6_zone文件失败。"
    exit 1
fi
log "$CENSYS6_ZONE 文件已创建。"

# 创建ipset规则censys
log "创建ipset集 'censys'..."
ipset -N censys hash:net
if [ $? -ne 0 ]; then
    log "创建ipset 'censys'失败。"
    exit 1
fi
log "ipset 'censys' 创建成功。"

# 创建ipset规则censys6
log "创建ipset集 'censys6'..."
ipset -N censys6 hash:net family inet6
if [ $? -ne 0 ]; then
    log "创建ipset 'censys6'失败。"
    exit 1
fi
log "ipset 'censys6' 创建成功。"

# 将IPv4地址段添加到censys集
log "将IPv4地址段添加到 'censys' 集中..."
while IFS= read -r ip; do
    ipset -A censys "$ip"
    if [ $? -ne 0 ]; then
        log "添加 $ip 到 'censys' 失败。"
    else
        log "添加 $ip 到 'censys' 成功。"
    fi
done < "$CENSYS_ZONE"

# 将IPv6地址段添加到censys6集
log "将IPv6地址段添加到 'censys6' 集中..."
while IFS= read -r ip; do
    ipset -A censys6 "$ip"
    if [ $? -ne 0 ]; then
        log "添加 $ip 到 'censys6' 失败。"
    else
        log "添加 $ip 到 'censys6' 成功。"
    fi
done < "$CENSYS6_ZONE"

# 屏蔽censys集中的IP
log "应用iptables规则以屏蔽 'censys' 集中的IP..."
iptables -I INPUT -p tcp -m set --match-set censys src -j DROP
if [ $? -ne 0 ]; then
    log "应用iptables规则失败。"
    exit 1
fi
log "iptables规则已应用。"

# 屏蔽censys6集中的IP
log "应用ip6tables规则以屏蔽 'censys6' 集中的IP..."
ip6tables -I INPUT -p tcp -m set --match-set censys6 src -j DROP
if [ $? -ne 0 ]; then
    log "应用ip6tables规则失败。"
    exit 1
fi
log "ip6tables规则已应用。"

# 保存iptables规则
log "保存iptables和ip6tables规则..."
netfilter-persistent save
if [ $? -ne 0 ]; then
    log "保存iptables规则失败。"
    exit 1
fi
log "iptables规则已保存。"

log "脚本执行完成。"