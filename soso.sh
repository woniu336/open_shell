#!/bin/bash

while true; do
    clear
    echo "请选择操作:"
    echo "1) 谷歌云一键重装"
	echo "2) 未完待续..."
    echo "0) 返回上一层"
    read -p "请输入操作编号: " choice

    case $choice in

        1)
            # 谷歌云一键重装
            curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/gd.sh && chmod +x gd.sh && ./gd.sh
            ;;
        0)
            # 返回上一层
            break
            ;;
        *)
            echo "无效的操作编号，请重新输入。"
            ;;
    esac

    read -p "按Enter键继续..."
done
