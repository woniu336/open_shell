import os
import re
import subprocess
import sys

def check_and_install_dependencies():
    print("正在检查并安装依赖...")
    try:
        import crontab
    except ImportError:
        print("正在安装 python-crontab...")
        subprocess.run([sys.executable, "-m", "pip", "install", "python-crontab"], check=True)
        print("python-crontab 已成功安装")

# 在脚本开头调用此函数
check_and_install_dependencies()

# 现在导入 crontab，因为我们确保它已经安装
from crontab import CronTab

import tempfile

BASH_SCRIPT_PATH = "/root/php-malware-scanner.sh"
PHP_FILES_LIST = "/tmp/php_files_list.txt"
WEBSITE_LIST_PATH = "/tmp/website_list.txt"

def read_bash_script():
    with open(BASH_SCRIPT_PATH, 'r') as file:
        return file.read()

def write_bash_script(content):
    with open(BASH_SCRIPT_PATH, 'w') as file:
        file.write(content)

def update_bash_variable(variable_name, new_value):
    content = read_bash_script()
    pattern = rf'{variable_name}=\(([^)]*)\)'
    if isinstance(new_value, list):
        new_value_str = '\n    "' + '"\n    "'.join(new_value) + '"\n'
        replacement = f'{variable_name}=(\n{new_value_str})'
    else:
        replacement = f'{variable_name}="{new_value}"'
    updated_content = re.sub(pattern, replacement, content, flags=re.DOTALL)
    write_bash_script(updated_content)

def add_website_dir():
    new_dir = input("请输入新的网站目录路径: ")
    content = read_bash_script()
    pattern = r'WEBSITE_DIRS=\((.*?)\)'
    match = re.search(pattern, content, re.DOTALL)
    if match:
        current_dirs = match.group(1).strip().split('\n')
        current_dirs = [dir.strip(' "') for dir in current_dirs if dir.strip()]
        if new_dir not in current_dirs:
            print("正在停止定时任务...")
            stop_cron_job()
            
            current_dirs.append(new_dir)
            update_bash_variable('WEBSITE_DIRS', current_dirs)
            print(f"已添加网站目录: {new_dir}")
            
            print("正在更新PHP文件列表...")
            run_bash_script()
            
            print("正在恢复定时任务...")
            start_cron_job()
            
            print("\n新目录已添加并更新了PHP文件列表。")
            check_cron_job()
        else:
            print("该目录已存在。")
    else:
        print("无法在脚本中找到 WEBSITE_DIRS 变量。")

def remove_website_dir():
    content = read_bash_script()
    pattern = r'WEBSITE_DIRS=\((.*?)\)'
    match = re.search(pattern, content, re.DOTALL)
    if match:
        current_dirs = match.group(1).strip().split('\n')
        current_dirs = [dir.strip(' "') for dir in current_dirs if dir.strip()]
        
        print("当前监控的网站目录:")
        for i, dir in enumerate(current_dirs, 1):
            print(f"{i}. {dir}")
        
        choice = input("请输入要删除的目录编号 (或按回车取消): ")
        if choice.isdigit() and 1 <= int(choice) <= len(current_dirs):
            removed_dir = current_dirs.pop(int(choice) - 1)
            update_bash_variable('WEBSITE_DIRS', current_dirs)
            print(f"已删除网站目录: {removed_dir}")
            
            print("正在清理被删除站点的PHP文件记录...")
            clean_php_files_list(removed_dir)
            
            print("正在清理被删除站点的网站列表记录...")
            clean_website_list(removed_dir)
            
            print("正在停止定时任务...")
            stop_cron_job()
            
            print("正在更新PHP文件列表...")
            run_bash_script()
            
            print("正在恢复定时任务...")
            start_cron_job()
            
            check_cron_job()
        else:
            print("取消删除操作。")
    else:
        print("无法在脚本中找到 WEBSITE_DIRS 变量。")

def clean_php_files_list(removed_dir):
    with open(PHP_FILES_LIST, 'r') as file:
        lines = file.readlines()
    
    new_lines = [line for line in lines if not line.startswith(removed_dir)]
    
    with open(PHP_FILES_LIST, 'w') as file:
        file.writelines(new_lines)

