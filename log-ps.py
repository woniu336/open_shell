import re
import sys
import requests
from collections import defaultdict, Counter
from datetime import datetime, timedelta
from ua_parser import user_agent_parser

class LogAnalyzer:
    def __init__(self, log_file):
        self.log_file = log_file
        self.pattern = re.compile(
            r'(?P<ip>\d+\.\d+\.\d+\.\d+)\s+'
            r'(?P<request_url>\S+)\s+'
            r'\[(?P<time>[^\]]+)\]\s+'
            r'(?P<domain>\S+)\s+'
            r'"(?P<method>\S+)\s+(?P<url>\S+)\s+(?P<protocol>[^"]+)"\s+'
            r'(?P<status>\d+)\s+'
            r'"(?P<referrer>[^"]*)"\s+'
            r'(?P<user_agent>[^"]+)\s+-\s+\[(?P<response_size>\d+),(?P<response_time>\d+\.\d+)\]'
        )
        self.records = []
        self.whitelist = set([
            '1.1.1.1',
            '192.168.1.1',
            '10.0.0.1',
            '172.16.0.1'
        ])   # 添加多个IP到白名单
        self.suspicious_patterns = ['/xxxx.com/', '/axxx/']  # 可疑URL模式列表

    def simplify_user_agent(self, user_agent):
        """
        使用 ua-parser 解析用户代理，提取主要关键词。
        """
        parsed_ua = user_agent_parser.Parse(user_agent)
        ua_family = parsed_ua['user_agent']['family']
        os_family = parsed_ua['os']['family']
        device_family = parsed_ua['device']['family']

        # 优先返回 UA family，如果是爬虫则返回对应名称
        if 'bot' in ua_family.lower() or 'crawler' in ua_family.lower() or 'spider' in ua_family.lower():
            return ua_family
        elif os_family:
            return os_family
        elif device_family:
            return device_family
        else:
            return 'Unknown'

    def get_ip_country(self, ip):
        """
        使用 ip-api.com 获取IP的国家信息。
        """
        try:
            response = requests.get(f'http://ip-api.com/json/{ip}', timeout=5)
            data = response.json()
            if data['status'] == 'success':
                return data.get('country', '未知')
            else:
                return '未知'
        except requests.RequestException:
            return '未知'

    def parse_logs(self, target_ip):
        with open(self.log_file, 'r', encoding='utf-8', errors='ignore') as f:
            for line_number, line in enumerate(f, 1):
                match = self.pattern.match(line)
                if match:
                    data = match.groupdict()
                    if data['ip'] == target_ip:
                        simplified_ua = self.simplify_user_agent(data['user_agent'])
                        country = self.get_ip_country(data['ip'])
                        self.records.append({
                            'IP地址': data['ip'],
                            '国家': country,
                            '时间': data['time'],
                            '请求类型': data['method'],
                            '请求URL': data['url'],
                            '状态码': data['status'],
                            '来源URL': data['referrer'],
                            '用户代理': simplified_ua,
                            '响应时间（秒）': data['response_time']
                        })
                else:
                    # 检查是否包含目标IP但未匹配
                    if target_ip in line:
                        print(f"调试信息: 第 {line_number} 行未匹配正则表达式: {line.strip()}")

    def display_summary_table(self):
        if not self.records:
            print("没有找到匹配的记录。")
            return

        total_requests = len(self.records)
        
        # 统计用户代理和状态码
        user_agents = [record['用户代理'] for record in self.records]
        status_codes = [record['状态码'] for record in self.records]
        most_common_ua = Counter(user_agents).most_common(1)[0][0]
        unique_status_codes = ', '.join(sorted(set(status_codes)))

        print("\n## IP访问汇总\n")
        print(f"| IP地址           | 国家 | 访问次数 | 用户代理 | 状态码 |\n|---|---|---|---|---|\n| {self.records[0]['IP地址']} | {self.records[0]['国家']} | {total_requests} | {most_common_ua} | {unique_status_codes} |")

    def display_url_pattern_table(self):
        if not self.records:
            return

        url_counts = defaultdict(int)
        for record in self.records:
            url_counts[record['请求URL']] += 1

        print("\n## 访问URL行为模式\n")
        print("| 请求URL                                         | 访问次数 |\n|---|---|\n")
        for url, count in sorted(url_counts.items(), key=lambda item: item[1], reverse=True):
            print(f"| {url} | {count} |")

    def check_url_pattern(self, url):
        return any(pattern in url for pattern in self.suspicious_patterns)

    def analyze_behavior(self):
        if not self.records:
            print("没有记录可供分析。")
            return

        if self.records[0]['IP地址'] in self.whitelist:
            print("\n该IP在白名单中，行为正常。")
            return

        request_count = len(self.records)
        suspicious_urls = any(self.check_url_pattern(record['请求URL']) for record in self.records)

        # 时间窗口分析
        try:
            times = sorted([datetime.strptime(record['时间'], '%d/%b/%Y:%H:%M:%S %z') for record in self.records])
        except ValueError:
            print("\n时间格式解析错误，无法进行时间窗口分析。")
            times = []

        window_start = times[0] if times else None
        window_end = window_start + timedelta(minutes=1) if window_start else None
        requests_in_window = 0
        max_requests_in_window = 0

        for time in times:
            if window_end and time > window_end:
                window_start = time
                window_end = window_start + timedelta(minutes=1)
                requests_in_window = 1
            else:
                requests_in_window += 1
                if requests_in_window > max_requests_in_window:
                    max_requests_in_window = requests_in_window

        high_freq = request_count > 50  # 调整后的总请求次数阈值
        high_freq_window = max_requests_in_window > 20 if max_requests_in_window else False  # 每分钟请求次数阈值

        if high_freq or suspicious_urls or high_freq_window:
            print("\n该IP的行为可能具有恶意性。")
        else:
            print("\n该IP的行为看起来正常。")

def main():
    if len(sys.argv) != 3:
        print("用法: python analyze_logs_ua_parser.py <日志文件路径> <目标IP地址>")
        sys.exit(1)
    log_file = sys.argv[1]
    target_ip = sys.argv[2]
    analyzer = LogAnalyzer(log_file)
    analyzer.parse_logs(target_ip)
    analyzer.display_summary_table()
    analyzer.display_url_pattern_table()
    analyzer.analyze_behavior()

if __name__ == "__main__":
    main()