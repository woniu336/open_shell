#!/bin/bash
# 脚本：允许指定 IP 访问 Docker 的指定端口
# 功能：
#   1) ./allow_ips.sh <端口> <ip1> <ip2> ...   # 添加规则
#   2) ./allow_ips.sh list                     # 查看规则
#   3) ./allow_ips.sh clear <端口>             # 清理指定端口的规则
#   4) ./allow_ips.sh save                     # 手动保存规则
#   5) ./allow_ips.sh restore                  # 恢复规则（开机自启可用）

CHAIN="DOCKER-USER"
RULE_FILE="/etc/iptables/rules.v4"

# 检查并安装 netfilter-persistent
if ! command -v netfilter-persistent >/dev/null 2>&1; then
    echo "未检测到 netfilter-persistent，正在安装..."
    sudo apt update
    sudo apt install -y iptables-persistent
fi

# 查看规则
if [ "$1" == "list" ]; then
    echo "当前 $CHAIN 链规则："
    sudo iptables -S $CHAIN
    exit 0
fi

# 清理规则
if [ "$1" == "clear" ]; then
    if [ -z "$2" ]; then
        echo "用法: $0 clear <端口>"
        exit 1
    fi
    PORT=$2
    echo "正在清理端口 $PORT 的规则..."
    while sudo iptables -C $CHAIN -p tcp --dport $PORT -j DROP 2>/dev/null; do
        sudo iptables -D $CHAIN -p tcp --dport $PORT -j DROP
    done
    while read -r ip; do
        while sudo iptables -C $CHAIN -s "$ip" -p tcp --dport $PORT -j ACCEPT 2>/dev/null; do
            sudo iptables -D $CHAIN -s "$ip" -p tcp --dport $PORT -j ACCEPT
        done
    done < <(sudo iptables -S $CHAIN | grep -- "--dport $PORT" | grep "ACCEPT" | awk '{print $4}' | cut -d/ -f1)
    echo "端口 $PORT 相关规则已清理完成。"

    # 自动保存
    sudo netfilter-persistent save
    echo "规则已保存。"
    exit 0
fi

# 保存规则
if [ "$1" == "save" ]; then
    echo "正在保存规则到 $RULE_FILE..."
    sudo mkdir -p /etc/iptables
    sudo iptables-save | sudo tee $RULE_FILE > /dev/null
    sudo netfilter-persistent save
    echo "规则已保存。"
    exit 0
fi

# 恢复规则
if [ "$1" == "restore" ]; then
    if [ -f "$RULE_FILE" ]; then
        echo "正在恢复规则..."
        sudo iptables-restore < $RULE_FILE
        sudo netfilter-persistent reload
        echo "规则已恢复并已持久化。"
    else
        echo "未找到规则文件: $RULE_FILE"
    fi
    exit 0
fi

# 添加规则
if [ $# -lt 2 ]; then
    echo "用法:"
    echo "  $0 <端口> <ip1> <ip2> ...   # 添加规则"
    echo "  $0 list                     # 查看规则"
    echo "  $0 clear <端口>             # 清理规则"
    echo "  $0 save                     # 保存规则"
    echo "  $0 restore                  # 恢复规则"
    exit 1
fi

PORT=$1
shift   # 去掉端口参数

# 先清理旧规则
while sudo iptables -C $CHAIN -p tcp --dport $PORT -j DROP 2>/dev/null; do
    sudo iptables -D $CHAIN -p tcp --dport $PORT -j DROP
done
for ip in "$@"; do
    while sudo iptables -C $CHAIN -s "$ip" -p tcp --dport $PORT -j ACCEPT 2>/dev/null; do
        sudo iptables -D $CHAIN -s "$ip" -p tcp --dport $PORT -j ACCEPT
    done
done

# 添加新的允许规则
for ip in "$@"; do
    echo "允许 $ip 访问端口 $PORT"
    sudo iptables -I $CHAIN 1 -s "$ip" -p tcp --dport $PORT -j ACCEPT
done

# 最后加一条 DROP 规则
sudo iptables -I $CHAIN $(($# + 1)) -p tcp --dport $PORT -j DROP
echo "所有其他 IP 已被阻止访问端口 $PORT"

# 自动保存
sudo netfilter-persistent save
echo "规则已保存。"
