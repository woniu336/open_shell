import time
import hmac
import hashlib
import base64
import urllib.parse
import requests
from datetime import datetime
import sys

# 设置输出无缓冲
sys.stdout.reconfigure(line_buffering=True)  # Python 3.7+
# 如果上面的方法不支持，可以使用这个：
# sys.stdout = open(sys.stdout.fileno(), mode='w', buffering=1)

# 配置信息
URL = "https://my.frantech.ca/cart.php?a=add&pid=1423"
ACCESS_TOKEN = ""
SECRET = ""
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
        if "Out of Stock" in response.text:
            log_message("目前此商品已断货")
        else:
            log_message("商品有货啦")
            message = f"卢森堡vps有货啦!快去购买: {URL}"
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