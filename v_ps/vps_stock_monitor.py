import requests
import time
import hmac
import hashlib
import base64
import urllib.parse
from datetime import datetime
import fcntl
import sys
import os
import logging

# 钉钉配置
ACCESS_TOKEN = ""
SECRET = ""

# 设置日志输出
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    datefmt='%Y年%m月%d日 %H:%M:%S',
    handlers=[logging.StreamHandler()]
)

class ProcessLock:
    def __init__(self):
        self.lockfile = '/tmp/vps_monitor.lock'
        self.fp = open(self.lockfile, 'w')
    
    def acquire(self):
        try:
            fcntl.flock(self.fp.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            return True
        except IOError:
            return False
    
    def release(self):
        try:
            fcntl.flock(self.fp.fileno(), fcntl.LOCK_UN)
            self.fp.close()
            os.remove(self.lockfile)
        except:
            pass

def generate_sign():
    timestamp = str(round(time.time() * 1000))
    secret_enc = SECRET.encode('utf-8')
    string_to_sign = f'{timestamp}\n{SECRET}'
    string_to_sign_enc = string_to_sign.encode('utf-8')
    hmac_code = hmac.new(secret_enc, string_to_sign_enc, digestmod=hashlib.sha256).digest()
    sign = urllib.parse.quote_plus(base64.b64encode(hmac_code))
    return timestamp, sign

def send_dingtalk_notification():
    timestamp, sign = generate_sign()
    webhook_url = f"https://oapi.dingtalk.com/robot/send?access_token={ACCESS_TOKEN}&timestamp={timestamp}&sign={sign}"
    
    message = f"""
V.PS 圣何塞 8.95EUR 已经有货!

配置信息:
- CPU: 2 Cores
- Memory: 1 GB
- NVMe Storage: 20 GB
- Data Transfer: 1 TB

购买链接: https://vps.hosting/cart/san-jose-cloud-kvm-vps/

通知时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
    """
    
    try:
        headers = {'Content-Type': 'application/json'}
        data = {
            "msgtype": "text",
            "text": {
                "content": message
            },
            "at": {
                "isAtAll": False
            }
        }
        
        response = requests.post(webhook_url, headers=headers, json=data)
        logging.info(f"钉钉通知发送状态: {response.status_code}")
        logging.info(f"钉钉通知响应: {response.text}")
        return True
    except Exception as e:
        logging.error(f"发送钉钉通知失败: {str(e)}")
        return False

def check_stock():
    url = "https://vps.hosting/cart/san-jose-cloud-kvm-vps/"
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"
    }
    
    try:
        response = requests.get(url, headers=headers)
        
        # 查找Starter套餐区块
        if "Starter" in response.text:
            # 检查是否存在缺货标记
            is_out_of_stock = 'class="card cart-product   outofstock "' in response.text or 'cart-product-outofstock-badge' in response.text
            
            # 检查价格
            has_price = "8.95 EUR" in response.text
            
            logging.info(f"价格检查: {'通过' if has_price else '未通过'}")
            logging.info(f"库存状态: {'缺货' if is_out_of_stock else '有货'}")
            
            if has_price and not is_out_of_stock:
                logging.info("Starter方案有货!")
                return True
            
            if is_out_of_stock:
                logging.info("Starter方案缺货")
            return False
            
        else:
            logging.info("未找到Starter方案")
            return False
            
    except Exception as e:
        logging.error(f"检查失败: {str(e)}")
        return False

def run_task():
    """执行监控任务"""
    if check_stock():
        logging.info("发现库存!")
        if send_dingtalk_notification():
            logging.info("通知发送成功，退出程序")
            sys.exit(0)
    else:
        logging.info("暂无库存,等待下次检查...")

def main():
    # 创建进程锁
    lock = ProcessLock()
    
    # 尝试获取锁
    if not lock.acquire():
        logging.warning("另一个监控进程正在运行")
        sys.exit(1)
    
    try:
        logging.info("开始监控VPS库存...")
        while True:
            run_task()  # 执行任务
            time.sleep(5)  # 每5秒执行一次任务
            
    except KeyboardInterrupt:
        logging.info("\n监控已停止")
    except Exception as e:
        logging.error(f"发生错误: {str(e)}")
    finally:
        # 释放进程锁
        lock.release()

if __name__ == "__main__":
    main()