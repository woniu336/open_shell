#!/bin/bash
# 脚本名称: ipwl.sh
# 描述: 针对Debian系统创建和管理基于端口的IP白名单
# 作者: Claude
# 日期: 2025-05-10

# 检查是否以root权限运行
if [ "$(id -u)" -ne 0 ]; then
    echo "错误: 请使用root权限运行此脚本" >&2
    exit 1
fi

# 静默检查ipset是否安装
if ! command -v ipset &> /dev/null; then
    echo "检测到ipset未安装，正在安装..."
    apt-get update -qq
    apt-get install -y ipset
    if [ $? -ne 0 ]; then
        echo "安装ipset失败，请检查您的网络连接或手动安装" >&2
        exit 1
    fi
    echo "ipset安装成功"
fi

# 提示用户输入端口
read -p "请输入需要设置白名单的端口号: " port

# 验证端口号是否有效
if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
    echo "错误: 请输入有效的端口号 (1-65535)" >&2
    exit 1
fi

# 根据端口创建ipset集合名称
set_name="whitelist_port_${port}"

# 检查是否已存在同名集合
set_exists=false
if ipset list -n | grep -q "^${set_name}$"; then
    set_exists=true
    echo "发现集合 ${set_name} 已存在"
    read -p "是否要添加新IP到现有集合? (y/n): " update_choice
    if [[ "$update_choice" != "y" && "$update_choice" != "Y" ]]; then
        echo "警告: 集合 ${set_name} 将被重置，所有现有IP将被删除"
        ipset destroy "${set_name}"
        set_exists=false
    fi
fi

# 如果集合不存在，创建新的ipset集合
if [ "$set_exists" = false ]; then
    ipset create "${set_name}" hash:ip
    echo "已创建新的白名单集合: ${set_name}"
fi

# 提示用户输入白名单IP
if [ "$set_exists" = true ]; then
    echo "当前集合中已有以下IP:"
    ipset list "${set_name}" | grep -E '^[0-9]'
fi
echo "请输入要添加到白名单的IP地址 (输入'完成'结束添加):"
while true; do
    read -p "IP地址: " ip_address
    
    if [ "$ip_address" = "完成" ]; then
        break
    fi
    
    # 验证IP地址格式
    if [[ ! $ip_address =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        echo "错误: 无效的IP地址格式，请重新输入" >&2
        continue
    fi
    
    # 检查IP是否已存在于集合中
    if ipset test "${set_name}" "${ip_address}" 2>/dev/null; then
        echo "IP ${ip_address} 已存在于白名单中，跳过"
    else
        # 添加IP到集合
        ipset add "${set_name}" "${ip_address}"
        echo "已添加 ${ip_address} 到白名单"
    fi
done

# 检查并删除ufw中相同端口的规则
if command -v ufw &> /dev/null && ufw status | grep -q "active"; then
    # 检查是否有相同端口的规则
    if ufw status numbered | grep -q "^\\[[0-9]\\+\\].*${port}"; then
        # 获取所有与该端口相关的规则号码（从高到低排序）
        rule_numbers=$(ufw status numbered | grep -E "^\[[0-9]+\].*${port}" | sed -E 's/^\[([0-9]+)\].*/\1/' | sort -nr)
        
        # 静默删除这些规则（从高到低删除，避免序号变化问题）
        for num in $rule_numbers; do
            ufw --force delete $num &>/dev/null
        done
    fi
fi

# 创建iptables规则并持久化
echo ""
echo "===== 正在添加并持久化iptables规则 ====="

# 检查iptables规则是否已存在
rule_exists=$(iptables -C INPUT -p tcp --dport ${port} -m set --match-set ${set_name} src -j ACCEPT 2>/dev/null || echo "no")
drop_exists=$(iptables -C INPUT -p tcp --dport ${port} -j DROP 2>/dev/null || echo "no")

# 添加允许规则（如果不存在）
if [ "$rule_exists" = "no" ]; then
    iptables -A INPUT -p tcp --dport ${port} -m set --match-set ${set_name} src -j ACCEPT
    echo "已添加白名单通行规则"
else
    echo "白名单通行规则已存在，无需添加"
fi

# 添加拒绝规则（如果不存在）
if [ "$drop_exists" = "no" ]; then
    iptables -A INPUT -p tcp --dport ${port} -j DROP
    echo "已添加默认拒绝规则"
else
    echo "默认拒绝规则已存在，无需添加"
fi

# 确保目录存在
mkdir -p /etc/iptables

# 保存iptables规则
echo "正在持久化iptables规则..."
iptables-save > /etc/iptables/rules.v4
if [ $? -eq 0 ]; then
    echo "iptables规则已成功保存到 /etc/iptables/rules.v4"
else
    echo "保存iptables规则失败，请检查权限"
fi

# 保存ipset规则
ipset save > /etc/iptables/ipset.conf
if [ $? -eq 0 ]; then
    echo "ipset规则已成功保存到 /etc/iptables/ipset.conf"
else
    echo "保存ipset规则失败，请检查权限"
fi

# 创建启动脚本以恢复规则
if [ ! -f /etc/network/if-pre-up.d/iptables-restore ]; then
    cat > /etc/network/if-pre-up.d/iptables-restore << 'EOF'
#!/bin/sh
# 恢复ipset规则
if [ -f /etc/iptables/ipset.conf ]; then
    ipset restore -f /etc/iptables/ipset.conf
fi
# 恢复iptables规则
if [ -f /etc/iptables/rules.v4 ]; then
    iptables-restore < /etc/iptables/rules.v4
fi
exit 0
EOF
    chmod +x /etc/network/if-pre-up.d/iptables-restore
    echo "已创建启动脚本以确保系统启动时加载规则"
fi