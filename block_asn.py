#!/usr/bin/env python3
# block_asn_interactive.py - ASN封禁管理工具（交互式菜单版）

import sys
import subprocess
import os
import ipaddress
from datetime import datetime

# ============== 依赖检测模块 ==============

def check_command(cmd):
    """检查命令是否存在"""
    try:
        subprocess.run(['which', cmd], capture_output=True, check=True)
        return True
    except subprocess.CalledProcessError:
        return False

def check_python_module(module_name):
    """检查Python模块是否已安装"""
    try:
        __import__(module_name)
        return True
    except ImportError:
        return False

def check_root():
    """检查是否有root权限"""
    return os.geteuid() == 0

def check_all_dependencies(silent=False):
    """检查所有依赖"""
    issues = []
    
    # 检查root权限
    if not check_root():
        issues.append("root")
    
    # 检查系统命令
    commands = ['ipset', 'iptables', 'ip6tables']
    for cmd in commands:
        if not check_command(cmd):
            issues.append(cmd)
    
    # 检查Python模块
    if not check_python_module('requests'):
        issues.append('requests')
    
    if issues and not silent:
        print("\n" + "=" * 60)
        print("⚠  系统依赖检测失败")
        print("=" * 60)
        print("\n发现缺失依赖，请先安装：")
        if 'root' in issues:
            print("  - 使用 sudo 运行此脚本")
        if 'ipset' in issues or 'iptables' in issues or 'ip6tables' in issues:
            print("  Debian/Ubuntu: sudo apt install ipset iptables")
            print("  CentOS/RHEL:   sudo yum install ipset iptables")
        if 'requests' in issues:
            print("  安装Python库:  pip3 install requests")
        print()
        return False
    
    return len(issues) == 0

# ============== 核心功能模块 ==============

def run_command(cmd, ignore_error=False, capture=True):
    """执行系统命令"""
    try:
        if capture:
            result = subprocess.run(cmd, shell=True, capture_output=True, text=True, check=True)
            return True, result.stdout
        else:
            subprocess.run(cmd, shell=True, check=True)
            return True, ""
    except subprocess.CalledProcessError as e:
        if not ignore_error:
            return False, e.stderr if capture else ""
        return False, ""

def get_asn_networks(asn):
    """获取指定ASN的所有IP网段"""
    import requests
    
    asn_clean = asn.replace('AS', '').replace('as', '')
    url = f"https://stat.ripe.net/data/announced-prefixes/data.json?resource=AS{asn_clean}"
    
    try:
        print(f"正在查询 ASN {asn_clean}...")
        response = requests.get(url, timeout=30)
        response.raise_for_status()
        data = response.json()
        
        if data.get('status') != 'ok':
            return [], []

        ipv4_nets = []
        ipv6_nets = []
        
        if 'data' in data and 'prefixes' in data['data']:
            for prefix_info in data['data']['prefixes']:
                prefix = prefix_info['prefix']
                try:
                    net = ipaddress.ip_network(prefix)
                    if net.version == 4:
                        ipv4_nets.append(prefix)
                    else:
                        ipv6_nets.append(prefix)
                except ValueError:
                    continue
        
        return ipv4_nets, ipv6_nets
    except Exception as e:
        print(f"✗ 获取ASN信息时出错: {e}")
        return [], []

def create_ipset(set_name, ip_family='inet'):
    """创建ipset集合"""
    run_command(f"ipset destroy {set_name}", ignore_error=True)
    success, _ = run_command(f"ipset create {set_name} hash:net family {ip_family} maxelem 100000")
    if success:
        print(f"✓ 创建ipset: {set_name}")
        return True
    return False

