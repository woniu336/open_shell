import re
from collections import defaultdict, Counter
import os

# 定义日志文件路径和报告输出路径
LOG_FILE_PATH = ''
REPORT_FILE_PATH = ''

# 定义正则表达式用于解析日志
LOG_PATTERN = re.compile(
    r'(?P<ip>\S+) \S+ \S+ \[(?P<time>.*?)\] "(?P<method>\S+) (?P<url>\S+) \S+" (?P<status>\d{3}) (?P<size>\d+|-) "(?P<referer>.*?)" "(?P<user_agent>.*?)"'
)

# 初始化统计数据结构
ip_counter = Counter()
visitor_type_counter = Counter()
method_counter = Counter()
resource_type_counter = Counter()
status_code_counter = Counter()
user_agent_counter = Counter()
response_size = []
url_counter = Counter()
error_urls = []
crawler_ips = set()

# 定义搜索引擎爬虫的User-Agent关键字
SEARCH_BOTS = {
    'Googlebot': 'Googlebot',
    'Facebook': 'facebookexternalhit',
    'Bingbot': 'bingbot'
}

# 定义请求资源类型分类规则
RESOURCE_TYPES = {
    '/play/': '播放页',
    '/show/': '分类页',
    '/video/': '详情页',
    '/index.php/ajax/': 'AJAX接口请求',
    '/index.php/user/ajax_ulog/': '用户操作记录接口',
    '/statics/img/': '静态资源'
}

def classify_visitor(user_agent):
    for bot, identifier in SEARCH_BOTS.items():
        if identifier.lower() in user_agent.lower():
            return bot
    return '普通用户'

def classify_resource(url):
    for prefix, resource_type in RESOURCE_TYPES.items():
        if url.startswith(prefix):
            return resource_type
    return '其他资源'

def parse_log_line(line):
    match = LOG_PATTERN.match(line)
    if match:
        return match.groupdict()
    return None

def analyze_log():
    with open(LOG_FILE_PATH, 'r', encoding='utf-8') as f:
        for line in f:
            parsed = parse_log_line(line)
            if parsed:
                ip = parsed['ip']
                method = parsed['method']
                url = parsed['url']
                status = parsed['status']
                size = parsed['size']
                user_agent = parsed['user_agent']
                
                # 更新IP计数
                ip_counter[ip] += 1
                
                # 分类访问者类型
                visitor_type = classify_visitor(user_agent)
                visitor_type_counter[visitor_type] += 1
                
                # 如果是爬虫，添加到爬虫IP集合
                if visitor_type in SEARCH_BOTS:
                    crawler_ips.add(ip)
                
                # 更新请求方法计数
                method_counter[method] += 1
                
                # 分类请求资源类型
                resource_type = classify_resource(url)
                resource_type_counter[resource_type] += 1
                
                # 更新状态码计数
                status_code_counter[status] += 1
                
                # 更新User-Agent计数
                user_agent_counter[user_agent] += 1
                
                # 更新URL计数
                url_counter[url] += 1
                
                # 检查错误状态码
                if status.startswith('5'):
                    error_urls.append(url)
                
                # 处理响应大小
                if size != '-':
                    response_size.append(int(size))

def generate_report():
    with open(REPORT_FILE_PATH, 'w', encoding='utf-8') as report:
        report.write("# 服务器日志分析报告\n\n")
        
        # 访问来源分析
        report.write("## 一、访问来源分析\n\n")
        report.write("### 1. IP地址分布\n\n")
        for ip, count in ip_counter.most_common(10):
            crawler_flag = "（爬虫IP）" if ip in crawler_ips else ""
            report.write(f"- {ip}: {count} 次访问 {crawler_flag}\n")
        report.write("\n")
        
        report.write("### 2. 访问者类型\n\n")
        for visitor, count in visitor_type_counter.most_common():
            report.write(f"- {visitor}: {count} 次访问\n")
        report.write("\n")
        
        # 请求分析
        report.write("## 二、请求分析\n\n")
        report.write("### 1. 请求方法\n\n")
        for method, count in method_counter.most_common():
            report.write(f"- {method}: {count} 次\n")
        report.write("\n")
        
        report.write("### 2. 请求资源类型\n\n")
        for resource, count in resource_type_counter.most_common():
            report.write(f"- {resource}: {count} 次\n")
        report.write("\n")
        
        # HTTP状态码分析
        report.write("## 三、HTTP状态码分析\n\n")
        for status, count in status_code_counter.most_common():
            report.write(f"- {status}: {count} 次\n")
        report.write("\n")
        
        # User-Agent分析
        report.write("## 四、User-Agent分析\n\n")
        for agent, count in user_agent_counter.most_common(10):
            report.write(f"- {agent}: {count} 次\n")
        report.write("\n")
        
        # 响应大小分布
        report.write("## 五、响应大小分布\n\n")
        if response_size:
            avg_size = sum(response_size) / len(response_size)
            max_size = max(response_size)
            min_size = min(response_size)
            report.write(f"- 平均响应大小: {avg_size:.2f} 字节\n")
            report.write(f"- 最大响应大小: {max_size} 字节\n")
            report.write(f"- 最小响应大小: {min_size} 字节\n")
        else:
            report.write("- 无有效的响应大小数据。\n")
        report.write("\n")
        
        # URL分析
        report.write("## 六、URL分析\n\n")
        report.write("### 1. 高频访问URL\n\n")
        for url, count in url_counter.most_common(10):
            report.write(f"- {url}: {count} 次访问\n")
        report.write("\n")
        
        report.write("### 2. 错误状态码的URL\n\n")
        for url in set(error_urls):
            report.write(f"- {url}\n")
        report.write("\n")
        
def main():
    print("开始分析日志...")
    analyze_log()
    print("日志分析完成，正在生成报告...")
    generate_report()
    print(f"报告已生成：{REPORT_FILE_PATH}")

if __name__ == "__main__":
    main()