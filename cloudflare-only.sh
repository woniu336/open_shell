#!/bin/bash
# Name  : Anti IP Leakage
# Author: Zhys
# Date  : 2019

# 备份当前规则
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

# 禁止来自 IPv4 的所有 HTTP/S 访问请求
echo "Setting up IPv4 rules..."
iptables -I INPUT -p tcp -m multiport --dports 80,443 -j DROP

# 对 Cloudflare CDN IPv4 地址开放 HTTP/S 入站访问
for i in `curl -s https://www.cloudflare.com/ips-v4`; do 
    echo "Adding Cloudflare IPv4: $i"
    iptables -I INPUT -s $i -p tcp -m multiport --dports 80,443 -j ACCEPT
done

# 禁止来自 IPv6 的所有 HTTP/S 访问请求
echo "Setting up IPv6 rules..."
ip6tables -I INPUT -p tcp -m multiport --dports 80,443 -j DROP

# 对 Cloudflare CDN IPv6 地址开放 HTTP/S 入站访问
for i in `curl -s https://www.cloudflare.com/ips-v6`; do 
    echo "Adding Cloudflare IPv6: $i"
    ip6tables -I INPUT -s $i -p tcp -m multiport --dports 80,443 -j ACCEPT
done

# 保存 iptables 配置
echo "Saving rules..."
mkdir -p /etc/iptables/
iptables-save > /etc/iptables/rules.v4
ip6tables-save > /etc/iptables/rules.v6

echo "Done! Rules have been updated and saved."

# 显示当前规则
echo -e "\nCurrent IPv4 rules:"
iptables -L INPUT -n --line-numbers | grep -E "80|443"
echo -e "\nCurrent IPv6 rules:"
ip6tables -L INPUT -n --line-numbers | grep -E "80|443"