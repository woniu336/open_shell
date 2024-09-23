import time
import hmac
import hashlib
import base64
import urllib.parse
import requests

# 配置信息
URL = "https://my.frantech.ca/cart.php?a=add&pid=1424"
ACCESS_TOKEN = "YOUR_ACCESS_TOKEN"
SECRET = "YOUR_SECRET"

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

def check_stock():
    response = requests.get(URL)
    if "Out of Stock" in response.text:
        print("目前此商品已断货")
    else:
        print("商品有货啦")
        message = f"卢森堡vps有货啦!快去购买: {URL}"
        send_dingtalk_notification(message)

if __name__ == "__main__":
    check_stock()