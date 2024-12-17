import time
import hmac
import hashlib
import base64
import urllib.parse
import requests
from datetime import datetime
import sys
from bs4 import BeautifulSoup

# 设置输出无缓冲
sys.stdout.reconfigure(line_buffering=True)

# 配置信息
URL = "https://app.vmiss.com/store/gb-london-9929"
ACCESS_TOKEN = "111"  # 替换为你的钉钉机器人access_token
SECRET = "222"  # 替换为你的钉钉机器人secret
CHECK_INTERVAL = 5  # 检查间隔（秒）

def generate_sign():
    timestamp = str(round(time.time() * 1000))
    secret_enc = SECRET.encode('utf-8')
    string_to_sign = f'{timestamp}\n{SECRET}'
    string_to_sign_enc = string_to_sign.encode('utf-8')
    hmac_code = hmac.new(secret_enc, string_to_sign_enc, digestmod=hashlib.sha256).digest()
    sign = urllib.parse.quote_plus(base64.b64encode(hmac_code))
    return timestamp, sign

def send_dingtalk_notification(message):
    timestamp, sign = generate_sign()
    webhook_url = f"https://oapi.dingtalk.com/robot/send?access_token={ACCESS_TOKEN}&timestamp={timestamp}&sign={sign}"
    
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
    print(f"钉钉通知发送状态: {response.status_code}")
    print(f"钉钉通知响应: {response.text}")

def log_message(message):
    """添加日志记录函数"""
    current_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{current_time}] {message}", flush=True)

def check_stock():
    try:
        response = requests.get(URL, timeout=10)
        response.raise_for_status()
        soup = BeautifulSoup(response.text, 'html.parser')
        
        # 查找库存信息
        stock_info = soup.find('div', {'id': 'product78'}).find('div', {'class': 'package-qty'})
        if stock_info and stock_info.text.strip() == "0 Available":
            log_message("GB.LON.9929.Basic 目前无货")
        else:
            log_message("GB.LON.9929.Basic 有货啦")
            message = f"GB.LON.9929.Basic 有货啦!快去购买: {URL}"
            send_dingtalk_notification(message)
    except requests.exceptions.RequestException as e:
        log_message(f"检查库存时发生错误: {str(e)}")

if __name__ == "__main__":
    log_message("开始监控库存状态...")
    log_message(f"监控间隔: {CHECK_INTERVAL}秒")
    try:
        while True:
            check_stock()
            time.sleep(CHECK_INTERVAL)
    except KeyboardInterrupt:
        log_message("监控已停止")