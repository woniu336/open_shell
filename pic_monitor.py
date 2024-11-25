import requests
import re
import time
from datetime import datetime

class NodeMonitor:
    def __init__(self, url, dingding_webhook):
        self.url = url
        self.dingding_webhook = dingding_webhook

    def get_current_time(self):
        """获取当前时间的字符串格式"""
        return datetime.now().strftime('%Y-%m-%d %H:%M:%S')

    def get_page_content(self):
        """获取监控页面的内容"""
        try:
            headers = {
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) ' +
                              'AppleWebKit/537.36 (KHTML, like Gecko) ' +
                              'Chrome/91.0.4472.124 Safari/537.36'
            }
            print(f"[{self.get_current_time()}] 正在检查节点状态...")
            response = requests.get(self.url, headers=headers, timeout=10)
            response.raise_for_status()  # 如果响应状态码不是200，将引发异常
            print(f"[{self.get_current_time()}] 成功获取页面内容")
            return response.text
        except Exception as e:
            error_msg = f"无法访问监控页面: {str(e)}"
            print(f"[{self.get_current_time()}] ❌ {error_msg}")
            self.send_alert(error_msg)
            return None

    def parse_status(self, content):
        """解析页面内容，提取所有节点的类型、标识和状态"""
        if not content:
            return []

        # 修改正则表达式，匹配任意状态
        pattern = r"(GitHub: node-\d+|GitLab: Project ID \d+(-\d+)?|R2 Storage: [^\s]+)\s*-\s*([^\(]+)"
        matches = re.findall(pattern, content, re.IGNORECASE)

        # 调试输出
        print(f"\n[{self.get_current_time()}] 调试信息:")
        print("找到的匹配:")
        for match in matches:
            node_identifier = match[0] + (f"-{match[1]}" if match[1] else "")
            status = match[2].strip().lower()
            print(f"节点: {node_identifier}, 状态: {status}")

        # 构建简化的匹配结果列表
        simplified_matches = []
        for match in matches:
            node_identifier = match[0] + (f"-{match[1]}" if match[1] else "")
            status = match[2].strip().lower()
            simplified_matches.append((node_identifier, status))

        return simplified_matches

    def send_alert(self, message):
        """通过钉钉机器人发送告警消息（Markdown 格式的表格）"""
        if not self.dingding_webhook:
            print(f"[{self.get_current_time()}] ⚠️ 未配置钉钉webhook，跳过告警发送")
            return

        headers = {'Content-Type': 'application/json'}
        
        # 如果传入的是错误信息字符串，则发送简单文本
        if isinstance(message, str) and not isinstance(message, list):
            data = {
                "msgtype": "text",
                "text": {
                    "content": f"节点监控警告 - {self.get_current_time()}\n{message}"
                }
            }
        else:
            # 构建 Markdown 表格
            markdown_table = "### 节点监控警告\n\n| 节点类型 | 节点标识 | 状态 |\n| --- | --- | --- |\n"
            for node in message:
                node_type, node_id, status = node
                markdown_table += f"| {node_type} | {node_id} | {status} |\n"
            
            data = {
                "msgtype": "markdown",
                "markdown": {
                    "title": "节点监控警告",
                    "text": markdown_table
                }
            }
        
        try:
            response = requests.post(self.dingding_webhook, headers=headers, json=data, timeout=10)
            response.raise_for_status()
            print(f"[{self.get_current_time()}] ✅ 已发送钉钉告警")
        except Exception as e:
            print(f"[{self.get_current_time()}] ❌ 发送钉钉消息失败: {str(e)}")

    def check_nodes(self):
        """检查所有节点的状态，并根据结果发送告警"""
        content = self.get_page_content()
        if not content:
            return

        nodes = self.parse_status(content)
        working_nodes = []
        not_working_nodes = []

        for node in nodes:
            node_type_identifier, status = node
            if status == "working":
                working_nodes.append(node_type_identifier)
            else:
                # 分解节点类型和标识
                if ":" in node_type_identifier:
                    node_type, node_id = node_type_identifier.split(":", 1)
                    node_type = node_type.strip()
                    node_id = node_id.strip()
                else:
                    node_type = "未知"
                    node_id = node_type_identifier.strip()
                not_working_nodes.append((node_type, node_id, status))

        # 打印状态正常的节点
        if working_nodes:
            print(f"\n[{self.get_current_time()}] 状态正常的节点 ✅:")
            for node in working_nodes:
                print(f"  - {node}")

        # 打印异常节点并发送告警
        if not_working_nodes:
            print(f"\n[{self.get_current_time()}] 异常节点 ❌:")
            for node in not_working_nodes:
                print(f"  - {node[0]}: {node[1]} - {node[2]}")
            # 构建警报信息的元组列表
            alert_message = not_working_nodes
            self.send_alert(alert_message)

        print(f"\n[{self.get_current_time()}] 本次检查完成 {'✅ 所有节点正常' if not not_working_nodes else '❌ 存在异常节点'}")
        print("-" * 50)

def main():
    # 配置监控参数
    URL = ""
    DINGDING_WEBHOOK = "https://oapi.dingtalk.com/robot/send?access_token="  # 如果要测试，可以先置空
    CHECK_INTERVAL = 3600  # 1小时检查一次（单位：秒）

    print(f"开始监控节点状态")
    print(f"监控地址: {URL}")
    print(f"检查间隔: {CHECK_INTERVAL}秒")
    print("-" * 50)

    monitor = NodeMonitor(URL, DINGDING_WEBHOOK)

    while True:
        try:
            monitor.check_nodes()
            print(f"[{monitor.get_current_time()}] 等待{CHECK_INTERVAL}秒后进行下一次检查...\n")
            time.sleep(CHECK_INTERVAL)
        except Exception as e:
            print(f"[{monitor.get_current_time()}] ❌ 监控异常: {str(e)}")
            print(f"[{monitor.get_current_time()}] 等待60秒后重试...\n")
            time.sleep(60)

if __name__ == "__main__":
    main()