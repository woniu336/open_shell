import re
from collections import defaultdict
from datetime import datetime, timedelta
import ipaddress
import sys

# 定义白名单文件路径
WHITELIST_FILE = "/root/logcheck/ip_whitelist.txt"

# 定义日志文件路径
LOG_PATHS = [
    "/www/wwwlogs/123.log",
    # 在这里添加更多日志文件路径
]

# 攻击类型和模式（预编译正则表达式）
ATTACK_PATTERNS = {
    re.compile(r"/admin|/login\.php|/manage|/dashboard|/control"): "后台页面访问",
    re.compile(r"SELECT.*FROM|UNION.*SELECT|INSERT.*INTO|UPDATE.*SET|DELETE.*FROM"): "SQL注入尝试",
    re.compile(r"<script>|javascript:|onerror=|onload="): "XSS攻击尝试",
    re.compile(r"\.\.\/|\..\\"): "目录遍历尝试",
    re.compile(r"include\(|require\(|include_once\(|require_once\("): "文件包含尝试",
    re.compile(r"\.git|\.env|\.config|\.bak|\.old|\.txt|\.log"): "敏感文件访问",
    re.compile(r"\`|\$\(|\&\&|\|\|"): "命令注入尝试",
    re.compile(r"\.vscode|sftp\.json"): "IDE配置扫描",
    re.compile(r"/wordpress|wp-includes|wp-content|wp-admin|wp-login\.php"): "WordPress扫描",
    re.compile(r"joomla\.xml|configuration\.php|com_content"): "Joomla扫描",
    re.compile(r"maccms|thinkphp|laravel|codeigniter|yii|zend|cakephp|drupal"): "CMS框架扫描"
}

# 搜索引擎爬虫用户代理
SEARCH_ENGINE_BOTS = [
    "Googlebot", "Bingbot", "Baiduspider", "YandexBot", "Sogou",
    "DuckDuckBot", "Slurp", "ia_archiver", "AhrefsBot", "Bytespider"
]

# 白名单路径（预编译正则表达式）
WHITELISTED_PATHS = [
    re.compile(r'/index\.php/ajax/hits'),
    re.compile(r'/index\.php/user/ajax_ulog'),
    re.compile(r'/video/\d+\.html'),
    re.compile(r'/play/\d+-\d+-\d+\.html'),
    re.compile(r'/show/')
]

def load_whitelist():
    whitelist = set()
    try:
        with open(WHITELIST_FILE, 'r') as f:
            for line in f:
                whitelist.add(line.strip())
    except FileNotFoundError:
        print(f"警告: 白名单文件 {WHITELIST_FILE} 不存在。")
    return whitelist

def parse_log_line(line):
    pattern = r'(\d+\.\d+\.\d+\.\d+).*\[([^\]]+)\] "([^"]*)" (\d+) \d+ "[^"]*" "([^"]*)"'
    match = re.search(pattern, line)
    if match:
        ip, timestamp, request, status, user_agent = match.groups()
        return {
            "ip": ip,
            "timestamp": datetime.strptime(timestamp, "%d/%b/%Y:%H:%M:%S %z"),
            "request": request,
            "status": int(status),
            "user_agent": user_agent
        }
    return None

def is_search_engine_bot(user_agent):
    return any(bot.lower() in user_agent.lower() for bot in SEARCH_ENGINE_BOTS)

def identify_attack_type(request, user_agent):
    for pattern, attack_type in ATTACK_PATTERNS.items():
        if pattern.search(request):
            return attack_type
    
    if "bot" in user_agent.lower() and not is_search_engine_bot(user_agent):
        return "可疑扫描"
    
    if re.search(r'[^\w\s]{4,}', request):
        return "可疑扫描"
    
    if len(request.split('?')[1]) > 200 if '?' in request else False:
        return "可疑扫描"
    
    unusual_extensions = r'\.(cgi|pl|exe|dll|jsp|action|do|xml)$'
    if re.search(unusual_extensions, request, re.IGNORECASE):
        return "可疑扫描"

    return None

def is_private_ip(ip):
    try:
        return ipaddress.ip_address(ip).is_private
    except ValueError:
        return False

def is_whitelisted_request(request):
    return any(pattern.search(request) for pattern in WHITELISTED_PATHS)

