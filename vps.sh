#!/bin/bash

while true; do
    clear
    echo "请选择要执行的操作："
    echo "1. 执行VPS检测"
    echo "2. 磁盘真实性能读写测试"
    echo "3. 三网测速脚本"
    echo "4. 三网回程线路测试"
    echo "5. 三网回程延迟测试脚本"
    echo "6. ChatGPT解锁状态检测"
    echo "7. 流媒体解锁测试"
    echo "8. TikTok状态检测"
    echo "9. 测试CPU性能"
    echo "0. 退出"

    read -p "请输入操作编号: " choice

    case $choice in
        1)
            # 执行VPS检测
            clear
            echo "请选择要执行的VPS检测脚本："
            echo "1. 脚本1"
            echo "2. 脚本2"
            echo "0. 返回上一层"
            read -p "请输入脚本编号: " vps_choice
            if [ "$vps_choice" == "1" ]; then
                wget -q https://github.com/Aniverse/A/raw/i/a && bash a
            elif [ "$vps_choice" == "2" ]; then
                wget -qO- bench.sh | bash
            elif [ "$vps_choice" == "0" ]; then
                continue
            else
                echo "无效的脚本选择。"
            fi
            ;;
        2)
            # 磁盘真实性能读写测试
            clear
# 检查系统类型并安装 bc 工具
install_bc() {
    if [[ -f /etc/debian_version ]]; then
        if ! command -v bc &>/dev/null; then
            echo "安装 bc 工具..."
            sudo apt-get update
            sudo apt-get install -y bc
        fi
    elif [[ -f /etc/redhat-release ]]; then
        if ! command -v bc &>/dev/null; then
            echo "安装 bc 工具..."
            sudo yum install -y bc
        fi
    else
        echo "未知的系统类型，无法安装 bc 工具。"
        exit 1
    fi
}

install_bc

echo "开始进行磁盘真实性能读写测试..."

# 执行磁盘读写测试
result=$(dd bs=64k count=4k if=/dev/zero of=/tmp/test oflag=dsync 2>&1)

# 从测试结果中提取速度信息
speed=$(echo "$result" | grep -oP '\d+\.\d+ MB/s' | cut -d' ' -f1)

echo "测试完成，磁盘读写速度为: $speed MB/s"

if [[ $(echo "$speed > 80" | bc -l) -eq 1 ]]; then
    echo "磁盘性能优秀，速度大于80MB/s。"
elif [[ $(echo "$speed > 40" | bc -l) -eq 1 ]]; then
    echo "磁盘性能普通，速度大于40MB/s。"
elif [[ $(echo "$speed > 20" | bc -l) -eq 1 ]]; then
    echo "磁盘性能合格，速度大于20MB/s。"
else
    echo "磁盘性能不达标，速度低于20MB/s。"
fi
            ;;
        3)
            # 三网测速脚本
            clear
            bash <(curl -Lso- https://git.io/superspeed_uxh)
            ;;
        4)
            # 三网回程线路测试
            clear
            echo "请选择要执行的三网回程测试脚本："
            echo "1. 脚本1"
            echo "2. 脚本2"
            echo "0. 返回上一层"
            read -p "请输入脚本编号: " mtr_choice
            if [ "$mtr_choice" == "1" ]; then
                curl https://raw.githubusercontent.com/zhucaidan/mtr_trace/main/mtr_trace.sh | bash
            elif [ "$mtr_choice" == "2" ]; then
                curl https://raw.githubusercontent.com/zhanghanyun/backtrace/main/install.sh -sSf | sh
            elif [ "$mtr_choice" == "0" ]; then
                continue
            else
                echo "无效的脚本选择。"
            fi
            ;;
        5)
            # 三网回程延迟测试脚本操作
            clear
            wget -qO- git.io/besttrace | bash
            ;;
        6)
            # ChatGPT解锁状态检测
            clear
            bash <(curl -Ls https://cdn.jsdelivr.net/gh/missuo/OpenAI-Checker/openai.sh)
            ;;
        7)
            # 流媒体解锁测试
            clear
            bash <(curl -L -s check.unlock.media)
            ;;
        8)
            # TikTok状态检测
            clear
            wget -qO- https://github.com/yeahwu/check/raw/main/check.sh | bash
            ;;
        9)
            # 执行测试CPU性能操作
            clear
            apt update -y && apt install -y curl wget sudo
            curl -sL yabs.sh | bash -s -- -i -5
            ;;
        0)
            # 退出
            clear
            exit 0
            ;;
        *)
            echo "无效的操作编号，请重新输入。"
            ;;
    esac
    read -p "按 Enter 键继续..."
done
