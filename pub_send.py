#!/usr/bin/env python3
import os

# 删除用户家目录下的 SSH 密钥文件
os.system('rm -rf ~/.ssh/id_rsa*')

# 生成新的 SSH 密钥对
os.system('ssh-keygen -f ~/.ssh/id_rsa -P "" >/dev/null 2>&1')

# 设置 SSH 密钥路径
key_path = os.path.expanduser('~/.ssh/id_rsa.pub')

# 定义IP地址列表、用户名、密码和端口
hosts_and_passwords = {
    "192.168.1.28": {"user": "root", "password": "123456", "port": 22},
    "192.168.1.29": {"user": "root", "password": "123456", "port": 22},
    "192.168.1.30": {"user": "root", "password": "123456", "port": 22}
}

# 循环遍历 IP 地址列表，将 SSH 公钥复制到远程主机
for host, credentials in hosts_and_passwords.items():
    user = credentials["user"]
    password = credentials["password"]
    port = credentials["port"]
    os.system(f'sshpass -p "{password}" ssh-copy-id -i {key_path} -o StrictHostKeyChecking=no -p {port} {user}@{host}')