def clean_website_list(removed_dir):
    try:
        with open(WEBSITE_LIST_PATH, 'r') as file:
            lines = file.readlines()
        
        new_lines = [line for line in lines if not line.startswith(removed_dir)]
        
        with open(WEBSITE_LIST_PATH, 'w') as file:
            file.writelines(new_lines)
        
        print(f"已从 {WEBSITE_LIST_PATH} 中清理被删除站点的记录。")
    except FileNotFoundError:
        print(f"警告: {WEBSITE_LIST_PATH} 文件不存在。")
    except Exception as e:
        print(f"清理 {WEBSITE_LIST_PATH} 时出错: {e}")

def run_bash_script():
    try:
        result = subprocess.run(["/bin/bash", BASH_SCRIPT_PATH, "update"], capture_output=True, text=True, check=True)
        print("已成功运行 Bash 脚本更新 PHP 文件列表。")
        if "发现新增的PHP文件：" in result.stdout:
            print("\n警告: 发现新增的PHP文件:")
            new_files = result.stdout.split("发现新增的PHP文件：")[1].split("开始扫描")[0].strip().split("\n")
            for file in new_files:
                print(f"  - {file}")
            print("\n这些新文件已被添加到监控列表中。请在下次扫描时检查它们。")
    except subprocess.CalledProcessError as e:
        print(f"运行 Bash 脚本时出错: {e}")
        print(f"错误输出: {e.stderr}")

def add_malicious_domain():
    new_domain = input("请输入新的恶意域名: ")
    content = read_bash_script()
    pattern = r'HIGH_RISK_DOMAINS=\((.*?)\)'
    match = re.search(pattern, content, re.DOTALL)
    if match:
        current_domains = match.group(1).strip().split()
        current_domains = [domain.strip('"') for domain in current_domains]
        if new_domain not in current_domains:
            current_domains.append(new_domain)
            update_bash_variable('HIGH_RISK_DOMAINS', current_domains)
            print(f"已添加恶意域名: {new_domain}")
        else:
            print("该域名已存在。")
    else:
        print("无法在脚本中找到 HIGH_RISK_DOMAINS 变量。")

def update_dingtalk_webhook():
    new_webhook = input("请输入新的钉钉 Webhook URL: ")
    content = read_bash_script()
    pattern = r'(DINGTALK_WEBHOOK=").*?(")'
    updated_content = re.sub(pattern, f'\\1{new_webhook}\\2', content)
    if content != updated_content:
        write_bash_script(updated_content)
        print("已成功更新钉钉 Webhook URL。")
    else:
        print("未找到 DINGTALK_WEBHOOK 变量或无需更新。")

def check_cron_job():
    try:
        current_crontab = subprocess.check_output("crontab -l", shell=True, universal_newlines=True)
        existing_task = None
        for line in current_crontab.splitlines():
            if BASH_SCRIPT_PATH in line:
                existing_task = line
                break
        
        if existing_task:
            print(f"已存在扫描器定时任务：\n  {existing_task}")
            choice = input("是否要修改现有任务? (y/n): ").lower()
            if choice == 'y':
                setup_cron_job()
            else:
                print("保留现有任务。")
        else:
            print("当前不存在扫描器定时任务。")
            setup_cron_job_prompt()
    except subprocess.CalledProcessError:
        print("当前不存在任何 cron 任务。")
        setup_cron_job_prompt()

def setup_cron_job_prompt():
    setup = input("\n是否要设置新的定时任务? (y/n): ").lower()
    if setup == 'y':
        setup_cron_job()
    else:
        print("未设置定时任务。您可以稍后在主菜单中设置。")

