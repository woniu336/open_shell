import re
import geoip2.database
from collections import Counter
import ipaddress
from datetime import datetime
import os

# 定义日志文件路径列表
LOG_PATHS = [
    "/www/wwwlogs/123.log",
    # 在这里添加更多日志文件路径
]

# 定义GeoIP数据库路径
GEOIP_DB_PATH = "/root/data/GeoLite2-City.mmdb"

# 定义输出文件夹路径
OUTPUT_FOLDER = "/root/logcheck"

# 确保输出文件夹存在
os.makedirs(OUTPUT_FOLDER, exist_ok=True)

# 定义输出文件路径
OUTPUT_PATH = os.path.join(OUTPUT_FOLDER, "log_analysis.txt")

# 定义白名单文件路径
WHITELIST_PATH = "/root/logcheck/ip_whitelist.txt"

# 扩展常见爬虫IP列表
CRAWLER_IPS = [
    ipaddress.ip_network("66.249.64.0/19"),  # Googlebot
    ipaddress.ip_network("66.249.79.0/24"),  # 新添加的Googlebot IP范围
    ipaddress.ip_network("40.77.167.0/24"),  # bingbot
    ipaddress.ip_network("157.55.39.0/24"),  # bingbot
    ipaddress.ip_network("52.167.144.0/24"),  # bingbot
    ipaddress.ip_network("207.46.13.0/24"),  # bingbot
    ipaddress.ip_network("20.15.133.0/24"),  # Bingbot
    ipaddress.ip_network("40.77.189.0/24"),  # Bingbot
    ipaddress.ip_network("40.77.202.0/24"),  # Bingbot
    ipaddress.ip_network("40.77.190.0/24"),  # Bingbot
    ipaddress.ip_network("40.77.188.0/24"),  # Bingbot 
    ipaddress.ip_network("72.30.198.0/24"),  # Yahoo! Slurp
    ipaddress.ip_network("209.191.64.0/18"),  # Yahoo!
    ipaddress.ip_network("199.16.156.0/22"),  # Twitter
    ipaddress.ip_network("199.59.148.0/22"),  # Twitter
    ipaddress.ip_network("65.52.0.0/14"),    # Microsoft
    ipaddress.ip_network("131.253.21.0/24"), # Microsoft
    ipaddress.ip_network("131.253.24.0/22"), # Microsoft
    ipaddress.ip_network("131.253.46.0/23"), # Microsoft
    ipaddress.ip_network("57.141.3.0/24"),   # FacebookBot IP范围
]

def load_whitelist():
    whitelist = set()
    if os.path.exists(WHITELIST_PATH):
        with open(WHITELIST_PATH, 'r') as f:
            for line in f:
                ip = line.strip()
                if re.match(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$', ip):
                    whitelist.add(ip)
    return whitelist

def is_crawler_ip(ip):
    try:
        ip_obj = ipaddress.ip_address(ip)
        return any(ip_obj in network for network in CRAWLER_IPS)
    except ValueError:
        return False

def parse_log_file(log_path):
    ip_pattern = r'\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}'
    timestamp_pattern = r'\[(\d{2}/\w{3}/\d{4}:\d{2}:\d{2}:\d{2})'
    ip_time_pairs = []
    
    with open(log_path, 'r') as f:
        for line in f:
            ip_match = re.search(ip_pattern, line)
            timestamp_match = re.search(timestamp_pattern, line)
            if ip_match and timestamp_match:
                ip = ip_match.group()
                timestamp = datetime.strptime(timestamp_match.group(1), '%d/%b/%Y:%H:%M:%S')
                if not is_crawler_ip(ip):
                    ip_time_pairs.append((ip, timestamp))
    
    return ip_time_pairs

def get_ip_location(ip, reader):
    try:
        response = reader.city(ip)
        continent = response.continent.name
        country = response.country.name
        city = response.city.name
        return continent, country, city
    except:
        return "Unknown", "Unknown", "Unknown"

def analyze_ips(ip_time_pairs, reader, whitelist):
    asia_ips = []
    north_america_ips = []
    for ip, timestamp in ip_time_pairs:
        if ip in whitelist:
            continue  # 排除白名单中的IP
        continent, country, city = get_ip_location(ip, reader)
        if continent == "Asia":
            asia_ips.append((ip, city))
        elif continent == "North America":
            north_america_ips.append((ip, city))
    return asia_ips, north_america_ips

def get_top_ips(ips, n=15):
    return Counter(ips).most_common(n)

def get_suspicious_ips(ip_time_pairs, reader, whitelist):
    ip_minute_counts = {}
    for ip, timestamp in ip_time_pairs:
        if ip in whitelist:
            continue  # 排除白名单中的IP
        minute_key = timestamp.strftime('%Y-%m-%d %H:%M')
        if ip not in ip_minute_counts:
            ip_minute_counts[ip] = Counter()
        ip_minute_counts[ip][minute_key] += 1
    
    suspicious_ips = []
    for ip, minute_counts in ip_minute_counts.items():
        if any(count >= 30 for count in minute_counts.values()):
            max_count = max(minute_counts.values())
            continent, _, _ = get_ip_location(ip, reader)
            region = "亚洲" if continent == "Asia" else "北美洲" if continent == "North America" else "未知"
            suspicious_ips.append((ip, max_count, region))
    
    return sorted(suspicious_ips, key=lambda x: x[1], reverse=True)

def write_results_to_file(output_path, asia_ips, north_america_ips, suspicious_ips):
    with open(output_path, 'w', encoding='utf-8') as f:
        f.write(f"# 日志分析结果 - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n")
        
        f.write(f"## 亚洲地区IP统计\n\n")
        f.write(f"总IP数量: {len(set(ip for ip, _ in asia_ips))}\n\n")
        f.write("前15个高频IP:\n\n")
        f.write("| IP | 访问次数 | 城市 |\n")
        f.write("|-----|----------|------|\n")
        for (ip, city), count in get_top_ips(asia_ips):
            f.write(f"| {ip} | {count} | {city or 'None'} |\n")
        
        f.write(f"\n## 北美洲地区IP统计\n\n")
        f.write(f"总IP数量: {len(set(ip for ip, _ in north_america_ips))}\n\n")
        f.write("前15个高频IP:\n\n")
        f.write("| IP | 访问次数 | 城市 |\n")
        f.write("|-----|----------|------|\n")
        for (ip, city), count in get_top_ips(north_america_ips):
            f.write(f"| {ip} | {count} | {city or 'None'} |\n")
        
        f.write(f"\n## 可疑IP（每分钟访问30次以上）\n\n")
        f.write("| IP | 最大每分钟访问次数 | 地区 |\n")
        f.write("|-----|--------------------|---------|\n")
        for ip, max_count, region in suspicious_ips:
            f.write(f"| {ip} | {max_count} | {region} |\n")

def main():
    reader = geoip2.database.Reader(GEOIP_DB_PATH)
    
    all_ip_time_pairs = []
    whitelist = load_whitelist()  # 加载白名单
    for log_path in LOG_PATHS:
        if log_path:  # 只处理非空路径
            ip_time_pairs = parse_log_file(log_path)
            all_ip_time_pairs.extend(ip_time_pairs)
    
    asia_ips, north_america_ips = analyze_ips(all_ip_time_pairs, reader, whitelist)
    suspicious_ips = get_suspicious_ips(all_ip_time_pairs, reader, whitelist)
    
    write_results_to_file(OUTPUT_PATH, asia_ips, north_america_ips, suspicious_ips)
    
    print(f"分析结果已保存到文件: {OUTPUT_PATH}")
    
    reader.close()

if __name__ == "__main__":
    main()