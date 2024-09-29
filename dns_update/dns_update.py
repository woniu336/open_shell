import socket
import time
import requests
import hmac
import hashlib
import base64
import urllib.parse

# Cloudflare 配置
api_key = ''
email = ''
zone_id = ''

# 钉钉机器人配置
ACCESS_TOKEN = "YOUR_ACCESS_TOKEN"
SECRET = "YOUR_SECRET"

# 服务器备注（将由 Bash 脚本更新）
SERVER_REMARK = ""

def generate_sign():
    # 生成钉钉机器人签名
    timestamp = str(round(time.time() * 1000))
    secret_enc = SECRET.encode('utf-8')
    string_to_sign = f'{timestamp}\n{SECRET}'
    string_to_sign_enc = string_to_sign.encode('utf-8')
    hmac_code = hmac.new(secret_enc, string_to_sign_enc, digestmod=hashlib.sha256).digest()
    sign = urllib.parse.quote_plus(base64.b64encode(hmac_code))
    return timestamp, sign

def send_dingtalk_notification(message):
    # 在消息前添加服务器备注
    if SERVER_REMARK:
        message = f"[{SERVER_REMARK}] {message}"
    
    # 发送钉钉通知
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

def check_tcp_port(server_ip, port):
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(5)  # 设置超时时间为5秒
        result = sock.connect_ex((server_ip, port))
        if result == 0:
            return True  # TCP端口连通
        else:
            return False  # TCP端口不连通
    except Exception as e:
        print(f"Error occurred while checking TCP port: {e}")
        return False

def update_dns_record(subdomain, ip, proxied=False):
    try:
        dns_record_id = dns_record_ids[subdomain]  # 查找子域名对应的 DNS 记录 ID
        # 使用Cloudflare API 更新 DNS 记录
        headers = {
            'X-Auth-Email': email,
            'X-Auth-Key': api_key,
            'Content-Type': 'application/json'
        }

        data = {
            'type': 'A',
            'name': subdomain,
            'content': ip,
            'proxied': proxied
        }

        url = f'https://api.cloudflare.com/client/v4/zones/{zone_id}/dns_records/{dns_record_id}'

        response = requests.put(url, headers=headers, json=data)
        response_json = response.json()
        
        if response.status_code == 200 and response_json.get('success'):
            print(f"DNS记录更新成功！ 子域名: {subdomain}")
        else:
            print(f"DNS记录更新失败！ 子域名: {subdomain}")
            print(f"错误信息: {response_json.get('errors')}")
            print(f"响应内容: {response_json}")
    except KeyError:
        print(f"未找到子域名 {subdomain} 的 DNS 记录 ID")
    except Exception as e:
        print(f"更新 DNS 记录时发生错误: {e}")

def main():
    server_ip = ''
    backup_ip = ''
    original_ip = server_ip
    server_down = False
    using_backup_ip = False
    port = 

    subdomains = []  # 要更新的子域名列表

    original_ip_cdn_enabled = False  # 原始 IP 的 CDN 状态
    backup_ip_cdn_enabled = True    # 备用 IP 的 CDN 状态

    while True:
        try:
            if not server_down and not check_tcp_port(server_ip, port):
                message = f"服务器宕机，切换到备用IP {backup_ip}"
                print(message)
                send_dingtalk_notification(message)
                for subdomain in subdomains:
                    update_dns_record(subdomain, backup_ip, proxied=backup_ip_cdn_enabled)
                using_backup_ip = True
                server_down = True
            elif server_down and check_tcp_port(server_ip, port):
                message = f"服务器已恢复，切换回原始IP {original_ip}"
                print(message)
                send_dingtalk_notification(message)
                for subdomain in subdomains:
                    update_dns_record(subdomain, original_ip, proxied=original_ip_cdn_enabled)
                using_backup_ip = False
                server_down = False

            if using_backup_ip:
                print(f"域名正在使用备用IP。CDN 状态：{'已开启' if backup_ip_cdn_enabled else '已关闭'}")
            else:
                print(f"域名正在使用原始IP。CDN 状态：{'已开启' if original_ip_cdn_enabled else '已关闭'}")

            time.sleep(300)  # 5分钟后再次检查
        except Exception as e:
            error_message = f"发生未捕获的异常：{e}"
            print(error_message)
            send_dingtalk_notification(error_message)

if __name__ == "__main__":
    main()