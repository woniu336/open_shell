import pandas as pd
import requests
import time
from urllib.parse import quote, urlparse
from concurrent.futures import ThreadPoolExecutor, as_completed

def check_link(row):
    filename, url = row['文件名'], row['链接']
    
    check_url = f'https://123.com/check_link.php?url={quote(url)}'
    try:
        response = requests.get(check_url, timeout=10)
        if response.status_code == 200:
            result = response.json()
            if 'valid' in result:
                status = "有效" if result['valid'] else "无效"
                return filename, url, status
            elif 'error' in result:
                return filename, url, f"检查失败 ({result['error']})"
        else:
            return filename, url, f"检查失败 (状态码: {response.status_code})"
    except requests.RequestException as e:
        return filename, url, f"检查失败 ({str(e)})"

def main():
    start_time = time.time()
    
    df = pd.read_excel('links.xlsx')
    
    results = []
    
    with ThreadPoolExecutor(max_workers=10) as executor:
        future_to_row = {executor.submit(check_link, row): row for _, row in df.iterrows()}
        for future in as_completed(future_to_row):
            results.append(future.result())
    
    total_links = len(results)
    invalid_links = [r for r in results if r[2] != "有效"]
    invalid_count = len(invalid_links)
    valid_count = total_links - invalid_count
    
    end_time = time.time()
    duration = end_time - start_time
    
    content = f"""
    <div class="container">
        <h1 class="title">网盘资源监控 📊</h1>

        <div class="stats">
            <div class="stat-item">
                <div class="stat-circle" style="--percentage: {valid_count/total_links*100}%;">
                    <span class="stat-number">{valid_count}</span>
                </div>
                <div class="stat-label">有效链接</div>
            </div>
            <div class="stat-item">
                <div class="stat-circle" style="--percentage: {invalid_count/total_links*100}%;">
                    <span class="stat-number">{invalid_count}</span>
                </div>
                <div class="stat-label">无效链接</div>
            </div>
        </div>

        <div class="duration">检测用时: {duration:.2f} 秒 ⏱️</div>

        <h2>无效链接</h2>
        <table class="invalid-links-table">
            <thead>
                <tr>
                    <th>文件名</th>
                    <th>链接</th>
                    <th>状态</th>
                </tr>
            </thead>
            <tbody>
    """

    for filename, url, status in invalid_links:
        parsed_url = urlparse(url)
        domain = parsed_url.netloc
        content += f'''
            <tr>
                <td>{filename}</td>
                <td><a href="{url}" target="_blank">{domain}</a></td>
                <td>{status}</td>
            </tr>
        '''

    content += """
            </tbody>
        </table>

        <h2>检查结果</h2>
        <div class="link-list">
    """

    for filename, url, status in results:
        status_class = 'valid' if status == '有效' else 'invalid'
        status_icon = '😊' if status == '有效' else '😞'
        parsed_url = urlparse(url)
        domain = parsed_url.netloc
        content += f'''
        <div class="link-item {status_class}">
            <div class="link-icon">{status_icon}</div>
            <div class="link-details">
                <div class="link-filename">{filename}</div>
                <div class="link-url"><a href="{url}" target="_blank">{domain}</a></div>
            </div>
        </div>
        '''

    content += "</div>\n</div>"
    
    html_doc = f"""
    <!DOCTYPE html>
    <html lang="zh-CN">
    <head>
        <meta charset="UTF-8"/>
        <link rel="shortcut icon" href="/favicon.ico" type="image/x-icon"/>
        <link rel="icon" type="image/svg+xml" href="/statics/img/logo.svg"/>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no"/>
        <meta name="renderer" content="webkit|ie-comp|ie-stand"/>
        <title>链接检查结果 - 资源猫</title>
        <link rel="stylesheet" href="https://lf6-cdn-tos.bytecdntp.com/cdn/expire-1-M/font-awesome/6.0.0/css/all.min.css">
        <style>
            body {{
                font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
                line-height: 1.6;
                color: #333;
                background-color: #f0f4f8;
                margin: 0;
                padding: 0;
            }}
            .header {{
                background-color: #3498db;
                color: white;
                text-align: center;
                padding: 1rem;
            }}
            .site-title {{
                font-size: 1.5rem;
                text-decoration: none;
                color: white;
            }}
            .container {{
                max-width: 800px;
                margin: 0 auto;
                padding: 20px;
                background-color: #ffffff;
                box-shadow: 0 0 10px rgba(0,0,0,0.1);
                border-radius: 10px;
            }}
            .title {{
                text-align: center;
                font-size: 28px;
                color: #2c3e50;
                margin-bottom: 30px;
            }}
            .stats {{
                display: flex;
                justify-content: space-around;
                margin-bottom: 30px;
            }}
            .stat-item {{
                text-align: center;
            }}
            .stat-circle {{
                width: 120px;
                height: 120px;
                border-radius: 50%;
                background: conic-gradient(
                    #3498db calc(var(--percentage) * 1%),
                    #ecf0f1 0
                );
                display: flex;
                align-items: center;
                justify-content: center;
                box-shadow: 0 4px 6px rgba(0,0,0,0.1);
            }}
            .stat-number {{
                font-size: 28px;
                font-weight: bold;
                color: #2c3e50;
            }}
            .stat-label {{
                margin-top: 10px;
                font-weight: bold;
                color: #34495e;
            }}
            .duration {{
                text-align: center;
                font-style: italic;
                margin-bottom: 30px;
                color: #7f8c8d;
            }}
            h2 {{
                color: #2c3e50;
                text-align: center;
                margin-bottom: 20px;
            }}
            .link-list {{
                display: flex;
                flex-direction: column;
                align-items: center;
            }}
            .link-item {{
                display: flex;
                align-items: center;
                width: 100%;
                max-width: 600px;
                margin-bottom: 15px;
                padding: 10px;
                background-color: #f8f9fa;
                border-radius: 8px;
                box-shadow: 0 2px 4px rgba(0,0,0,0.1);
                transition: transform 0.2s ease-in-out;
            }}
            .link-item:hover {{
                transform: translateY(-3px);
            }}
            .link-icon {{
                font-size: 24px;
                margin-right: 15px;
            }}
            .link-details {{
                flex-grow: 1;
            }}
            .link-filename {{
                font-weight: bold;
                color: #2c3e50;
            }}
            .link-url a {{
                color: #3498db;
                text-decoration: none;
            }}
            .link-url a:hover {{
                text-decoration: underline;
            }}
            .valid {{
                border-left: 4px solid #27ae60;
            }}
            .invalid {{
                border-left: 4px solid #e74c3c;
            }}
            .invalid-links-table {{
                width: 100%;
                border-collapse: collapse;
                margin-top: 20px;
                margin-bottom: 30px;
            }}
            .invalid-links-table th, .invalid-links-table td {{
                border: 1px solid #ddd;
                padding: 8px;
                text-align: left;
            }}
            .invalid-links-table th {{
                background-color: #f2f2f2;
                font-weight: bold;
            }}
            .invalid-links-table tr:nth-child(even) {{
                background-color: #f9f9f9;
            }}
            .invalid-links-table tr:hover {{
                background-color: #f5f5f5;
            }}
        </style>
    </head>
    <body>
        <header class="header">
            <a href="/" class="site-title">资源猫</a>
        </header>

        {content}
    </body>
    </html>
    """
    
    with open('link_check_results.html', 'w', encoding='utf-8') as f:
        f.write(html_doc)
    
    print(f"检查完成，结果已保存到 link_check_results.html")
    print(f"检测用时: {duration:.2f} 秒")

if __name__ == "__main__":
    main()