def add_networks_to_ipset(set_name, networks):
    """批量添加网段到ipset"""
    if not networks:
        return 0
    
    commands = [f"add {set_name} {net}" for net in networks]
    restore_input = "\n".join(commands)
    
    try:
        process = subprocess.Popen(
            ['ipset', 'restore', '-exist'],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        stdout, stderr = process.communicate(input=restore_input)
        
        if process.returncode == 0:
            print(f"✓ 已添加 {len(networks)} 个网段到 {set_name}")
            return len(networks)
        else:
            print(f"✗ 添加网段失败: {stderr}")
            return 0
    except Exception as e:
        print(f"✗ 批量添加出错: {e}")
        return 0

def add_iptables_rule(set_name, chain='INPUT'):
    """添加iptables规则"""
    check_cmd = f"iptables -C {chain} -m set --match-set {set_name} src -j DROP 2>/dev/null"
    success, _ = run_command(check_cmd, ignore_error=True)
    
    if success:
        print(f"  规则已存在于 {chain} 链")
        return True
    
    add_cmd = f"iptables -I {chain} 1 -m set --match-set {set_name} src -j DROP"
    success, _ = run_command(add_cmd)
    if success:
        print(f"✓ 添加iptables规则: {set_name}")
        return True
    return False

def add_ip6tables_rule(set_name, chain='INPUT'):
    """添加ip6tables规则"""
    check_cmd = f"ip6tables -C {chain} -m set --match-set {set_name} src -j DROP 2>/dev/null"
    success, _ = run_command(check_cmd, ignore_error=True)
    
    if success:
        print(f"  规则已存在于 {chain} 链")
        return True
    
    add_cmd = f"ip6tables -I {chain} 1 -m set --match-set {set_name} src -j DROP"
    success, _ = run_command(add_cmd)
    if success:
        print(f"✓ 添加ip6tables规则: {set_name}")
        return True
    return False

# ============== 菜单功能模块 ==============

def block_asn():
    """封禁ASN"""
    print("\n" + "=" * 60)
    print("封禁ASN")
    print("=" * 60)
    
    asn_input = input("请输入要封禁的ASN（多个用空格分隔，如: AS13335 AS15169）: ").strip()
    if not asn_input:
        print("✗ 未输入ASN")
        return
    
    asn_list = asn_input.split()
    
    for asn in asn_list:
        asn_clean = asn.replace('AS', '').replace('as', '')
        print(f"\n{'─' * 60}")
        print(f"处理 ASN {asn_clean}")
        print(f"{'─' * 60}")
        
        ipv4_nets, ipv6_nets = get_asn_networks(asn_clean)
        
        if not ipv4_nets and not ipv6_nets:
            print(f"✗ 未找到 ASN {asn_clean} 的网段")
            continue
        
        print(f"找到 IPv4: {len(ipv4_nets)} 个, IPv6: {len(ipv6_nets)} 个")
        
        if ipv4_nets:
            set_name_v4 = f"blocked_asn{asn_clean}_v4"
            if create_ipset(set_name_v4, 'inet'):
                add_networks_to_ipset(set_name_v4, ipv4_nets)
                add_iptables_rule(set_name_v4)
        
        if ipv6_nets:
            set_name_v6 = f"blocked_asn{asn_clean}_v6"
            if create_ipset(set_name_v6, 'inet6'):
                add_networks_to_ipset(set_name_v6, ipv6_nets)
                add_ip6tables_rule(set_name_v6)
    
    save_config()
    print("\n✓ 封禁完成")

def list_blocked():
    """列出已封禁的ASN"""
    print("\n" + "=" * 60)
    print("已封禁的ASN集合")
    print("=" * 60)
    
    success, output = run_command("ipset list -name | grep blocked_asn")
    if success and output.strip():
        sets = output.strip().split('\n')
        for s in sets:
            # 获取集合详情
            success2, detail = run_command(f"ipset list {s} | grep 'Number of entries'")
            if success2:
                count = detail.strip().split(':')[1].strip()
                print(f"  {s:30} - {count} 个网段")
            else:
                print(f"  {s}")
    else:
        print("  (无)")

def view_ipset_details():
    """查看ipset集合详情"""
    print("\n" + "=" * 60)
    print("查看集合详情")
    print("=" * 60)
    
    success, output = run_command("ipset list -name | grep blocked_asn")
    if not success or not output.strip():
        print("  (无已封禁的集合)")
        return
    
    sets = output.strip().split('\n')
    print("\n可用的集合:")
    for i, s in enumerate(sets, 1):
        print(f"  {i}. {s}")
    
    choice = input("\n请输入集合编号（直接回车返回）: ").strip()
    if not choice:
        return
    
    try:
        idx = int(choice) - 1
        if 0 <= idx < len(sets):
            set_name = sets[idx]
            print(f"\n{'─' * 60}")
            print(f"集合: {set_name}")
            print(f"{'─' * 60}")
            success, output = run_command(f"ipset list {set_name}")
            if success:
                print(output)
        else:
            print("✗ 无效的编号")
    except ValueError:
        print("✗ 请输入数字")

def view_iptables_rules():
    """查看iptables规则"""
    print("\n" + "=" * 60)
    print("iptables/ip6tables 规则")
    print("=" * 60)
    
    print("\nIPv4 规则:")
    success, output = run_command("iptables -L INPUT -n -v | grep match-set")
    if success and output.strip():
        print(output)
    else:
        print("  (无)")
    
    print("\nIPv6 规则:")
    success, output = run_command("ip6tables -L INPUT -n -v | grep match-set")
    if success and output.strip():
        print(output)
    else:
        print("  (无)")

def test_ip():
    """测试IP是否被封禁"""
    print("\n" + "=" * 60)
    print("测试IP是否被封禁")
    print("=" * 60)
    
    ip = input("请输入要测试的IP地址: ").strip()
    if not ip:
        return
    
    # 判断IP版本
    try:
        ip_obj = ipaddress.ip_address(ip)
        if ip_obj.version == 4:
            pattern = "blocked_asn.*_v4"
        else:
            pattern = "blocked_asn.*_v6"
    except ValueError:
        print("✗ 无效的IP地址")
        return
    
    success, output = run_command(f"ipset list -name | grep -E '{pattern}'")
    if not success or not output.strip():
        print(f"  未找到对应的封禁集合")
        return
    
    sets = output.strip().split('\n')
    print(f"\n测试结果:")
    found = False
    for s in sets:
        success, _ = run_command(f"ipset test {s} {ip}", ignore_error=True)
        if success:
            print(f"  ✓ {ip} 在集合 {s} 中（已封禁）")
            found = True
    
    if not found:
        print(f"  ✗ {ip} 未被封禁")

def remove_block():
    """移除封禁"""
    print("\n" + "=" * 60)
    print("移除ASN封禁")
    print("=" * 60)
    
    success, output = run_command("ipset list -name | grep blocked_asn")
    if not success or not output.strip():
        print("  (无已封禁的集合)")
        return
    
    sets = output.strip().split('\n')
    print("\n可用的集合:")
    for i, s in enumerate(sets, 1):
        print(f"  {i}. {s}")
    
    choice = input("\n请输入要删除的集合编号（多个用空格分隔，直接回车返回）: ").strip()
    if not choice:
        return
    
    try:
        indices = [int(x) - 1 for x in choice.split()]
        for idx in indices:
            if 0 <= idx < len(sets):
                set_name = sets[idx]
                
                # 删除iptables规则
                if '_v4' in set_name:
                    run_command(f"iptables -D INPUT -m set --match-set {set_name} src -j DROP", ignore_error=True)
                else:
                    run_command(f"ip6tables -D INPUT -m set --match-set {set_name} src -j DROP", ignore_error=True)
                
                # 删除ipset
                success, _ = run_command(f"ipset destroy {set_name}")
                if success:
                    print(f"✓ 已删除集合: {set_name}")
            else:
                print(f"✗ 无效的编号: {idx + 1}")
        
        save_config()
    except ValueError:
        print("✗ 请输入有效的数字")

def view_block_statistics():
    """查看封禁统计（包含拦截数量）"""
    print("\n" + "=" * 60)
    print("封禁统计 - 实时拦截数据")
    print("=" * 60)
    
    print("\nIPv4 封禁规则统计:")
    print("─" * 60)
    success, output = run_command("iptables -L INPUT -n -v | grep match-set")
    if success and output.strip():
        print(f"{'数据包数':<12} {'字节数':<12} {'集合名称':<30}")
        print("─" * 60)
        for line in output.strip().split('\n'):
            parts = line.split()
            if len(parts) >= 8:
                pkts = parts[0]
                bytes_val = parts[1]
                # 查找包含 blocked_asn 的部分
                set_name = "未知"
                for part in parts:
                    if 'blocked_asn' in part:
                        set_name = part
                        break
                print(f"{pkts:<12} {bytes_val:<12} {set_name:<30}")
    else:
        print("  (无)")
    
    print("\nIPv6 封禁规则统计:")
    print("─" * 60)
    success, output = run_command("ip6tables -L INPUT -n -v | grep match-set")
    if success and output.strip():
        print(f"{'数据包数':<12} {'字节数':<12} {'集合名称':<30}")
        print("─" * 60)
        for line in output.strip().split('\n'):
            parts = line.split()
            if len(parts) >= 8:
                pkts = parts[0]
                bytes_val = parts[1]
                # 查找包含 blocked_asn 的部分
                set_name = "未知"
                for part in parts:
                    if 'blocked_asn' in part:
                        set_name = part
                        break
                print(f"{pkts:<12} {bytes_val:<12} {set_name:<30}")
    else:
        print("  (无)")
    
    print("\n" + "=" * 60)
    print("💡 提示:")
    print("  - 数据包数：已拦截的数据包数量")
    print("  - 字节数：已拦截的流量大小（字节）")
    print("=" * 60)

def save_config():
    """保存配置"""
    run_command("ipset save > /etc/ipset.conf", ignore_error=True)
    run_command("iptables-save > /etc/iptables/rules.v4", ignore_error=True)
    run_command("ip6tables-save > /etc/iptables/rules.v6", ignore_error=True)

def query_asn_info():
    """查询ASN信息（不封禁）"""
    print("\n" + "=" * 60)
    print("查询ASN信息")
    print("=" * 60)
    
    asn = input("请输入要查询的ASN: ").strip()
    if not asn:
        return
    
    asn_clean = asn.replace('AS', '').replace('as', '')
    ipv4_nets, ipv6_nets = get_asn_networks(asn_clean)
    
    if not ipv4_nets and not ipv6_nets:
        print(f"✗ 未找到 ASN {asn_clean} 的网段")
        return
    
    print(f"\nASN {asn_clean} 信息:")
    print(f"  IPv4 网段数: {len(ipv4_nets)}")
    print(f"  IPv6 网段数: {len(ipv6_nets)}")
    
    if ipv4_nets and input("\n显示IPv4网段? (y/n): ").lower() == 'y':
        print("\nIPv4 网段:")
        for net in ipv4_nets[:20]:  # 只显示前20个
            print(f"  {net}")
        if len(ipv4_nets) > 20:
            print(f"  ... (还有 {len(ipv4_nets) - 20} 个)")
    
    if ipv6_nets and input("\n显示IPv6网段? (y/n): ").lower() == 'y':
        print("\nIPv6 网段:")
        for net in ipv6_nets[:20]:
            print(f"  {net}")
        if len(ipv6_nets) > 20:
            print(f"  ... (还有 {len(ipv6_nets) - 20} 个)")

# ============== 主菜单 ==============

def show_menu():
    """显示主菜单"""
    print("\n" + "╔" + "═" * 58 + "╗")
    print("║" + " " * 10 + "ASN 封禁管理工具 - 交互式菜单" + " " * 18 + "║")
    print("╚" + "═" * 58 + "╝")
    print()
    print("  ┌─ 核心功能 " + "─" * 44 + "┐")
    print("  │                                                          │")
    print("  │  [1] 🚫 封禁 ASN                                         │")
    print("  │  [2] 🔍 查询 ASN 信息（不封禁）                          │")
    print("  │  [3] ✅ 移除封禁                                         │")
    print("  │                                                          │")
    print("  └" + "─" * 58 + "┘")
    print()
    print("  ┌─ 查询功能 " + "─" * 44 + "┐")
    print("  │                                                          │")
    print("  │  [4] 📋 列出已封禁的 ASN                                 │")
    print("  │  [5] 📊 查看集合详情                                     │")
    print("  │  [6] 🔧 查看 iptables 规则                               │")
    print("  │  [7] 🎯 测试 IP 是否被封禁                               │")
    print("  │                                                          │")
    print("  └" + "─" * 58 + "┘")
    print()
    print("  ┌─ 系统功能 " + "─" * 44 + "┐")
    print("  │                                                          │")
    print("  │  [8] 📈 查看封禁统计（拦截数据）                         │")
    print("  │  [0] 👋 退出程序                                         │")
    print("  │                                                          │")
    print("  └" + "─" * 58 + "┘")

def main():
    """主程序"""
    # 静默检查依赖
    if not check_all_dependencies(silent=True):
        check_all_dependencies(silent=False)
        sys.exit(1)
    
    while True:
        show_menu()
        choice = input("\n  ➤ 请选择功能 [0-8]: ").strip()
        
        if choice == '1':
            block_asn()
        elif choice == '2':
            query_asn_info()
        elif choice == '3':
            remove_block()
        elif choice == '4':
            list_blocked()
        elif choice == '5':
            view_ipset_details()
        elif choice == '6':
            view_iptables_rules()
        elif choice == '7':
            test_ip()
        elif choice == '8':
            view_block_statistics()
        elif choice == '0':
            print("\n  👋 再见！感谢使用。\n")
            break
        else:
            print("\n  ✗ 无效的选择，请重新输入")
        
        input("\n  ⏎ 按回车键继续...")

if __name__ == "__main__":
    main()
