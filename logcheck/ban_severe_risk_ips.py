import subprocess
import sys
import logging

# 定义日志文件路径
SEVERE_RISK_LOG = "severe_risk_ips.log"

# 设置日志记录
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

def read_severe_risk_ips(log_file):
    try:
        with open(log_file, 'r') as f:
            return set(line.strip() for line in f if line.strip())
    except FileNotFoundError:
        logging.error(f"错误：找不到日志文件 {log_file}")
        sys.exit(1)
    except PermissionError:
        logging.error(f"错误：没有权限读取日志文件 {log_file}")
        sys.exit(1)

def ban_ip(ip):
    command = f"sudo fail2ban-client set fail2ban-nginx-cc banip {ip}"
    try:
        result = subprocess.run(command, shell=True, check=True, capture_output=True, text=True)
        logging.info(f"成功将IP {ip} 加入黑名单")
        logging.debug(f"命令输出：{result.stdout.strip()}")
    except subprocess.CalledProcessError as e:
        logging.error(f"将IP {ip} 加入黑名单时出错")
        logging.error(f"错误信息：{e.stderr.strip()}")
    except PermissionError:
        logging.error(f"错误：没有足够的权限执行命令。请确保脚本以适当的权限运行。")

def main():
    severe_risk_ips = read_severe_risk_ips(SEVERE_RISK_LOG)
    
    if not severe_risk_ips:
        logging.info("未发现严重风险IP")
        return
    
    logging.info(f"发现 {len(severe_risk_ips)} 个严重风险IP")
    
    for ip in severe_risk_ips:
        ban_ip(ip)
    
    logging.info("所有严重风险IP已被加入黑名单")

if __name__ == "__main__":
    main()