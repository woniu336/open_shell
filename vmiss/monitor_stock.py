import time
import hmac
import hashlib
import base64
import urllib.parse
import requests
import cloudscraper
import sys
from datetime import datetime
from bs4 import BeautifulSoup

# 设置输出无缓冲，确保日志能实时写入文件或显示
sys.stdout.reconfigure(line_buffering=True)

# ================= 配置信息 =================
URL = "https://app.vmiss.com/store/us-los-angeles-tri"
ACCESS_TOKEN = "1111"  # 替换为你的钉钉机器人access_token
SECRET = "22222"        # 替换为你的钉钉机器人secret
CHECK_INTERVAL = 60     # 建议增加到60秒，减少被封风险
# ===========================================

def generate_sign():
    """钉钉签名算法"""
    timestamp = str(round(time.time() * 1000))
    secret_enc = SECRET.encode('utf-8')
    string_to_sign = f'{timestamp}\n{SECRET}'
    string_to_sign_enc = string_to_sign.encode('utf-8')
    hmac_code = hmac.new(secret_enc, string_to_sign_enc, digestmod=hashlib.sha256).digest()
    sign = urllib.parse.quote_plus(base64.b64encode(hmac_code))
    return timestamp, sign

def send_dingtalk_notification(message):
    """发送钉钉通知"""
    try:
        timestamp, sign = generate_sign()
        webhook_url = f"https://oapi.dingtalk.com/robot/send?access_token={ACCESS_TOKEN}&timestamp={timestamp}&sign={sign}"
        
        headers = {'Content-Type': 'application/json'}
        data = {
            "msgtype": "text",
            "text": {"content": message},
            "at": {"isAtAll": False}
        }
        
        response = requests.post(webhook_url, headers=headers, json=data, timeout=10)
        print(f"钉钉通知状态: {response.status_code}")
    except Exception as e:
        log_message(f"钉钉发送失败: {e}")

def log_message(message):
    """带时间戳的日志输出"""
    current_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{current_time}] {message}", flush=True)

def check_stock():
    try:
        scraper = cloudscraper.create_scraper(
            browser={'browser': 'chrome', 'platform': 'windows', 'desktop': True}
        )
        response = scraper.get(URL, timeout=20)
        
        if response.status_code == 200:
            soup = BeautifulSoup(response.text, 'html.parser')
            # 定位商品容器
            product_box = soup.find('div', {'id': 'product32'})
            
            if not product_box:
                # 这通常意味着页面改版或 ID 变了
                log_message("错误: 找不到商品 ID 'product32'，请检查页面结构。")
                return

            # 提取商品块内的全部文字
            content = product_box.get_text(strip=True)
            
            # 精准判断
            if "0 Available" in content:
                log_message("状态：US.LA.TRI.Basic 无货")
            else:
                # 只要不是 0，就触发有货通知
                log_message("状态：有货啦！")
                msg = f"【库存通知】US.LA.TRI.Basic 有货啦！\n立即抢购: {URL}"
                send_dingtalk_notification(msg)
                
        else:
            log_message(f"请求失败，状态码: {response.status_code}")

    except Exception as e:
        log_message(f"运行异常: {str(e)}")

if __name__ == "__main__":
    log_message("--- 脚本启动：VMiss 库存监控模块 ---")
    log_message(f"目标地址: {URL}")
    log_message(f"检测频率: 每 {CHECK_INTERVAL} 秒一次")
    
    try:
        while True:
            check_stock()
            time.sleep(CHECK_INTERVAL)
    except KeyboardInterrupt:
        log_message("监控已手动停止")