def analyze_logs(log_paths, whitelist):
    attacks = defaultdict(lambda: {"requests": [], "statuses": set(), "attack_types": set(), "404_count": 0})

    for log_file_path in log_paths:
        try:
            with open(log_file_path, 'r') as file:
                for line in file:
                    parsed = parse_log_line(line)
                    if parsed and not is_search_engine_bot(parsed["user_agent"]) and not is_private_ip(parsed["ip"]) and not is_whitelisted_request(parsed["request"]):
                        ip = parsed["ip"]
                        if ip not in whitelist:
                            attack_type = identify_attack_type(parsed["request"], parsed["user_agent"])
                            if attack_type or parsed["status"] == 404:
                                attacks[ip]["requests"].append(parsed)
                                attacks[ip]["statuses"].add(parsed["status"])
                                if attack_type:
                                    attacks[ip]["attack_types"].add(attack_type)
                                if parsed["status"] == 404:
                                    attacks[ip]["404_count"] += 1
        except FileNotFoundError:
            print(f"警告: 日志文件 {log_file_path} 不存在。")

    filtered_attacks = {}
    for ip, data in attacks.items():
        if len(data["requests"]) > 3 and (len(data["statuses"]) > 1 or 200 not in data["statuses"]):
            data["requests"].sort(key=lambda x: x["timestamp"])
            start_time = data["requests"][0]["timestamp"]
            end_time = data["requests"][-1]["timestamp"]
            duration = end_time - start_time
            duration_seconds = duration.total_seconds()
            
            request_rate = len(data["requests"]) / max(duration_seconds, 1)
            
            is_attack = (
                (duration <= timedelta(minutes=10) and len(data["requests"]) > 50)  # 10分钟内50次以上请求
                or request_rate > 10  # 每秒超过10次请求
                or (len(data["attack_types"]) > 1 and any(status >= 400 for status in data["statuses"]))  # 多种攻击类型且有错误状态码
                or any(attack in ["SQL注入尝试", "XSS攻击尝试", "命令注入尝试"] for attack in data["attack_types"])  # 特定严重攻击类型
                or (data["404_count"] >= 20 and duration <= timedelta(minutes=10))  # 10分钟内20次以上404状态
            )
            
            if is_attack:
                severity = "严重"
            else:
                severity = "可疑"
            
            if data["attack_types"] or is_attack:
                filtered_attacks[ip] = {
                    "count": len(data["requests"]),
                    "statuses": data["statuses"],
                    "start_time": start_time,
                    "duration_seconds": duration_seconds,
                    "attack_types": data["attack_types"],
                    "request_rate": request_rate,
                    "404_count": data["404_count"],
                    "severity": severity
                }

    return filtered_attacks

def format_duration(seconds):
    if seconds < 60:
        return f"{seconds:.2f}秒"
    elif seconds < 3600:
        return f"{seconds / 60:.2f}分钟"
    else:
        return f"{seconds / 3600:.2f}小时"

def format_output(attacks):
    print("日志记录汇总:")
    
    severe_attacks = []
    minor_attacks = []
    
    # 添加生成严重风险IP日志的部分
    severe_risk_log = "/root/logcheck/severe_risk_ips.log"
    with open(severe_risk_log, 'w') as log_file:
        for ip, data in attacks.items():
            if data["attack_types"] and (len(data["statuses"]) > 1 or 200 not in data["statuses"]):
                attack_info = {
                    "ip": ip,
                    "statuses": ", ".join(map(str, data["statuses"])),
                    "start_time": data["start_time"].strftime("%Y-%m-%d %H:%M:%S"),
                    "duration": format_duration(data["duration_seconds"]),
                    "attack_types": ", ".join(data["attack_types"]),
                    "count": data["count"],
                    "request_rate": f"{data['request_rate']:.2f}",
                    "404_count": data["404_count"],
                    "severity": "轻微" if data["severity"] == "可疑" else data["severity"]
                }
                
                if data["severity"] == "严重":
                    severe_attacks.append(attack_info)
                    # 将严重风险IP写入日志
                    log_file.write(f"{ip}\n")
                else:
                    minor_attacks.append(attack_info)
    
    print(f"严重风险 (IP数量: {len(severe_attacks)}):")
    print_attack_table(severe_attacks)
    
    print(f"\n轻微风险 (IP数量: {len(minor_attacks)}):")
    print_attack_table(minor_attacks)

    print(f"\n严重风险IP已记录到 {severe_risk_log}")

    if severe_attacks:
        print("\n是否要将所有严重风险IP关进小黑屋？(需配合fail2ban脚本)")
        choice = input("输入 'y' 确认，回车键取消: ")
        if choice.lower() == 'y':
            for attack in severe_attacks:
                ip = attack['ip']
                #command = f"sudo fail2ban-client set fail2ban-nginx-cc banip {ip}"
                command = f"sudo ufw insert 1 deny from {ip} to any"
                print(f"执行命令: {command}")
                # 取消下面的注释以实际执行命令
                import os
                os.system(command)
            print("所有严重风险IP已被关进小黑屋。")
        else:
            print("操作已取消。")
            
def print_attack_table(attacks):
    print("| 恶意IP | 返回状态码 | 攻击开始时间 | 时间跨度 | 攻击方式 | 请求次数 | 请求频率(/秒) | 404状态次数 | 严重程度 |")
    print("|---------|------------|--------------|----------|----------|----------|----------------|-------------|----------|")
    for attack in attacks:
        print(f"| {attack['ip']} | {attack['statuses']} | {attack['start_time']} | {attack['duration']} | {attack['attack_types']} | {attack['count']} | {attack['request_rate']} | {attack['404_count']} | {attack['severity']} |")

def main():
    whitelist = load_whitelist()
    attacks = analyze_logs(LOG_PATHS, whitelist)
    format_output(attacks)

if __name__ == "__main__":
    main()