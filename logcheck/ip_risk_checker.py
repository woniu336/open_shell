import re
import os

# 定义日志分析结果文件路径
LOG_ANALYSIS_FILE = "/root/logcheck/log_analysis.txt"
WHITELIST_FILE = "/root/logcheck/ip_whitelist.txt"

def extract_suspicious_ips(log_analysis_file):
    suspicious_ips = []
    ip_regions = {}
    with open(log_analysis_file, 'r', encoding='utf-8') as f:
        content = f.read()
        # 使用正则表达式匹配可疑IP表格
        table_pattern = re.compile(r'## 可疑IP（每分钟访问20次以上）\s*\n\s*\|.*?\|(.*?)(?=\n\n|\Z)', re.DOTALL)
        table_match = table_pattern.search(content)
        if table_match:
            table_content = table_match.group(1)
            # 提取IP地址和地区
            ip_pattern = re.compile(r'\|\s*(\d{1,3}(?:\.\d{1,3}){3})\s*\|\s*\d+\s*\|\s*(\S+)\s*\|')
            matches = ip_pattern.findall(table_content)
            for ip, region in matches:
                suspicious_ips.append(ip)
                ip_regions[ip] = region
    return suspicious_ips, ip_regions

def block_ip(ip):
    os.system(f"sudo ufw insert 1 deny from {ip} to any")
    print(f"已拉黑IP: {ip}")

def unblock_ip(ip):
    os.system(f"sudo ufw delete deny from {ip} to any")
    print(f"已解封IP: {ip}")

def view_blocked_ips():
    os.system("sudo ufw status | grep DENY")

def view_ufw_status():
    os.system("sudo ufw status")

def add_to_whitelist(ip):
    # 读取现有白名单
    existing_ips = load_whitelist()
    if ip in existing_ips:
        print(f"IP {ip} 已在白名单中，跳过添加。")
        return

    with open(WHITELIST_FILE, 'a') as f:
        f.write(ip + '\n')
    print(f"已将IP {ip} 添加到白名单。")

def load_whitelist():
    if os.path.exists(WHITELIST_FILE):
        with open(WHITELIST_FILE, 'r') as f:
            return {line.strip() for line in f}
    return set()

def menu(suspicious_ips, ip_regions, whitelist):
    while True:
        print("\n菜单:")
        print("1. 拉黑全部可疑IP")
        print("2. 拉黑国外IP（除亚洲外）")
        print("3. 手动拉黑IP")
        print("4. 手动解封IP")
        print("5. 查看拉黑列表")
        print("6. 查看UFW状态")
        print("7. 添加IP到白名单")
        print("0. 退出")
        choice = input("请选择一个选项: ")

        if choice == '1':
            for ip in suspicious_ips:
                if ip not in whitelist:
                    block_ip(ip)
        elif choice == '2':
            for ip in suspicious_ips:
                if ip not in whitelist and ip_regions[ip] not in ["亚洲"]:
                    block_ip(ip)
        elif choice == '3':
            ip_to_block = input("请输入要拉黑的IP: ")
            block_ip(ip_to_block)
        elif choice == '4':
            ip_to_unblock = input("请输入要解封的IP: ")
            unblock_ip(ip_to_unblock)
        elif choice == '5':
            view_blocked_ips()
        elif choice == '6':
            view_ufw_status()
        elif choice == '7':
            ip_to_whitelist = input("请输入要添加到白名单的IP: ")
            add_to_whitelist(ip_to_whitelist)
        elif choice == '0':
            break
        else:
            print("无效选项，请重试。")

def main():
    suspicious_ips, ip_regions = extract_suspicious_ips(LOG_ANALYSIS_FILE)
    whitelist = load_whitelist()
    
    if not suspicious_ips:
        print("未找到可疑IP。")
        return

    print(f"找到 {len(suspicious_ips)} 个可疑IP：")
    for ip in suspicious_ips:
        print(f"- {ip}")

    menu(suspicious_ips, ip_regions, whitelist)

if __name__ == "__main__":
    main()