def setup_cron_job():
    schedule = input("请输入 cron 表达式 (例如: * * * * * 表示每分钟): ")
    cron_command = f'{schedule} /bin/bash {BASH_SCRIPT_PATH} >/dev/null 2>&1'
    
    confirm = input(f"将添加以下 cron 任务:\n{cron_command}\n此操作将覆盖现有的扫描器任务。确认添加吗? (y/n): ").lower()
    if confirm == 'y':
        try:
            # 创建临时文件
            with tempfile.NamedTemporaryFile(mode='w+', delete=False) as temp_file:
                # 读取现有的 crontab，但排除旧的扫描器任务
                try:
                    current_crontab = subprocess.check_output("crontab -l", shell=True, universal_newlines=True)
                    for line in current_crontab.splitlines():
                        if BASH_SCRIPT_PATH not in line:
                            temp_file.write(line + '\n')
                except subprocess.CalledProcessError:
                    # 如果没有现有的 crontab，就创建一个空的
                    pass
                
                # 添加新的任务
                temp_file.write(f"{cron_command}\n")
                temp_file.flush()
            
            # 使用临时文件更新 crontab
            result = subprocess.run(f"crontab {temp_file.name}", shell=True, capture_output=True, text=True)
            
            if result.returncode != 0:
                print(f"添加 cron 任务时出错: {result.stderr}")
            else:
                print("cron 任务已成功添加，并覆盖了之前的扫描器任务。")
            
            # 删除临时文件
            os.unlink(temp_file.name)
        except Exception as e:
            print(f"添加 cron 任务时出错: {e}")
    else:
        print("取消添加 cron 任务。")

def stop_cron_job():
    try:
        cron = CronTab(user=True)
        cron.remove_all(comment='php-malware-scanner')
        cron.write()
        print("已停止定时任务。")
    except Exception as e:
        print(f"停止定时任务时出错: {e}")

def start_cron_job():
    try:
        cron = CronTab(user=True)
        job = cron.new(command=f'/bin/bash {BASH_SCRIPT_PATH} >/dev/null 2>&1', comment='php-malware-scanner')
        job.setall('*/30 * * * *')
        cron.write()
        print("已恢复定时任务。")
    except Exception as e:
        print(f"恢复定时任务时出错: {e}")

def execute_scan():
    try:
        print("正在执行扫描...")
        result = subprocess.run(["/bin/bash", BASH_SCRIPT_PATH, "scan"], capture_output=True, text=True, check=True)
        print("扫描完成。")
        print("扫描输出:")
        print(result.stdout)
        
        if "发现可疑文件：" in result.stdout:
            print("\n警告: 发现可疑文件:")
            suspicious_files = result.stdout.split("发现可疑文件：")[1].split("扫描完成")[0].strip().split("\n")
            for file in suspicious_files:
                print(f"  - {file}")
            print("这些可疑文件已被自动处理。")
        else:
            print("")
        
        if "已发送钉钉通知" in result.stdout:
            print("\n已发送钉钉通知。")
    except subprocess.CalledProcessError as e:
        print(f"执行操作时出错: {e}")
        print(f"错误输出: {e.stderr}")

def manage_exclude_dirs():
    content = read_bash_script()
    pattern = r'EXCLUDE_DIRS=\((.*?)\)'
    match = re.search(pattern, content, re.DOTALL)
    if match:
        current_dirs = match.group(1).strip().split('\n')
        current_dirs = [dir.strip(' "') for dir in current_dirs if dir.strip()]
        
        while True:
            print("\n当前排除的目录:")
            for i, dir in enumerate(current_dirs, 1):
                print(f"{i}. {dir}")
            
            print("\n选项:")
            print("1. 添加排除目录")
            print("2. 删除排除目录")
            print("3. 返回主菜单")
            
            choice = input("请选择操作 (1-3): ")
            
            if choice == '1':
                new_dir = input("请输入要排除的目录路径: ")
                if new_dir not in current_dirs:
                    current_dirs.append(new_dir)
                    update_bash_variable('EXCLUDE_DIRS', current_dirs)
                    print(f"已添加排除目录: {new_dir}")
                else:
                    print("该目录已在排除列表中。")
            elif choice == '2':
                index = int(input("请输入要删除的目录编号: ")) - 1
                if 0 <= index < len(current_dirs):
                    removed_dir = current_dirs.pop(index)
                    update_bash_variable('EXCLUDE_DIRS', current_dirs)
                    print(f"已删除排除目录: {removed_dir}")
                else:
                    print("无效的编号。")
            elif choice == '3':
                break
            else:
                print("无效的选择，请重新输入。")
    else:
        print("无法在脚本中找到 EXCLUDE_DIRS 变量。")

