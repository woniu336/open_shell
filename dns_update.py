import socket
import time
import requests

def check_tcp_port(server_ip, port):
    # 检测TCP端口的连通性
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

def update_dns_record(ip, proxied=False):
    # 使用Cloudflare API 更新 DNS 记录
    # 你需要替换以下参数为你的实际参数
    api_key = 'API密钥'
    email = '登录邮箱'
    zone_id = '区域ID'
    dns_record_id = 'DNS_ID'
    
    headers = {
        'X-Auth-Email': email,
        'X-Auth-Key': api_key,
        'Content-Type': 'application/json'
    }

    data = {
        'type': 'A',
        'name': '你的域名',  # 指定要更新的 DNS 记录的域名
        'content': ip,
        'proxied': proxied  # 指定是否开启代理
    }

    url = f'https://api.cloudflare.com/client/v4/zones/{zone_id}/dns_records/{dns_record_id}'
    
    response = requests.put(url, headers=headers, json=data)
    if response.status_code == 200:
        print("DNS记录更新成功！")
    else:
        print("DNS记录更新失败！")

def main():
    server_ip = '原始ip'
    backup_ip = '备用ip'
    original_ip = server_ip
    server_down = False
    using_backup_ip = False
    port = 80  # 检测的TCP端口号，您可以根据实际情况更改

    while True:
        if not server_down and not check_tcp_port(server_ip, port):
            print("服务器宕机，切换到备用IP并开启代理...")
            update_dns_record(backup_ip, proxied=True)
            using_backup_ip = True
            server_down = True
        elif server_down and check_tcp_port(server_ip, port):
            print("服务器已恢复，切换回原始IP并关闭代理...")
            update_dns_record(original_ip, proxied=False)
            using_backup_ip = False
            server_down = False

        if using_backup_ip:
            print("域名正在使用备用IP，并已开启代理。")
        else:
            print("服务器端口正常，等待下次检查...")

        time.sleep(600)  # 10分钟后再次检查

if __name__ == "__main__":
    main()

