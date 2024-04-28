import socket
import time
import requests

api_key = ''
email = ''
zone_id = ''

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
        if response.status_code == 200:
            print(f"DNS记录更新成功！ 子域名: {subdomain}")
        else:
            print(f"DNS记录更新失败！ 子域名: {subdomain}")
    except KeyError:
        print(f"未找到子域名 {subdomain} 的 DNS 记录 ID")

def main():
    server_ip = ''
    backup_ip = ''
    original_ip = server_ip
    server_down = False
    using_backup_ip = False
    port = 

    subdomains = []  # 要更新的子域名列表

    while True:
        try:
            if not server_down and not check_tcp_port(server_ip, port):
                print("服务器宕机，切换到备用IP并开启代理...")
                for subdomain in subdomains:
                    update_dns_record(subdomain, backup_ip, proxied=True)
                using_backup_ip = True
                server_down = True
            elif server_down and check_tcp_port(server_ip, port):
                print("服务器已恢复，切换回原始IP并关闭代理...")
                for subdomain in subdomains:
                    update_dns_record(subdomain, original_ip, proxied=False)
                using_backup_ip = False
                server_down = False

            if using_backup_ip:
                print("域名正在使用备用IP，并已开启代理。")
            else:
                print("服务器端口正常，5分钟后再次检查...")

            time.sleep(300)  # 5分钟后再次检查
        except Exception as e:
            print(f"发生未捕获的异常：{e}")

if __name__ == "__main__":
    main()
