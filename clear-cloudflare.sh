#!/bin/bash
# Name  : Clear Cloudflare Rules
# Author: Zhys

echo "Backing up current rules..."
# 备份当前内存中的规则
iptables-save > "iptables_backup_$(date +%Y%m%d_%H%M%S).rules"
ip6tables-save > "ip6tables_backup_$(date +%Y%m%d_%H%M%S).rules"

# 备份已保存的规则文件
if [ -f "/etc/iptables/rules.v4" ]; then
    cp /etc/iptables/rules.v4 /etc/iptables/rules.v4.bak
    echo "Backed up /etc/iptables/rules.v4"
fi

if [ -f "/etc/iptables/rules.v6" ]; then
    cp /etc/iptables/rules.v6 /etc/iptables/rules.v6.bak
    echo "Backed up /etc/iptables/rules.v6"
fi

echo "Cleaning all rules related to ports 80,443..."

# 清理 IPv4 规则（从最后一条规则开始删除）
while read -r line; do
    rule_num=$(echo "$line" | awk '{print $1}')
    if [ ! -z "$rule_num" ]; then
        iptables -D INPUT "$rule_num"
        echo "Removed IPv4 rule #$rule_num"
    fi
done < <(iptables -L INPUT -n --line-numbers | grep "multiport dports 80,443" | tac)

# 清理 IPv6 规则（从最后一条规则开始删除）
while read -r line; do
    rule_num=$(echo "$line" | awk '{print $1}')
    if [ ! -z "$rule_num" ]; then
        ip6tables -D INPUT "$rule_num"
        echo "Removed IPv6 rule #$rule_num"
    fi
done < <(ip6tables -L INPUT -n --line-numbers | grep "multiport dports 80,443" | tac)

echo "Saving new rules..."
mkdir -p /etc/iptables/
iptables-save > /etc/iptables/rules.v4
ip6tables-save > /etc/iptables/rules.v6

echo "Done! All rules related to ports 80,443 have been removed."

# 显示当前规则
echo -e "\nCurrent IPv4 rules:"
iptables -L INPUT -n --line-numbers | grep -E "80|443"
echo -e "\nCurrent IPv6 rules:"
ip6tables -L INPUT -n --line-numbers | grep -E "80|443"