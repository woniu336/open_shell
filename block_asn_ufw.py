#!/usr/bin/env python3
# block_asn_ufw.py

import sys
import subprocess
import requests
import ipaddress
from datetime import datetime

def get_asn_networks(asn):
    """获取指定ASN的所有IP网段"""
    url = f"https://api.bgpview.io/asn/{asn}/prefixes"
    try:
        response = requests.get(url)
        response.raise_for_status()
        data = response.json()
        
        if data['status'] != 'ok':
            print(f"获取ASN {asn}信息失败")
            return []

        networks = []
        for prefix in data['data']['ipv4_prefixes']:
            networks.append(prefix['prefix'])
        for prefix in data['data']['ipv6_prefixes']:
            networks.append(prefix['prefix'])
        
        return networks
    except Exception as e:
        print(f"获取ASN信息时出错: {e}")
        return []

def backup_ufw_rules():
    """备份当前UFW规则"""
    timestamp = datetime.now().strftime('%Y-%m-%d_%H-%M-%S')
    backup_file = f"ufw_backup_{timestamp}.txt"
    try:
        subprocess.run(['sudo', 'ufw', 'status', 'numbered'], 
                      stdout=open(backup_file, 'w'), 
                      check=True)
        print(f"UFW规则已备份到: {backup_file}")
    except subprocess.CalledProcessError as e:
        print(f"备份UFW规则失败: {e}")
        sys.exit(1)

def get_first_v6_position():
    """获取第一条IPv6规则的位置"""
    try:
        result = subprocess.run(['sudo', 'ufw', 'status', 'numbered'],
                              capture_output=True, text=True, check=True)
        lines = result.stdout.splitlines()
        for line in lines:
            if '(v6)' in line:
                position = line.split('[')[1].split(']')[0]
                return int(position)
        return len(lines) + 1
    except subprocess.CalledProcessError as e:
        print(f"获取IPv6规则位置失败: {e}")
        return 1

def add_ufw_rules(networks):
    """添加UFW规则"""
    v6_position = get_first_v6_position()
    current_v4_position = 1
    current_v6_position = v6_position

    for network in networks:
        try:
            net = ipaddress.ip_network(network)
            position = current_v6_position if net.version == 6 else current_v4_position
            
            cmd = ['sudo', 'ufw', 'insert', str(position), 
                   'deny', 'from', network, 'to', 'any']
            
            subprocess.run(cmd, check=True)
            print(f"已添加规则: deny from {network} at position {position}")
            
            if net.version == 6:
                current_v6_position += 1
            else:
                current_v4_position += 1
        except subprocess.CalledProcessError as e:
            print(f"添加规则失败 {network}: {e}")
        except ValueError as e:
            print(f"无效的网络地址 {network}: {e}")

def main():
    if len(sys.argv) < 2:
        print("使用方法: python3 block_asn_ufw.py ASN1 [ASN2 ...]")
        print("示例: python3 block_asn_ufw.py 394711 394712")
        sys.exit(1)

    # 备份当前UFW规则
    backup_ufw_rules()

    # 获取并添加每个ASN的规则
    for asn in sys.argv[1:]:
        print(f"\n处理 ASN {asn}...")
        networks = get_asn_networks(asn)
        if networks:
            print(f"找到 {len(networks)} 个网段")
            add_ufw_rules(networks)
        else:
            print(f"未找到 ASN {asn} 的网段")

    # 重新加载UFW规则
    try:
        subprocess.run(['sudo', 'ufw', 'reload'], check=True)
        print("\nUFW规则已重新加载")
    except subprocess.CalledProcessError as e:
        print(f"重新加载UFW规则失败: {e}")

if __name__ == "__main__":
    main()