#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import subprocess
import sys
import os
import platform
import re
from datetime import datetime
import locale
import warnings
import time

# 禁用 SSL 警告
warnings.filterwarnings('ignore', message='Unverified HTTPS request')

# 重定向标准错误输出到 null
class DevNull:
    def write(self, msg): pass
    def flush(self): pass

stderr_backup = sys.stderr
sys.stderr = DevNull()

def restore_stderr():
    """恢复标准错误输出"""
    sys.stderr = stderr_backup

# 设置默认编码为UTF-8
if sys.stdout.encoding != 'UTF-8':
    try:
        sys.stdout.reconfigure(encoding='utf-8')
    except AttributeError:
        # Python 3.6 及以下版本
        import codecs
        sys.stdout = codecs.getwriter('utf-8')(sys.stdout.buffer)

# 设置区域
try:
    locale.setlocale(locale.LC_ALL, '')
except:
    pass

def check_root():
    """检查是否有root权限"""
    return os.geteuid() == 0

def show_progress(message):
    """显示进度动画"""
    chars = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    sys.stdout.write('\r')
    for char in chars:
        sys.stdout.write(f'\r{char} {message}')
        sys.stdout.flush()
        time.sleep(0.1)

def install_package(package_name, pip=False):
    """安装包的通用函数"""
    try:
        if pip:
            show_progress(f"Installing {package_name}...")
            # 重定向所有输出到 /dev/null
            with open(os.devnull, 'w') as devnull:
                subprocess.check_call(
                    [sys.executable, "-m", "pip", "install", "--quiet", package_name],
                    stdout=devnull,
                    stderr=devnull
                )
            sys.stdout.write('\r' + ' ' * 70 + '\r')  # 清除进度显示
            print(f"✓ Installed {package_name}")
        else:
            # 检测系统类型
            if platform.system() == "Linux":
                # 检测Linux发行版
                if os.path.exists("/etc/debian_version"):  # Debian/Ubuntu
                    show_progress("Updating package list...")
                    # 重定向所有输出到 /dev/null
                    with open(os.devnull, 'w') as devnull:
                        subprocess.check_call(
                            ["apt-get", "update", "-qq"],
                            stdout=devnull,
                            stderr=devnull
                        )
                    sys.stdout.write('\r' + ' ' * 70 + '\r')  # 清除进度显示
                    
                    show_progress(f"Installing {package_name}...")
                    with open(os.devnull, 'w') as devnull:
                        subprocess.check_call(
                            ["DEBIAN_FRONTEND=noninteractive", "apt-get", "install", "-y", "-qq", package_name],
                            stdout=devnull,
                            stderr=devnull,
                            env=dict(os.environ, DEBIAN_FRONTEND="noninteractive")
                        )
                    sys.stdout.write('\r' + ' ' * 70 + '\r')  # 清除进度显示
                    print(f"✓ Installed {package_name}")
                    
                elif os.path.exists("/etc/redhat-release"):  # CentOS/RHEL
                    show_progress(f"Installing {package_name}...")
                    with open(os.devnull, 'w') as devnull:
                        subprocess.check_call(
                            ["yum", "install", "-y", "-q", package_name],
                            stdout=devnull,
                            stderr=devnull
                        )
                    sys.stdout.write('\r' + ' ' * 70 + '\r')  # 清除进度显示
                    print(f"✓ Installed {package_name}")
                else:
                    print(f"不支持的Linux发行版，请手动安装 {package_name}")
                    sys.exit(1)
            else:
                print(f"不支持的操作系统，请手动安装 {package_name}")
                sys.exit(1)
        return True
    except subprocess.CalledProcessError as e:
        sys.stdout.write('\r' + ' ' * 70 + '\r')  # 清除进度显示
        print(f"✗ Failed to install {package_name}: {str(e)}")
        return False

