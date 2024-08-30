# -*- coding: utf-8 -*- 
# @Time : 2020/9/18 10:26 
# @Author : ljy 
# @File : update warnsrc.py on 2024/08/31
import sys
import os
import requests

def send_warning(file_path):
    if os.path.getsize(file_path) == 0:
        return

    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    url = 'Webhook地址'
    
    data = {
        "msgtype": "text",
        "text": {"content": content},
        "at": {"isAtAll": "false"}
    }
    headers = {'Content-Type': 'application/json'}
    
    requests.post(url=url, headers=headers, json=data)

if __name__ == "__main__":
    if len(sys.argv) != 2:
        pass
    else:
        send_warning(sys.argv[1])