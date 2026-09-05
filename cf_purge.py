#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
xxxxx.com 专属 Cloudflare 缓存清理与广告联动运维工具
=====================================================
功能清单:
1. 指定视频 ID 清除 (自动刷新对应详情页 + 该剧所有集数播放页)
2. 清除所有播放页 (/play/)
3. 清除分类与展示筛选页 (/type/ 与 /show/)
4. 清除详情页 (/video/)
5. 广告切换全联动清理 (同时清除 /play/、/video/、/type/、/show/)
6. 查看/一键配置分时段广告切换的 Linux Crontab 定时任务
7. 清空整站所有缓存 (Purge Everything)

命令行快捷用法:
  python cf_purge.py 42003      # 清理 ID 为 42003 的视频及全部播放页
  python cf_purge.py play       # 清理所有播放页 (/play/)
  python cf_purge.py type       # 清理所有分类与筛选页 (/type/ 与 /show/)
  python cf_purge.py video      # 清理所有详情页 (/video/)
  python cf_purge.py ad         # 广告全联动清理 (play + video + type + show)
  python cf_purge.py cron       # 输出或配置 Linux 定时任务
  python cf_purge.py all        # 清空整站所有缓存
"""

import sys
import os
import json
import urllib.request
import urllib.error

# ==================== 配置区 ====================
# 请将下方两项替换为你自己的 Cloudflare 凭证
ZONE_ID = ""      # 替换为你的 Cloudflare Zone ID (区域ID)
API_TOKEN = ""  # 替换为你的 Cloudflare API Token (API令牌)
DOMAIN = "xxxxx.com"

# 服务器上各脚本的实际存放绝对路径 (用于生成/配置 crontab 定时任务)
SERVER_RESTORE_SCRIPT = "/root/restore_mxonest.py"
SERVER_CF_PURGE_SCRIPT = "/root/cf_purge.py"
# =================================================

API_URL = f"https://api.cloudflare.com/client/v4/zones/{ZONE_ID}/purge_cache"


def send_cf_purge(payload: dict) -> bool:
    """发送请求到 Cloudflare API 执行缓存清除"""
    headers = {
        "Authorization": f"Bearer {API_TOKEN}",
        "Content-Type": "application/json"
    }
    req = urllib.request.Request(
        API_URL,
        data=json.dumps(payload).encode("utf-8"),
        headers=headers,
        method="POST"
    )
    try:
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            if data.get("success"):
                task_id = data.get("result", {}).get("id", "N/A")
                print(f"  [✓] 清理成功！(Task ID: {task_id})")
                return True
            else:
                print(f"  [✗] 清理失败: {data.get('errors')}")
                return False
    except urllib.error.HTTPError as e:
        err_msg = e.read().decode("utf-8")
        print(f"  [✗] 请求错误 HTTP {e.code}: {err_msg}")
        return False
    except Exception as e:
        print(f"  [✗] 网络异常: {e}")
        return False


def purge_by_video_id(vod_id: str):
    """
    根据单个视频 ID 清除:
    1. /video/{id}.html (详情页)
    2. /play/{id} 前缀 (覆盖该视频下所有集数播放页)
    """
    vod_id = str(vod_id).strip()
    print(f"\n>> 正在清理视频 ID [{vod_id}] 的详情页及所有集数播放页...")
    payload = {
        "files": [
            f"https://{DOMAIN}/video/{vod_id}.html"
        ],
        "prefixes": [
            f"{DOMAIN}/play/{vod_id}"
        ]
    }
    send_cf_purge(payload)


def purge_play_pages():
    """清除所有播放页缓存 (/play/)"""
    print(f"\n>> 正在清除所有播放页缓存 ({DOMAIN}/play/)...")
    payload = {
        "prefixes": [
            f"{DOMAIN}/play/"
        ]
    }
    send_cf_purge(payload)


def purge_category_and_show():
    """清除全部分类页、筛选页 (/type/ 和 /show/)"""
    print(f"\n>> 正在清除分类页 ({DOMAIN}/type/) 与展示页 ({DOMAIN}/show/)...")
    payload = {
        "prefixes": [
            f"{DOMAIN}/type/",
            f"{DOMAIN}/show/"
        ]
    }
    send_cf_purge(payload)


def purge_video_pages():
    """清除所有视频详情页缓存 (/video/)"""
    print(f"\n>> 正在清除所有视频详情页缓存 ({DOMAIN}/video/)...")
    payload = {
        "prefixes": [
            f"{DOMAIN}/video/"
        ]
    }
    send_cf_purge(payload)


def purge_for_ad_switch():
    """
    广告上下线全联动清理：
    包含播放页 (/play/)、详情页 (/video/)、分类列表页 (/type/) 与 筛选展示页 (/show/)
    """
    print(f"\n>> 正在执行广告切换全联动清理 (/play/ + /video/ + /type/ + /show/)...")
    payload = {
        "prefixes": [
            f"{DOMAIN}/play/",
            f"{DOMAIN}/video/",
            f"{DOMAIN}/type/",
            f"{DOMAIN}/show/"
        ]
    }
    send_cf_purge(payload)


def purge_everything():
    """清除全站所有缓存"""
    confirm = input("确定要清空整站所有缓存吗？这将导致源站负载升高 (y/N): ")
    if confirm.lower() == "y":
        print(f"\n>> 正在清空 {DOMAIN} 全部缓存...")
        send_cf_purge({"purge_everything": True})
    else:
        print("已取消。")


def manage_cron_menu():
    """查看与配置分时段广告切换 Crontab 定时任务"""
    cron_night = f"0 19 * * * python3 {SERVER_RESTORE_SCRIPT} ddd && python3 {SERVER_CF_PURGE_SCRIPT} ad"
    cron_day = f"0 6 * * * python3 {SERVER_RESTORE_SCRIPT} bak && python3 {SERVER_CF_PURGE_SCRIPT} ad"

    print("\n" + "=" * 60)
    print("【分时段广告自动轮换】定时任务方案:")
    print("=" * 60)
    print("规则说明:")
    print(f"  • 每日 19:00: 切换至广告配置(ddd.php) -> 自动刷新 CF 全站缓存")
    print(f"  • 每日 06:00: 切换至无广告配置(bbb.php) -> 自动刷新 CF 全站缓存")
    print("\n对应的 Crontab 命令格式如下:")
    print(f"  {cron_night}")
    print(f"  {cron_day}")
    print("=" * 60)

    if os.name != "posix":
        print("【提示】检测到当前运行在 Windows 环境，请将上方两行规则复制到 Linux 服务器终端执行：")
        print(f'(crontab -l 2>/dev/null; echo "{cron_night}") | crontab -')
        print(f'(crontab -l 2>/dev/null; echo "{cron_day}") | crontab -')
        return

    # Linux 下支持一键写入当前用户的 crontab
    choice = input("\n检测到处于 Linux 环境，是否直接写入当前服务器的 Crontab？(y/N): ").strip().lower()
    if choice == "y":
        cmd = f'(crontab -l 2>/dev/null; echo "{cron_night}"; echo "{cron_day}") | crontab -'
        res = os.system(cmd)
        if res == 0:
            print("  [✓] 定时任务写入成功！已设置 19:00 上广告与 06:00 撤广告并联动刷新缓存。")
        else:
            print("  [✗] 定时任务写入失败，请检查权限。")
    else:
        print("操作已取消。")


def main():
    # 支持命令行参数直接调用
    if len(sys.argv) > 1:
        arg = sys.argv[1].strip().lower()
        if arg == "cron":
            manage_cron_menu()
            return
        
        # 缓存操作前检查配置
        if ZONE_ID == "YOUR_CF_ZONE_ID" or API_TOKEN == "YOUR_CF_API_TOKEN":
            print("【提示】请先用编辑器打开脚本，配置顶部的 ZONE_ID 和 API_TOKEN！")
            sys.exit(1)

        if arg == "play":
            purge_play_pages()
        elif arg == "type":
            purge_category_and_show()
        elif arg == "video":
            purge_video_pages()
        elif arg == "ad":
            purge_for_ad_switch()
        elif arg == "all":
            purge_everything()
        elif arg.isdigit():
            purge_by_video_id(arg)
        else:
            print("快捷命令参数无效。用法说明:")
            print("  python cf_purge.py <视频ID>  (例如: python cf_purge.py 42003)")
            print("  python cf_purge.py play      (清理所有播放页)")
            print("  python cf_purge.py type      (清理分类与筛选页)")
            print("  python cf_purge.py video     (清理所有详情页)")
            print("  python cf_purge.py ad        (广告全联动清理：play+video+type+show)")
            print("  python cf_purge.py cron      (查看/配置广告定时切换 Crontab)")
            print("  python cf_purge.py all       (清空整站)")
        return

    # 交互式主菜单
    while True:
        print("\n" + "=" * 55)
        print(f" Cloudflare 缓存清理与广告联动工具 - {DOMAIN}")
        print("=" * 55)
        print("1. 清理指定视频 (输入ID，刷新详情页 + 所有集数播放页)")
        print("2. 清理所有播放页 (/play/)")
        print("3. 清理所有分类与筛选列表页 (/type/ 与 /show/)")
        print("4. 清理所有视频详情页 (/video/)")
        print("5. 广告切换全联动清理 (同时清除 play + video + type + show)")
        print("6. 查看/配置分时段【广告切换】定时任务 (Crontab)")
        print("7. 清空整站所有缓存 (Purge Everything)")
        print("0. 退出")
        print("=" * 55)
        choice = input("请选择操作 [0-7]: ").strip()

        if choice == "1":
            if ZONE_ID == "YOUR_CF_ZONE_ID":
                print("请先配置顶部的 ZONE_ID 和 API_TOKEN！")
                continue
            vod_id = input("请输入视频 ID (如 42003): ").strip()
            if vod_id:
                purge_by_video_id(vod_id)
        elif choice == "2":
            purge_play_pages()
        elif choice == "3":
            purge_category_and_show()
        elif choice == "4":
            purge_video_pages()
        elif choice == "5":
            purge_for_ad_switch()
        elif choice == "6":
            manage_cron_menu()
        elif choice == "7":
            purge_everything()
        elif choice == "0":
            print("已退出。")
            break
        else:
            print("无效输入，请重试。")


if __name__ == "__main__":
    main()
