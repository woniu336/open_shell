#!/usr/bin/env python3
import os
import re

def clean_html_files(directory):
    # 需要删除的恶意代码（注意引号格式）
    malicious_code = '"<script src="//zz.bdstatiic.com/linksubmit/plus.js"></script>'
    
    # 计数器
    cleaned_files = 0
    
    # 递归遍历目录
    for root, dirs, files in os.walk(directory):
        for file in files:
            if file.endswith('.html'):
                file_path = os.path.join(root, file)
                
                try:
                    # 读取文件内容
                    with open(file_path, 'r', encoding='utf-8') as f:
                        content = f.read()
                    
                    # 检查文件是否包含恶意代码
                    if malicious_code in content:
                        # 删除恶意代码
                        new_content = content.replace(malicious_code, '')
                        
                        # 写回文件
                        with open(file_path, 'w', encoding='utf-8') as f:
                            f.write(new_content)
                            
                        cleaned_files += 1
                        print(f'已清理文件: {file_path}')
                
                except Exception as e:
                    print(f'处理文件 {file_path} 时出错: {str(e)}')

    print(f'\n清理完成！共处理了 {cleaned_files} 个文件。')

if __name__ == '__main__':
    directory = '/www/wwwroot/123.cc'
    print(f'开始清理目录: {directory}')
    clean_html_files(directory)