def check_and_install_requirements():
    """检查并安装所需的包"""
    try:
        if not check_root():
            print("请使用root权限运行此脚本")
            sys.exit(1)

        # 静默检查和安装
        try:
            import pip
        except ImportError:
            if not install_package("python3-pip"):
                sys.exit(1)

        try:
            subprocess.check_call(["mtr", "--version"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except (subprocess.CalledProcessError, FileNotFoundError):
            if not install_package("mtr"):
                sys.exit(1)

        required_packages = {
            "requests": "requests",
            "pandas": "pandas",
            "tabulate": "tabulate",
            "colorama": "colorama"
        }

        for module, package in required_packages.items():
            try:
                __import__(module)
            except ImportError:
                if not install_package(package, pip=True):
                    sys.exit(1)
    finally:
        # 恢复标准错误输出
        restore_stderr()

# 先执行依赖检查
if __name__ == "__main__":
    check_and_install_requirements()

# 在依赖安装完成后再导入这些模块
import requests
import pandas as pd
from tabulate import tabulate
from colorama import init, Fore, Back, Style

class NetworkTester:
    def __init__(self):
        # 初始化colorama，设置转换所有输出
        init(strip=False)
        self.ip = None
        self.mtr_data = []
        self.summary = {}
        self.raw_output = None
    
    def clear_screen(self):
        """清屏函数"""
        os.system('cls' if os.name == 'nt' else 'clear')
    
    def print_header(self):
        """打印标题"""
        try:
            print(f"\n{Style.BRIGHT}{Fore.CYAN}{'='*60}")
            print(f"{Fore.WHITE}Network Testing Tool - MTR Report")  # 使用英文替代
            print(f"{Fore.CYAN}{'='*60}{Style.RESET_ALL}\n")
        except UnicodeEncodeError:
            # 如果仍然出现编码错误，使用ASCII字符
            print("="*60)
            print("Network Testing Tool - MTR Report")
            print("="*60)
    
    def get_location(self, ip):
        try:
            response = requests.get(f"http://ip-api.com/json/{ip}", timeout=5)
            data = response.json()
            if data["status"] == "success":
                return f"{data.get('city', 'Unknown')}, {data.get('regionName', 'Unknown')}, {data.get('country', 'Unknown')}"
            return "Unknown"
        except:
            return "Unknown"
    
    def run_mtr(self, ip):
        self.ip = ip
        cmd = f"mtr -n -r -c 10 {ip}"
        
        try:
            print("执行 MTR 命令...")
            result = subprocess.run(cmd.split(), capture_output=True, text=True)
            if result.stderr:
                print(f"MTR 错误输出: {result.stderr}")
            if not result.stdout:
                print("MTR 没有输出")
                return None
            self.raw_output = result.stdout
            print("MTR 命令执行完成")
            return result.stdout
        except Exception as e:
            print(f"执行 MTR 时出错: {str(e)}")
            return None

    def parse_mtr_output(self, output):
        if not output:
            print("没有 MTR 输出可供解析")
            return
        
        lines = output.strip().split('\n')
        data_lines = [line for line in lines[2:] if line.strip()]
        
        for line in data_lines:
            try:
                parts = re.split(r'\s+', line.strip())
                hop_num = parts[0].replace('.', '')
                host = parts[1].replace('|--', '').strip()
                
                # 跳过 "waiting for reply" 的行
                if "(waiting for reply)" in line:
                    continue
                    
                loss = parts[2].replace('%', '')
                sent = parts[3]
                last = parts[4]
                avg = parts[5]
                best = parts[6]
                worst = parts[7]
                stdev = parts[8]

                hop = {
                    'hop': hop_num,
                    'host': host,
                    'loss%': float(loss),
                    'sent': int(sent),
                    'last': float(last),
                    'avg': float(avg),
                    'best': float(best),
                    'worst': float(worst),
                    'stdev': float(stdev)
                }
                self.mtr_data.append(hop)
                
            except (ValueError, IndexError) as e:
                continue

    def analyze_results(self):
        if not self.mtr_data:
            return "No data to analyze"
        
        last_hop = self.mtr_data[-1]
        hops_with_loss = [hop for hop in self.mtr_data if hop['loss%'] > 0]
        
        # 计算平均延迟和最大延迟跳变
        delays = [hop['avg'] for hop in self.mtr_data]
        delay_changes = [delays[i] - delays[i-1] for i in range(1, len(delays))]
        max_delay_change = max(delay_changes) if delay_changes else 0
        
        # 计算路径质量指标
        path_quality = self.calculate_path_quality()
        
        self.summary = {
            "目标 IP": self.ip,
            "地理位置": self.get_location(self.ip),
            "总跳数": len(self.mtr_data),
            "最终延迟": f"{last_hop['avg']:.1f}ms",
            "最佳延迟": f"{last_hop['best']:.1f}ms",
            "最差延迟": f"{last_hop['worst']:.1f}ms",
            "延迟波动": f"{last_hop['stdev']:.1f}ms",
            "最大延迟跳变": f"{max_delay_change:.1f}ms",
            "路径质量": path_quality,
            "连接质量": self.get_connection_quality(last_hop['avg'], last_hop['stdev']),
            "丢包情况": self.get_packet_loss_summary(hops_with_loss),
            "测试时间": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        }

    def calculate_path_quality(self):
        """计算路径质量"""
        if not self.mtr_data:
            return "未知"
            
        # 计算加权平均延迟（越后面的节点权重越大）
        total_weight = 0
        weighted_delay = 0
        for i, hop in enumerate(self.mtr_data):
            weight = i + 1
            total_weight += weight
            weighted_delay += hop['avg'] * weight
            
        avg_weighted_delay = weighted_delay / total_weight
        
        # 根据加权延迟评估路径质量
        if avg_weighted_delay < 50:
            return "优秀"
        elif avg_weighted_delay < 100:
            return "良好"
        elif avg_weighted_delay < 200:
            return ""
        else:
            return "较差"
        
    def get_connection_quality(self, avg_latency, stdev):
        if avg_latency < 10 and stdev < 1:
            return "极佳"
        elif avg_latency < 50 and stdev < 5:
            return "良好"
        elif avg_latency < 100 and stdev < 10:
            return "一般"
        else:
            return "较差"
            
    def get_packet_loss_summary(self, hops_with_loss):
        if not hops_with_loss:
            return "无丢包"
        
        # 计算有效节点总数（排除waiting for reply的节点）
        total_valid_hops = len(self.mtr_data)  # self.mtr_data已经在parse时排除了waiting for reply
        
        # 过滤掉丢包率为100%的节点
        valid_loss_hops = [hop for hop in hops_with_loss if hop['loss%'] < 100.0]
        
        if not valid_loss_hops:
            return "无丢包"
        
        # 计算丢包率
        # 使用有丢包节点数除以总有效节点数
        loss_rate = (len(valid_loss_hops) / total_valid_hops) * 100
        
        # 生成详细的丢包报告
        summary = (
            f"存在丢包 ({len(valid_loss_hops)} 个节点，总体丢包率 {loss_rate:.1f}%)"
        )
        
        return summary
    
    def generate_markdown_report(self):
        if not self.summary:
            return "无数据可供显示"
        
        self.clear_screen()
        self.print_header()
        
        report = ""
        
        # 基本信息
        report += f"{Fore.YELLOW}▶ 基本信息{Style.RESET_ALL}\n"
        report += f"┌{'─'*58}┐\n"
        basic_info = {
            "目标 IP": (self.summary["目标 IP"], False),
            "地理位置": (self.summary["地理位置"], False),
            "测试时间": (self.summary["测试时间"], False)
        }
        
        for key, (value, highlight) in basic_info.items():
            value_str = str(value)
            if highlight:
                value_str = f"{Fore.RED}{value_str}{Style.RESET_ALL}"
            report += f"│ {key:<15} {value_str:<41} │\n"
        
        # 网络状态
        report += f"└{'─'*58}┘\n\n"
        report += f"{Fore.YELLOW}▶ 网络状态{Style.RESET_ALL}\n"
        report += f"┌{'─'*58}┐\n"
        
        network_info = {
            "最终延迟": (self.summary["最终延迟"], self.is_high_latency(self.summary["最终延迟"])),
            "最佳延迟": (self.summary["最佳延迟"], False),
            "最差延迟": (self.summary["最差延迟"], self.is_high_latency(self.summary["最差延迟"])),
            "延迟波动": (self.summary["延迟波动"], self.is_high_jitter(self.summary["延迟波动"])),
            "路径质量": (self.summary["路径质量"], self.summary["路径质量"] in ["较差", "一般"]),
            "总跳数": (self.summary["总跳数"], False),
            "丢包情况": (self.summary["丢包情况"], "存在丢包" in self.summary["丢包情况"])
        }
        
        for key, (value, highlight) in network_info.items():
            value_str = str(value)
            if highlight:
                value_str = f"{Fore.RED}{value_str}{Style.RESET_ALL}"
            report += f"│ {key:<15} {value_str:<41} │\n"
        
        report += f"└{'─'*58}┘\n"
        return report

    def is_high_latency(self, latency_str):
        """判断延迟是否过高"""
        try:
            value = float(latency_str.replace('ms', ''))
            return value > 100
        except:
            return False

    def is_high_jitter(self, jitter_str):
        """判断抖��是否过高"""
        try:
            value = float(jitter_str.replace('ms', ''))
            return value > 10
        except:
            return False

def validate_ip(ip):
    """验证IP地址格式"""
    pattern = r'^(\d{1,3}\.){3}\d{1,3}$'
    if not re.match(pattern, ip):
        return False
    
    # 验证每个数字是否在0-255之间
    return all(0 <= int(num) <= 255 for num in ip.split('.'))

def main():
    try:
        while True:
            tester = NetworkTester()
            tester.clear_screen()
            tester.print_header()
            
            ip = input("Please enter IP address to test (q to quit): ").strip()  # 使用英文提示
            
            if ip.lower() == 'q':
                print("\nExiting program...")
                break
                
            if not validate_ip(ip):
                print("\nInvalid IP address format, please try again")
                input("Press Enter to continue...")
                continue
            
            print("\nRunning network test, please wait...")
            mtr_output = tester.run_mtr(ip)
            
            if mtr_output:
                tester.parse_mtr_output(mtr_output)
                if tester.mtr_data:
                    tester.analyze_results()
                    print(tester.generate_markdown_report())
                else:
                    print("\nNo valid test data received")
            else:
                print("\nMTR test failed")
            
            input("\nPress Enter to continue...")
    except Exception as e:
        print(f"\nError: {str(e)}")
        return 1
    return 0

if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\nProgram interrupted by user")
        sys.exit(1)
    except Exception as e:
        print(f"\nProgram error: {str(e)}")
        print("Error details:")
        import traceback
        traceback.print_exc()
        sys.exit(1)