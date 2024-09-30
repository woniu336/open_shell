#!/usr/bin/env python3

import requests
import os
import sys

# 配置文件路径
CF_CONF = "/www/server/nginx/conf/cf.conf"

def get_cloudflare_ips():
    ipv4_url = "https://www.cloudflare-cn.com/ips-v4/"
    ipv6_url = "https://www.cloudflare-cn.com/ips-v6/"
    
    try:
        ipv4_response = requests.get(ipv4_url)
        ipv4_response.raise_for_status()
        ipv4_list = ipv4_response.text.strip().split('\n')
        
        ipv6_response = requests.get(ipv6_url)
        ipv6_response.raise_for_status()
        ipv6_list = ipv6_response.text.strip().split('\n')
        
        return ipv4_list, ipv6_list
    except requests.RequestException as e:
        print(f"请求 Cloudflare IP 列表时发生错误: {e}")
        return [], []

def update_cf_conf(ipv4_list, ipv6_list):
    if not ipv4_list and not ipv6_list:
        print("错误：没有找到 IP 地址。不进行更新。")
        return
    
    # 确保目录存在
    os.makedirs(os.path.dirname(CF_CONF), exist_ok=True)
    
    # 如果文件存在，创建备份
    if os.path.exists(CF_CONF):
        os.rename(CF_CONF, CF_CONF + '.bak')
        print(f"已备份原始文件到 {CF_CONF}.bak")
    else:
        print(f"正在创建新的 {CF_CONF} 文件")
    
    with open(CF_CONF, 'w') as f:
        f.write("# IPv4 地址\n")
        for ip in ipv4_list:
            f.write(f"set_real_ip_from {ip};\n")
        
        f.write("\n# IPv6 地址\n")
        for ip in ipv6_list:
            f.write(f"set_real_ip_from {ip};\n")
        
        f.write("\nreal_ip_header CF-Connecting-IP;\n")
    
    print(f"Cloudflare IP 地址已更新到 {CF_CONF}")

def main():
    try:
        ipv4_list, ipv6_list = get_cloudflare_ips()
        update_cf_conf(ipv4_list, ipv6_list)
        
        print(f"IPv4 地址数量: {len(ipv4_list)}")
        print(f"IPv6 地址数量: {len(ipv6_list)}")
        if os.path.exists(CF_CONF):
            print(f"cf.conf 中的总行数: {sum(1 for line in open(CF_CONF))}")
        else:
            print("警告：cf.conf 文件不存在")
    except Exception as e:
        print(f"更新过程中发生错误: {e}")
        print("错误详情:", sys.exc_info())

if __name__ == "__main__":
    main()