def download_script():
    if os.path.exists(BASH_SCRIPT_PATH):
        print("脚本文件已存在,跳过下载。")
        return
    
    try:
        # 下载脚本
        print("正在下载脚本...")
        subprocess.run(["curl", "-sS", "-O", "https://raw.githubusercontent.com/woniu336/open_shell/main/php-malware-scanner.sh"], check=True)
        subprocess.run(["chmod", "+x", "php-malware-scanner.sh"], check=True)
        print("脚本已成功下载并设置执行权限。")
    except subprocess.CalledProcessError as e:
        print(f"下载脚本时出错: {e}")

def set_shortcut():
    while True:
        os.system('clear')
        shortcut = input("请输入你想要的快捷按键（输入0退出）: ")
        if shortcut == "0":
            break

        home = os.path.expanduser("~")
        bashrc_path = os.path.join(home, ".bashrc")
        current_script_path = os.path.abspath(__file__)

        # 删除旧的别名设置
        with open(bashrc_path, 'r') as f:
            lines = f.readlines()
        lines = [line for line in lines if 'alias' not in line or current_script_path not in line]
        
        # 添加新的别名设置
        lines.append(f"alias {shortcut}='python3 {current_script_path}'\n")

        with open(bashrc_path, 'w') as f:
            f.writelines(lines)

        # 重新加载 .bashrc
        subprocess.run(["source", bashrc_path], shell=True)

        print("快捷键已设置")
        # 如果您有发送统计信息的函数,可以在这里调用
        # send_stats("PHP恶意代码扫描器脚本快捷键已设置")
        
        input("\n按回车键继续...")
        break

def print_menu():
    # 定义颜色
    CYAN = '\033[0;36m'
    GREEN = '\033[0;32m'
    BLUE = '\033[0;34m'
    NC = '\033[0m'  # No Color

    print(f"\n{CYAN}{'=' * 40}{NC}")
    print(f"{GREEN}     PHP 恶意代码扫描器管理系统{NC}")
    print(f"教程：https://woniu336.github.io/p/328/")
    print(f"{CYAN}{'=' * 40}{NC}")
    print(f"{BLUE}1.{NC} 下载脚本")
    print(f"{BLUE}2.{NC} 添加网站目录监控")
    print(f"{BLUE}3.{NC} 删除网站目录监控")
    print(f"{BLUE}4.{NC} 添加恶意域名")
    print(f"{BLUE}5.{NC} 更新钉钉通知 Webhook")
    print(f"{BLUE}6.{NC} 设置定时任务")
    print(f"{BLUE}7.{NC} 执行扫描")
    print(f"{BLUE}8.{NC} 管理排除目录")
    print(f"{BLUE}9.{NC} 设置脚本启动快捷键")
    print(f"{BLUE}0.{NC} 退出")
    print(f"{CYAN}{'=' * 40}{NC}")

def main_menu():
    while True:
        os.system('clear')
        print_menu()
        choice = input("请选择操作 (0-9): ")
        
        if choice == '1':
            download_script()
        elif choice == '2':
            add_website_dir()
        elif choice == '3':
            remove_website_dir()
        elif choice == '4':
            add_malicious_domain()
        elif choice == '5':
            update_dingtalk_webhook()
        elif choice == '6':
            check_cron_job()
        elif choice == '7':
            execute_scan()
        elif choice == '8':
            manage_exclude_dirs()
        elif choice == '9':
            set_shortcut()
        elif choice == '0':
            print("谢谢使用,再见!")
            break
        else:
            print("无效的选择,请重新输入。")
        
        if choice != '9':  # 如果不是设置快捷键,才显示"按回车键继续"
            input("\n按回车键继续...")

if __name__ == "__main__":
    main_menu()