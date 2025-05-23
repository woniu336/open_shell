#!/usr/bin/env python3
"""
Google Bot IP屏蔽脚本
从Google官方API获取Googlebot IP范围并生成屏蔽规则
"""

import requests
import json
import ipaddress
import subprocess
import sys
from typing import List, Tuple

class GoogleBotBlocker:
    def __init__(self):
        self.api_url = "https://developers.google.com/search/apis/ipranges/googlebot.json"
        self.ipv4_ranges = []
        self.ipv6_ranges = []
        
    def fetch_ip_ranges(self) -> bool:
        """从Google API获取IP范围"""
        try:
            print("正在从Google API获取Googlebot IP范围...")
            response = requests.get(self.api_url, timeout=10)
            response.raise_for_status()
            
            data = response.json()
            
            # 解析IP范围
            for prefix in data.get('prefixes', []):
                if 'ipv4Prefix' in prefix:
                    self.ipv4_ranges.append(prefix['ipv4Prefix'])
                elif 'ipv6Prefix' in prefix:
                    self.ipv6_ranges.append(prefix['ipv6Prefix'])
            
            print(f"✓ 成功获取IP范围")
            print(f"  - IPv4范围: {len(self.ipv4_ranges)}个")
            print(f"  - IPv6范围: {len(self.ipv6_ranges)}个")
            return True
            
        except requests.RequestException as e:
            print(f"✗ 获取IP范围失败: {e}")
            return False
        except json.JSONDecodeError as e:
            print(f"✗ 解析JSON数据失败: {e}")
            return False
    
    def generate_iptables_rules(self) -> Tuple[List[str], List[str]]:
        """生成iptables屏蔽规则"""
        ipv4_rules = []
        ipv6_rules = []
        
        # 生成IPv4规则
        for ip_range in self.ipv4_ranges:
            rule = f"iptables -A INPUT -s {ip_range} -j DROP"
            ipv4_rules.append(rule)
        
        # 生成IPv6规则
        for ip_range in self.ipv6_ranges:
            rule = f"ip6tables -A INPUT -s {ip_range} -j DROP"
            ipv6_rules.append(rule)
        
        return ipv4_rules, ipv6_rules
    
    def save_rules_to_file(self, ipv4_rules: List[str], ipv6_rules: List[str]) -> None:
        """保存规则到文件"""
        # 保存IPv4规则
        with open('block_googlebot_ipv4.sh', 'w', encoding='utf-8') as f:
            f.write("#!/bin/bash\n")
            f.write("# Google Bot IPv4屏蔽规则\n")
            f.write("# 自动生成于: $(date)\n\n")
            f.write("echo '正在添加IPv4屏蔽规则...'\n")
            for rule in ipv4_rules:
                f.write(f"{rule}\n")
            f.write("echo 'IPv4规则添加完成'\n")
        
        # 保存IPv6规则
        with open('block_googlebot_ipv6.sh', 'w', encoding='utf-8') as f:
            f.write("#!/bin/bash\n")
            f.write("# Google Bot IPv6屏蔽规则\n")
            f.write("# 自动生成于: $(date)\n\n")
            f.write("echo '正在添加IPv6屏蔽规则...'\n")
            for rule in ipv6_rules:
                f.write(f"{rule}\n")
            f.write("echo 'IPv6规则添加完成'\n")
        
        # 设置执行权限
        try:
            subprocess.run(['chmod', '+x', 'block_googlebot_ipv4.sh'], check=True)
            subprocess.run(['chmod', '+x', 'block_googlebot_ipv6.sh'], check=True)
        except subprocess.CalledProcessError:
            print("注意: 无法设置脚本执行权限，请手动执行 chmod +x *.sh")
    
    def generate_removal_script(self) -> None:
        """生成移除Googlebot屏蔽规则的脚本"""
        # 保存移除脚本
        with open('remove_googlebot_block.sh', 'w', encoding='utf-8') as f:
            f.write("#!/bin/bash\n")
            f.write("# 移除Google Bot屏蔽规则\n")
            f.write("# 自动生成\n\n")
            
            f.write("echo '正在移除Googlebot屏蔽规则...'\n\n")
            
            # 方法1: 使用-D参数精确删除规则
            f.write("# 方法1: 精确删除规则\n")
            for ip_range in self.ipv4_ranges:
                f.write(f"iptables -D INPUT -s {ip_range} -j DROP 2>/dev/null\n")
            for ip_range in self.ipv6_ranges:
                f.write(f"ip6tables -D INPUT -s {ip_range} -j DROP 2>/dev/null\n")
            
            f.write("\n# 方法2: 按行号删除(备用方法)\n")
            f.write("# 获取包含Googlebot IP的规则行号并删除\n")
            
            # IPv4规则按行号删除
            f.write("echo '按行号删除IPv4规则...'\n")
            for ip_range in self.ipv4_ranges:
                # 转义点号用于grep
                escaped_ip = ip_range.replace('.', '\\.')
                f.write(f"while true; do\n")
                f.write(f"  LINE=$(iptables -L INPUT --line-numbers -n | grep '{escaped_ip}' | head -1 | awk '{{print $1}}')\n")
                f.write(f"  [ -z \"$LINE\" ] && break\n")
                f.write(f"  iptables -D INPUT $LINE\n")
                f.write(f"  echo '删除IPv4规则行: '$LINE\n")
                f.write(f"done\n")
            
            # IPv6规则按行号删除
            f.write("echo '按行号删除IPv6规则...'\n")
            for ip_range in self.ipv6_ranges:
                f.write(f"while true; do\n")
                f.write(f"  LINE=$(ip6tables -L INPUT --line-numbers -n | grep '{ip_range}' | head -1 | awk '{{print $1}}')\n")
                f.write(f"  [ -z \"$LINE\" ] && break\n")
                f.write(f"  ip6tables -D INPUT $LINE\n")
                f.write(f"  echo '删除IPv6规则行: '$LINE\n")
                f.write(f"done\n")
            
            f.write("\necho 'Googlebot屏蔽规则移除完成'\n")
            f.write("echo '验证移除结果:'\n")
            f.write("echo 'IPv4剩余Googlebot规则:'\n")
            f.write("iptables -L INPUT -n | grep -E '(66\\.249\\.|64\\.233\\.|72\\.14\\.|74\\.125\\.|209\\.85\\.|216\\.239\\.)' || echo '未发现Googlebot IPv4规则'\n")
            f.write("echo 'IPv6剩余Googlebot规则:'\n")
            f.write("ip6tables -L INPUT -n | grep -E '2001:4860' || echo '未发现Googlebot IPv6规则'\n")
        
        # 设置执行权限
        try:
            subprocess.run(['chmod', '+x', 'remove_googlebot_block.sh'], check=True)
        except subprocess.CalledProcessError:
            pass
    
    def apply_rules(self) -> bool:
        """应用屏蔽规则（需要root权限）"""
        try:
            print("\n是否立即应用屏蔽规则？(需要root权限) [y/N]: ", end='')
            choice = input().lower().strip()
            
            if choice in ['y', 'yes']:
                print("正在应用IPv4屏蔽规则...")
                result = subprocess.run(['bash', 'block_googlebot_ipv4.sh'], 
                                      capture_output=True, text=True)
                if result.returncode != 0:
                    print(f"IPv4规则应用失败: {result.stderr}")
                    return False
                
                print("正在应用IPv6屏蔽规则...")
                result = subprocess.run(['bash', 'block_googlebot_ipv6.sh'], 
                                      capture_output=True, text=True)
                if result.returncode != 0:
                    print(f"IPv6规则应用失败: {result.stderr}")
                    return False
                
                return True
            else:
                print("跳过规则应用，请手动执行生成的脚本文件")
                return True
                
        except Exception as e:
            print(f"应用规则时发生错误: {e}")
            return False
    
    def validate_blocking(self) -> bool:
        """验证屏蔽规则是否生效"""
        try:
            print("\n正在验证屏蔽规则...")
            
            # 检查iptables规则中是否包含DROP规则
            result = subprocess.run(['iptables', '-L', 'INPUT', '-n'], 
                                  capture_output=True, text=True)
            
            ipv4_blocked = 0
            if result.returncode == 0:
                # 检查每个IP范围是否在规则中
                for ip_range in self.ipv4_ranges:
                    if ip_range in result.stdout and "DROP" in result.stdout:
                        ipv4_blocked += 1
            
            print(f"✓ 已验证 {ipv4_blocked}/{len(self.ipv4_ranges)} 个IPv4范围被屏蔽")
            
            # 检查ip6tables规则
            ipv6_blocked = 0
            try:
                result = subprocess.run(['ip6tables', '-L', 'INPUT', '-n'], 
                                      capture_output=True, text=True)
                if result.returncode == 0:
                    for ip_range in self.ipv6_ranges:
                        if ip_range in result.stdout and "DROP" in result.stdout:
                            ipv6_blocked += 1
                print(f"✓ 已验证 {ipv6_blocked}/{len(self.ipv6_ranges)} 个IPv6范围被屏蔽")
            except FileNotFoundError:
                print("注意: 系统不支持IPv6或ip6tables未安装")
            
            # 提供额外的验证方法
            self.show_verification_methods()
            
            return ipv4_blocked > 0 or ipv6_blocked > 0
            
        except Exception as e:
            print(f"验证过程中发生错误: {e}")
            return False
    
    def show_verification_methods(self) -> None:
        """显示其他验证屏蔽效果的方法"""
        print(f"\n检查防火墙日志:")
        print(f"   journalctl -f | grep -i drop")
        print(f"   或: dmesg | grep -i iptables")
    
    def run(self) -> None:
        """主执行函数"""
        print("=" * 50)
        print("Google Bot IP屏蔽脚本")
        print("=" * 50)
        
        # 获取IP范围
        if not self.fetch_ip_ranges():
            sys.exit(1)
        
        # 生成屏蔽规则
        print(f"\n正在生成屏蔽规则...")
        ipv4_rules, ipv6_rules = self.generate_iptables_rules()
        
        # 保存到文件
        self.save_rules_to_file(ipv4_rules, ipv6_rules)
        print(f"✓ 规则已保存到文件:")
        print(f"  - block_googlebot_ipv4.sh ({len(ipv4_rules)}条规则)")
        print(f"  - block_googlebot_ipv6.sh ({len(ipv6_rules)}条规则)")
        
        # 生成移除脚本
        self.generate_removal_script()
        print(f"  - remove_googlebot_block.sh (移除脚本)")
        
        # 应用规则
        rules_applied = self.apply_rules()
        
        # 验证屏蔽效果
        if rules_applied:
            validation_success = self.validate_blocking()
            if validation_success:
                print(f"\n✓ 屏蔽执行成功!")
                print(f"  - 已屏蔽 {len(self.ipv4_ranges)} 个IPv4范围")
                print(f"  - 已屏蔽 {len(self.ipv6_ranges)} 个IPv6范围")
            else:
                print(f"\n⚠ 屏蔽可能未完全生效，请检查防火墙配置")
        
        print(f"\n" + "=" * 50)
        print(f"🚫 移除Googlebot屏蔽:")
        print(f"=" * 50)
        print(f"sudo bash remove_googlebot_block.sh")
        print(f"=" * 50)


def main():
    """主函数"""
    try:
        blocker = GoogleBotBlocker()
        blocker.run()
    except KeyboardInterrupt:
        print("\n\n操作被用户取消")
        sys.exit(0)
    except Exception as e:
        print(f"\n程序执行出错: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()