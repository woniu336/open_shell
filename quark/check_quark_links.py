import json
import sys
from quark_auto_save import Quark

def print_bordered_table(title, data, headers):
    if not data:
        return
    
    # 计算每列的最大宽度
    col_widths = [max(len(str(row[i])) for row in data + [headers]) for i in range(len(headers))]
    
    # 计算总宽度
    total_width = sum(col_widths) + len(col_widths) * 3 + 1
    
    # 打印标题
    print("╔" + "═" * (total_width - 2) + "╗")
    print(f"║ {title.center(total_width - 4)} ║")
    print("╠" + "═" * (total_width - 2) + "╣")
    
    # 打印表头
    header_row = "║ " + " │ ".join(h.ljust(w) for h, w in zip(headers, col_widths)) + " ║"
    print(header_row)
    print("╠" + "═" * (total_width - 2) + "╣")
    
    # 打印数据行
    for row in data:
        data_row = "║ " + " │ ".join(str(cell).ljust(w) for cell, w in zip(row, col_widths)) + " ║"
        print(data_row)
    
    # 打印底部边框
    print("╚" + "═" * (total_width - 2) + "╝")

def check_quark_links(config_file):
    # 读取配置文件
    with open(config_file, 'r', encoding='utf-8') as file:
        config_data = json.load(file)

    # 获取cookie
    cookie = config_data.get('cookie', [])[0] if config_data.get('cookie') else None
    if not cookie:
        print("\033[0;31m错误: 配置文件中没有找到 cookie。\033[0m")
        return

    # 创建Quark对象
    quark = Quark(cookie, 0)

    # 验证账号
    if not quark.init():
        print("\033[0;31m错误: 账号验证失败，请检查cookie是否有效。\033[0m")
        return

    print(f"\033[0;32m账号验证成功: {quark.nickname}\033[0m")

    # 检查所有任务的链接
    tasklist = config_data.get('tasklist', [])
    invalid_links = []
    valid_count = 0

    for task in tasklist:
        taskname = task.get('taskname', '未知')
        shareurl = task.get('shareurl')
        
        if not shareurl:
            print(f"\033[0;33m警告: 任务 '{taskname}' 没有找到有效的分享链接。\033[0m")
            continue

        print(f"\n正在检查任务: {taskname}")
        pwd_id, _ = quark.get_id_from_url(shareurl)
        is_valid, message = quark.get_stoken(pwd_id)

        if is_valid:
            print(f"\033[0;32m链接有效: {taskname}\033[0m")
            valid_count += 1
        else:
            print(f"\033[0;31m链接无效: {taskname} - {message}\033[0m")
            invalid_links.append((taskname, shareurl))

    # 打印汇总结果
    print("\n\033[1;34m检查结果汇总:\033[0m")
    
    if invalid_links:
        print_bordered_table("失效链接", invalid_links, ["任务名称", "失效URL"])
    else:
        print("\033[0;32m没有发现失效链接。\033[0m")
    
    print(f"\n总计检查了 {len(tasklist)} 个链接，其中 {valid_count} 个有效，{len(invalid_links)} 个无效。")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("使用方法: python3 check_quark_links.py <配置文件路径>")
        sys.exit(1)
    
    config_file = sys.argv[1]
    check_quark_links(config_file)