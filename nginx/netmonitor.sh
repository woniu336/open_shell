#!/usr/bin/env bash

# 检查是root权限，否则退出
if [ $(id -u) -ne 0 ]; then
    echo "请使用root权限运行此脚本"
    exit 1
fi

# 检查是否存在/opt/NetMonitor文件夹和 /etc/systemd/system/netmonitor.service 文件，任意存在则询问是否删除并重新安装、升级并保留配置文件，或退出安装。
if [ -d "/opt/NetMonitor" ] || [ -f "/etc/systemd/system/netmonitor.service" ]; then
    echo "已经安装NetMonitor，请选择操作："
    echo "1. 删除并重新安装"
    echo "2. 升级并保留配置文件"
    echo "3. 退出安装"
    echo "4. 删除NetMonitor"
    read -p "请输入选项（1/2/3/4）：" choice
    case $choice in
        1)
            systemctl stop netmonitor
            systemctl disable netmonitor
            rm -rf /opt/NetMonitor
            rm -f /etc/systemd/system/netmonitor.service
            ;;
        2)
            systemctl stop netmonitor
            systemctl disable netmonitor
            rm -f /opt/NetMonitor/netmonitor
            ;;
        3)
            echo "退出安装"
            exit 1
            ;;
        4)
            systemctl stop netmonitor
            systemctl disable netmonitor
            rm -rf /opt/NetMonitor
            rm -f /etc/systemd/system/netmonitor.service
            echo "NetMonitor已删除"
            exit 0
            ;;
        *)
            echo "无效的选项，退出安装"
            exit 1
            ;;
    esac
else
        choice="1"  # 第一次安装时设置默认值
fi

# 检查依赖curl和wget是否已经安装，如果没有，则安装。适配Debian和RedHat系列发行版。
echo "检查依赖..."
if command -v apt-get &> /dev/null; then
    apt-get update
    apt-get install -y curl wget
elif command -v yum &> /dev/null; then
    yum install -y curl wget
else
    distribution=$(grep "^ID=" /etc/*release | cut -d= -f2 | tr -d \")
    echo "不支持 $distribution 系统，请提出issue进行添加"
    exit 1
fi

# 创建文件夹和文件
echo "创建文件夹和文件..."

if [ "$choice" != "2" ]; then
    mkdir -p /opt/NetMonitor
    touch /opt/NetMonitor/error.log /opt/NetMonitor/output.log
    chmod 666 /opt/NetMonitor/error.log /opt/NetMonitor/output.log
fi

# 通过github api从https://github.com/nodeseeker/netMonitor/releases获取最新的版本号，下载地址
cd /opt/NetMonitor
echo "获取最新版本号..."
version=$(curl -s https://api.github.com/repos/nodeseeker/netMonitor/releases/latest | grep "tag_name" | cut -d\" -f4)
arch=$(uname -m)
case $arch in
    x86_64) arch="amd64" ;;
    aarch64) arch="arm64" ;;
    *) echo "不支持 $arch CPU架构"; exit 1 ;;
esac

download_url="https://github.com/nodeseeker/netMonitor/releases/download/$version/netmonitor-linux-$arch"
echo "下载地址：$download_url"
wget -O netmonitor $download_url
chmod +x netmonitor

if [ "$choice" != "2" ]; then
    # 创建配置文件
    echo "创建配置文件..."
    read -p "请输入设备名称：" device_name


    # 获取所有网卡名称
    network_interfaces=($(ls /sys/class/net | grep -v lo))
    default_interface=${network_interfaces[0]}

    # 使用第一个非lo的网卡作为默认名称并询问是否需要修改
    read -p "检测到默认网卡名称为 $default_interface，是否需要修改？（y/n）" modify_interface
    if [ "$modify_interface" == "y" ]; then
        read -p "请输入监控网卡名称：" network_interface
    else
        network_interface=$default_interface
    fi

    # 检查网卡名称是否存在
    if [ ! -d "/sys/class/net/$network_interface" ]; then
        echo "网卡 $network_interface 不存在，退出安装"
        exit 1
    fi

    read -p "请输入流量重置日期（1-31）：" start_day
    if ! [[ "$start_day" =~ ^[1-9]$|^[12][0-9]$|^3[01]$ ]]; then
        echo "无效的日期，必须在1-31之间，退出安装"
        exit 1
    fi

    read -p "请输入上次重置时间（格式：2024-08-09）：" last_reset
    if ! [[ "$last_reset" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        echo "无效的日期格式，必须为yyyy-mm-dd，退出安装"
        exit 1
    fi

    read -p "请选择流量统计方式，仅输入数字：1. 单向上传 2. 单向下载 3. 双向计算 4. 任意最大值：" traffic_type
    case $traffic_type in
        1) traffic_type="upload" ;;
        2) traffic_type="download" ;;
        3) traffic_type="upload+download" ;;
        4) traffic_type="anymax" ;;
        *) echo "无效的输入"; exit 1 ;;
    esac

    read -p "请输入月流量上限（单位：GB）：" monthly_traffic
    read -p "请输入流量提示比例，例如0.85（即85%时发出提示）：" traffic_threshold
    read -p "请输入流量警告比例，例如0.95（即95%时发出警告并关机）：" traffic_ratio
    read -p "请输入Telegram机器人的Token：" telegram_bot_token
    read -p "请输入Telegram的Chat ID：" telegram_chat_id

    cat <<EOL > /opt/NetMonitor/config.json
{
    "device": "$device_name",
    "interface": "$network_interface",
    "interval": 60,
    "start_day": $start_day,
    "statistics": {
        "total_receive": 0,
        "total_transmit": 0,
        "last_receive": 0,
        "last_transmit": 0,
        "last_reset": "$last_reset"
    },
    "comparison": {
        "category": "$traffic_type",
        "limit": $monthly_traffic,
        "threshold": $traffic_threshold,
        "ratio": $traffic_ratio
    },
    "message": {
        "telegram": {
            "threshold_status": false,
            "ratio_status": false,
            "token": "$telegram_bot_token",
            "chat_id": "$telegram_chat_id"
        }
    }
}
EOL
fi

# 创建systemd服务
echo "创建systemd服务文件..."
if [ "$choice" != "2" ]; then
    # 创建systemd服务
    echo "创建systemd服务文件..."
    cat <<EOL > /etc/systemd/system/netmonitor.service
[Unit]
Description=Network Bandwidth Monitor
After=network.target

[Service]
WorkingDirectory=/opt/NetMonitor
ExecStart=/opt/NetMonitor/netmonitor -c /opt/NetMonitor/config.json
StandardOutput=file:/opt/NetMonitor/output.log
StandardError=file:/opt/NetMonitor/error.log
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOL
fi

# 设置开机自启并启动服务
echo "设置开机自启并启动服务..."
systemctl daemon-reload
systemctl enable netmonitor
systemctl start netmonitor

# 提示systemd操作命令
echo "NetMonitor已安装并启动，可以使用以下命令操作："
echo "运行 systemctl restart netmonitor 重启服务"
echo "运行 systemctl stop netmonitor 停止服务"
echo "运行 systemctl status netmonitor 查看服务状态"

echo "安装完成！"