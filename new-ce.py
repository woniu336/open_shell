#!/usr/bin/env python3
import os
import re

def clean_html_files(directory):
    # 需要替换的代码
    old_code = '<script type="text/javascript" language="javascript" src="/js/ads/foot960x90.js"></script>'
    new_code = '<script type="text/javascript" language="javascript" src="/js/components/foot960x90.js"></script>'
    
    # 计数器
    modified_files = 0
    
    # 递归遍历目录
    for root, dirs, files in os.walk(directory):
        for file in files:
            if file.endswith('.html'):
                file_path = os.path.join(root, file)
                
                try:
                    # 读取文件内容
                    with open(file_path, 'r', encoding='utf-8') as f:
                        content = f.read()
                    
                    # 检查文件是否包含需要替换的代码
                    if old_code in content:
                        # 替换代码
                        new_content = content.replace(old_code, new_code)
                        
                        # 写回文件
                        with open(file_path, 'w', encoding='utf-8') as f:
                            f.write(new_content)
                            
                        modified_files += 1
                        print(f'已更新文件: {file_path}')
                
                except Exception as e:
                    print(f'处理文件 {file_path} 时出错: {str(e)}')

    print(f'\n更新完成！共处理了 {modified_files} 个文件。')

if __name__ == '__main__':
    directory = '/www/wwwroot/123.cc'  # 请根据实际情况修改目录路径
    print(f'开始处理目录: {directory}')
    clean_html_files(directory)