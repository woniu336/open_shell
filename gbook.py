import requests
from bs4 import BeautifulSoup
import time
import hmac
import hashlib
import base64
import urllib.parse
import json

# 配置信息
URL = "https://catpdf.org/gbook-1.html"  # 留言页面URL
ACCESS_TOKEN = ""  # 替换为您的钉钉机器人 access token
SECRET = ""  # 替换为您的钉钉机器人 secret

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

def get_latest_comment():
    response = requests.get(URL)
    soup = BeautifulSoup(response.text, 'html.parser')
    
    latest_comment = soup.find('div', class_='gbook-item')
    if latest_comment:
        content = latest_comment.find('div', class_='gbook-content').text.strip()
        meta = latest_comment.find('div', class_='gbook-meta').text.strip()
        return f"{content}\n{meta}"
    return None

def check_new_comments():
    latest_comment = get_latest_comment()
    if latest_comment:
        try:
            with open('last_comment.txt', 'r+') as f:
                last_saved_comment = f.read().strip()
                if latest_comment != last_saved_comment:
                    message = f"新留言:\n{latest_comment}"
                    send_dingtalk_notification(message)
                    f.seek(0)
                    f.write(latest_comment)
                    f.truncate()
                    print("发现新留言并发送通知")
                else:
                    print("没有新留言")
        except FileNotFoundError:
            # 如果文件不存在，创建文件并写入最新留言
            with open('last_comment.txt', 'w') as f:
                f.write(latest_comment)
            message = f"首次运行，记录最新留言:\n{latest_comment}"
            send_dingtalk_notification(message)
            print("首次运行，记录最新留言并发送通知")
    else:
        print("无法获取最新留言")

if __name__ == "__main__":
    check_new_comments()