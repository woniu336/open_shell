import re
import subprocess
import os
from collections import defaultdict, Counter
from datetime import datetime, timedelta, timezone
from ua_parser import user_agent_parser

class LogAnalyzer:
    def __init__(self):
        self.log_files = [
            '/www/wwwlogs/123.log',
            # 在这里添加更多日志文件路径
        ]
        self.pattern = re.compile(
            r'(?P<ip>\S+)\s+-\s+-\s+'
            r'\[(?P<time>[^\]]+)\]\s+'
            r'"(?P<method>\S+)\s+(?P<url>\S+)\s+(?P<protocol>[^"]+)"\s+'
            r'(?P<status>\d+)\s+'
            r'(?P<response_size>\d+)\s+'
            r'"(?P<referrer>[^"]*)"\s+'
            r'"(?P<user_agent>[^"]+)"'
        )
        self.records = []
        self.url_counter = Counter()
        self.ip_pattern = re.compile(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$')
        self.output_file = open('analyze_logs.txt', 'w', encoding='utf-8')
        self.whitelist = self.load_whitelist()
        self.severe_risk_log = 'severe_risk_ips.log'
        self.ensure_log_file_exists()

    def log(self, message: str):
        print(message)
        self.output_file.write(message + '\n')

    def load_whitelist(self):
        whitelist_file = '/root/logcheck/ip_whitelist.txt'
        if not os.path.exists(whitelist_file):
            with open(whitelist_file, 'w') as f:
                pass
            self.log(f"创建了空白的白名单文件：{whitelist_file}")
        else:
            self.log(f"白名单文件 {whitelist_file} 已存在，跳过创建。")

        whitelist = set()
        with open(whitelist_file, 'r') as f:
            for line in f:
                ip = line.strip()
                if self.ip_pattern.match(ip):
                    whitelist.add(ip)
        return whitelist

    def ensure_log_file_exists(self):
        if not os.path.exists(self.severe_risk_log):
            with open(self.severe_risk_log, 'w') as f:
                pass
            self.log(f"创建了新的高风险IP日志文件：{self.severe_risk_log}")
        else:
            self.log(f"高风险IP日志文件 {self.severe_risk_log} 已存在，跳过创建。")

    def simplify_user_agent(self, user_agent):
        parsed_ua = user_agent_parser.Parse(user_agent)
        ua_family = parsed_ua['user_agent']['family']
        os_family = parsed_ua['os']['family']
        device_family = parsed_ua['device']['family']

        if 'bot' in ua_family.lower() or 'crawler' in ua_family.lower() or 'spider' in ua_family.lower():
            return ua_family, True
        elif os_family:
            return os_family, False
        elif device_family:
            return device_family, False
        else:
            return 'Unknown', False

    def parse_logs(self):
        self.log("开始解析日志文件...")
        for log_file in self.log_files:
            self.log(f"正在处理日志文件: {log_file}")
            try:
                with open(log_file, 'r', encoding='utf-8', errors='ignore') as f:
                    for line in f:
                        match = self.pattern.match(line)
                        if match:
                            data = match.groupdict()
                            simplified_ua, is_crawler = self.simplify_user_agent(data['user_agent'])
                            self.records.append({
                                'IP地址': data['ip'],
                                '时间': data['time'],
                                '请求类型': data['method'],
                                '请求URL': data['url'],
                                '状态码': data['status'],
                                '用户代理': simplified_ua,
                                '响应大小': data['response_size'],
                                '是爬虫': is_crawler
                            })
                            self.url_counter[data['url']] += 1
                        else:
                            self.log(f"无法匹配的日志行: {line.strip()}")
            except Exception as e:
                self.log(f"无法读取日志文件 {log_file}: {e}")
        self.log(f"日志解析完成。共解析 {len(self.records)} 条记录。\n")

    def display_summary_table(self):
        if not self.records:
            self.log("没有找到匹配的记录。")
            return

        normal_ip_data = defaultdict(lambda: {
            'count': 0, 
            'user_agents': set(),
            'request_types': set(),
            'status_codes': set(),
            'response_sizes': []
        })
        crawler_ip_data = defaultdict(lambda: {
            'count': 0, 
            'user_agents': set(),
            'request_types': set(),
            'status_codes': set(),
            'response_sizes': []
        })

        for record in self.records:
            ip = record['IP地址']
            if ip in self.whitelist:
                continue  # 排除白名单中的IP
            data = crawler_ip_data[ip] if record['是爬虫'] else normal_ip_data[ip]
            data['count'] += 1
            data['user_agents'].add(record['用户代理'])
            data['request_types'].add(record['请求类型'])
            data['status_codes'].add(record['状态码'])
            data['response_sizes'].append(int(record['响应大小']))

        self.log("\n## 普通IP访问汇总（前20个IP）\n")
        self._display_ip_table(normal_ip_data)

        self.log("\n## 爬虫IP访问汇总（前20个IP）\n")
        self._display_ip_table(crawler_ip_data)

    def _display_ip_table(self, ip_data):
        self.log("| IP地址 | 访问次数 | 用户代理 | 请求类型 | 状态码 | 平均响应大小 |")
        self.log("|--------|----------|----------|----------|--------|--------------|")
        for ip, data in sorted(ip_data.items(), key=lambda x: x[1]['count'], reverse=True)[:20]:
            user_agents = ', '.join(data['user_agents'])
            request_types = ', '.join(data['request_types'])
            status_codes = ', '.join(data['status_codes'])
            avg_response_size = sum(data['response_sizes']) / len(data['response_sizes'])
            
            self.log(f"| {ip} | {data['count']} | {user_agents} | {request_types} | {status_codes} | {avg_response_size:.0f} |")

    def display_top_urls(self):
        self.log("\n## 访问次数最多的前20个URL\n")
        self.log("| URL | 访问次数 |")
        self.log("|-----|----------|")
        for url, count in self.url_counter.most_common(20):
            self.log(f"| {url} | {count} |")
        self.log("\n" + "="*50 + "\n")  # 添加分隔符

    def analyze_high_frequency_ips(self):
        ip_time_requests = defaultdict(lambda: defaultdict(int))
        ip_is_crawler = {}
        for record in self.records:
            ip = record['IP地址']
            ip_is_crawler[ip] = record['是爬虫']
            try:
                record_time = datetime.strptime(record['时间'], '%d/%b/%Y:%H:%M:%S %z')
            except ValueError:
                record_time = datetime.strptime(record['时间'], '%d/%b/%Y:%H:%M:%S')
                record_time = record_time.replace(tzinfo=timezone.utc)
            minute_key = record_time.strftime('%Y-%m-%d %H:%M')
            ip_time_requests[ip][minute_key] += 1

        high_frequency_ips = []
        banned_ips = []
        for ip, time_requests in ip_time_requests.items():
            max_requests = max(time_requests.values())
            if max_requests > 30 and ip not in self.whitelist and not ip_is_crawler[ip]:
                high_frequency_ips.append((ip, max_requests, ip_is_crawler[ip]))
                if max_requests > 70:
                    banned_ips.append(ip)
                    self.ban_ip(ip)
                    self.record_severe_risk_ip(ip)

        if banned_ips:
            self.log("\n## 自动封禁的高频率访问IP\n")
            self.log(f"共封禁 {len(banned_ips)} 个IP地址：")
            for ip in banned_ips:
                self.log(f"- {ip}")
            self.log("\n" + "="*50 + "\n")  # 添加分隔符

        if high_frequency_ips:
            self.log("\n## 高频率访问IP汇总（每分钟请求次数超过30次）\n")
            self.log("| IP地址 | 最高每分钟请求次数 |")
            self.log("|--------|---------------------|")
            for ip, max_requests, is_crawler in sorted(high_frequency_ips, key=lambda x: x[1], reverse=True):
                ip_display = f"{ip} (爬虫)" if is_crawler else ip
                self.log(f"| {ip_display} | {max_requests} |")
        else:
            self.log("\n暂时没有超过每分钟请求次数阈值的IP。")

    def ban_ip(self, ip):
        try:
            subprocess.run(
                ["sudo", "fail2ban-client", "set", "fail2ban-nginx-cc", "banip", ip],
                check=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True
            )
        except subprocess.CalledProcessError as e:
            self.log(f"封禁IP {ip} 时出错: {e}")
        except Exception as e:
            self.log(f"执行封禁IP {ip} 时出现未预料的错误: {e}")

    def record_severe_risk_ip(self, ip):
        existing_ips = set()
        try:
            with open(self.severe_risk_log, 'r') as f:
                existing_ips = set(line.strip() for line in f)
        except FileNotFoundError:
            pass

        if ip not in existing_ips:
            with open(self.severe_risk_log, 'a') as f:
                f.write(f"{ip}\n")
            self.log(f"已将IP {ip} 记录到高风险IP日志文件。")
        else:
            self.log(f"IP {ip} 已存在于高风险IP日志文件中，跳过记录。")

    def analyze_suspicious_ips(self):
        ip_time_requests = defaultdict(list)
        for record in self.records:
            ip = record['IP地址']
            if not self.ip_pattern.match(ip) or record['是爬虫'] or ip in self.whitelist:
                continue
            try:
                record_time = datetime.strptime(record['时间'], '%d/%b/%Y:%H:%M:%S %z')
            except ValueError:
                record_time = datetime.strptime(record['时间'], '%d/%b/%Y:%H:%M:%S')
                record_time = record_time.replace(tzinfo=timezone.utc)
            ip_time_requests[ip].append(record_time)

        suspicious_ips = []
        for ip, times in ip_time_requests.items():
            times.sort()
            for i in range(len(times) - 70):
                if times[i+69] - times[i] <= timedelta(minutes=5):
                    suspicious_ips.append(ip)
                    break

        if suspicious_ips:
            self.log("\n## 可疑IP列表（5分钟内访问次数超过70次，不包括爬虫和白名单IP）\n")
            self.log(f"共发现 {len(suspicious_ips)} 个可疑IP地址：")
            for ip in suspicious_ips:
                self.log(f"- {ip}")
            self.log("\n" + "="*50 + "\n")  # 添加分隔符
        else:
            self.log("\n暂时没有发现可疑IP。")

    def display_error_status_ips(self):
        error_ip_data = defaultdict(lambda: defaultdict(int))
        
        for record in self.records:
            status_code = int(record['状态码'])
            ip = record['IP地址']
            
            if 400 <= status_code < 600 and ip not in self.whitelist:
                error_ip_data[ip][status_code] += 1

        ip_total_errors = {
            ip: sum(status_counts.values()) 
            for ip, status_counts in error_ip_data.items()
        }
        
        top_15_ips = sorted(ip_total_errors.items(), key=lambda x: x[1], reverse=True)[:15]
        
        self.log("\n## 状态码为4xx或5xx的IP汇总（前15个）\n")
        self.log("| IP地址 | 状态码 | 次数 |")
        self.log("|--------|--------|------|")
        
        for ip, _ in top_15_ips:
            status_counts = error_ip_data[ip]
            for status, count in sorted(status_counts.items()):
                self.log(f"| {ip} | {status} | {count} |")

    def close(self):
        self.output_file.close()

def main():
    analyzer = LogAnalyzer()
    try:
        analyzer.parse_logs()
        analyzer.display_summary_table()
        analyzer.display_top_urls()
        analyzer.analyze_high_frequency_ips()
        analyzer.analyze_suspicious_ips()
        analyzer.display_error_status_ips()
    except Exception as e:
        analyzer.log(f"发生错误：{str(e)}")
    finally:
        analyzer.close()

if __name__ == "__main__":
    main()