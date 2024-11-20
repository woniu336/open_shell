import requests
import time
import hmac
import hashlib
import base64
import urllib.parse

# 配置
CHECK_INTERVAL = 5  # 每次检查的间隔时间（秒）
RETRY_INTERVAL = 5   # 请求失败后的重试间隔时间（秒）
OVH_API_URL = "https://www.ovh.com/engine/apiv6/dedicated/server/datacenter/availabilities/?excludeDatacenters=true&planCode=25skleb01&server=25skleb01"

# 钉钉机器人配置
DINGTALK_ACCESS_TOKEN = ""
DINGTALK_SECRET = ""

# 要监控的配置和数据中心
CONFIGS = ["softraid-2x2000sa", "softraid-2x450nvme"]
DATACENTERS = ["fra", "gra"]

# 上一次库存记录（避免重复通知）
last_availability = {}

def generate_sign():
    """生成钉钉机器人签名"""
    timestamp = str(round(time.time() * 1000))
    secret_enc = DINGTALK_SECRET.encode('utf-8')
    string_to_sign = f'{timestamp}\n{DINGTALK_SECRET}'
    string_to_sign_enc = string_to_sign.encode('utf-8')
    hmac_code = hmac.new(secret_enc, string_to_sign_enc, digestmod=hashlib.sha256).digest()
    sign = urllib.parse.quote_plus(base64.b64encode(hmac_code))
    return timestamp, sign

def send_dingtalk_notification(content):
    """发送钉钉通知"""
    try:
        timestamp, sign = generate_sign()
        webhook_url = f"https://oapi.dingtalk.com/robot/send?access_token={DINGTALK_ACCESS_TOKEN}&timestamp={timestamp}&sign={sign}"
        
        headers = {'Content-Type': 'application/json'}
        data = {
            "msgtype": "text",
            "text": {
                "content": f"OVH库存提醒\n\n{content}"
            },
            "at": {
                "isAtAll": True
            }
        }
        
        response = requests.post(webhook_url, headers=headers, json=data)
        response.raise_for_status()
        print("钉钉通知发送成功！")
        print(f"响应状态: {response.status_code}")
        print(f"响应内容: {response.text}")
    except Exception as e:
        print(f"钉钉通知发送失败: {e}")

def check_availability():
    """检查库存函数"""
    try:
        response = requests.get(OVH_API_URL, timeout=10)
        response.raise_for_status()
        data = response.json()
        
        available_items = []
        for item in data:
            if item["storage"] in CONFIGS:  # 只检查我们关注的配置
                for datacenter in item["datacenters"]:
                    if datacenter["datacenter"] in DATACENTERS and datacenter["availability"] == "available":
                        available_items.append({
                            "fqn": item["fqn"],
                            "storage": item["storage"],
                            "datacenter": datacenter["datacenter"]
                        })
        return available_items
    except requests.exceptions.RequestException as e:
        print(f"请求失败: {e}")
        return []

def main():
    """主程序"""
    global last_availability
    while True:
        print("正在检查库存...")
        available_items = check_availability()
        
        if available_items:
            # 生成库存信息
            content = "以下商品有库存：\n"
            for item in available_items:
                key = f"{item['storage']}_{item['datacenter']}"
                content += f"商品名称: {item['fqn']}\n硬盘类型: {item['storage']}\n服务器地址: {item['datacenter']}\n\n"
                
                # 检查是否已通知过
                if key not in last_availability or not last_availability[key]:
                    last_availability[key] = True  # 标记为已通知
                    print(f"新库存：{item['storage']} 在 {item['datacenter']} 有货！")
            
            # 发送钉钉通知
            send_dingtalk_notification(content)
        else:
            print("当前无货。")
            # 清除上次记录（无货时重新监控）
            last_availability = {key: False for key in last_availability}
        
        print("等待下一次检查...")
        time.sleep(CHECK_INTERVAL)

if __name__ == "__main__":
    print("OVH库存监控程序启动...")
    print(f"监控配置: {CONFIGS}")
    print(f"监控数据中心: {DATACENTERS}")
    print(f"检查间隔: {CHECK_INTERVAL}秒")
    
    while True:
        try:
            main()
        except Exception as e:
            print(f"主程序出错: {e}")
            print(f"{RETRY_INTERVAL} 秒后重试...")
            time.sleep(RETRY_INTERVAL)