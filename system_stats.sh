#!/bin/bash

# 设置终端颜色
GREEN='\033[0;32m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# 确保脚本以root权限运行
if [ "$EUID" -ne 0 ]; then
  echo -e "${GREEN}请以root权限运行此脚本${NC}"
  exit 1
fi

# 获取系统运行时间（秒）
uptime_seconds=$(cat /proc/uptime | awk '{print $1}' | cut -d. -f1)
# 换算成天、小时、分钟、秒
days=$((uptime_seconds / 86400))
hours=$(( (uptime_seconds % 86400) / 3600 ))
minutes=$(( (uptime_seconds % 3600) / 60 ))
seconds=$((uptime_seconds % 60))
uptime_formatted="${days}天 ${hours}小时 ${minutes}分钟 ${seconds}秒"

# 获取网络流量信息
# 先获取所有活跃的网络接口
interfaces=$(ip -o link show | awk -F': ' '$2 != "lo" && $2 ~ /^[a-zA-Z0-9]+$/ {print $2}')

total_rx=0
total_tx=0

for interface in $interfaces; do
  # 检查接口是否存在于 /proc/net/dev
  if grep -q "$interface:" /proc/net/dev; then
    # 获取接收和发送的字节数
    rx_bytes=$(grep "$interface:" /proc/net/dev | awk '{print $2}')
    tx_bytes=$(grep "$interface:" /proc/net/dev | awk '{print $10}')
    
    # 累加总流量
    total_rx=$((total_rx + rx_bytes))
    total_tx=$((total_tx + tx_bytes))
  fi
done

# 转换为人类可读的格式
function convert_bytes {
  local bytes=$1
  local unit="B"
  
  if [ $bytes -ge 1073741824 ]; then
    bytes=$(echo "scale=2; $bytes/1073741824" | bc)
    unit="GB"
  elif [ $bytes -ge 1048576 ]; then
    bytes=$(echo "scale=2; $bytes/1048576" | bc)
    unit="MB"
  elif [ $bytes -ge 1024 ]; then
    bytes=$(echo "scale=2; $bytes/1024" | bc)
    unit="KB"
  fi
  
  echo "$bytes $unit"
}

rx_human=$(convert_bytes $total_rx)
tx_human=$(convert_bytes $total_tx)
total_human=$(convert_bytes $((total_rx + total_tx)))

# 获取内存使用情况
mem_total=$(free -m | awk '/^Mem:/ {print $2}')
mem_used=$(free -m | awk '/^Mem:/ {print $3}')
mem_percent=$(echo "scale=2; $mem_used*100/$mem_total" | bc)

# 清屏
clear

# 绘制表格标题
echo -e "${GREEN}${BOLD}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
echo -e "${GREEN}${BOLD}┃                系统状态监控报告                    ┃${NC}"
echo -e "${GREEN}${BOLD}┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫${NC}"

# 运行时间表格
echo -e "${GREEN}┃${NC} ${BOLD}系统运行时间${NC}                                        ${GREEN}┃${NC}"
echo -e "${GREEN}┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫${NC}"
echo -e "${GREEN}┃${NC} $uptime_formatted ${GREEN}┃${NC}"
echo -e "${GREEN}┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫${NC}"

# 网络流量表格
echo -e "${GREEN}┃${NC} ${BOLD}网络流量统计${NC}                                        ${GREEN}┃${NC}"
echo -e "${GREEN}┣━━━━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━┫${NC}"
echo -e "${GREEN}┃${NC} 下载总量              ${GREEN}┃${NC} $rx_human ${GREEN}┃${NC}"
echo -e "${GREEN}┣━━━━━━━━━━━━━━━━━━━━━━━━╋━━━━━━━━━━━━━━━━━━━━━━━━━━┫${NC}"
echo -e "${GREEN}┃${NC} 上传总量              ${GREEN}┃${NC} $tx_human ${GREEN}┃${NC}"
echo -e "${GREEN}┣━━━━━━━━━━━━━━━━━━━━━━━━╋━━━━━━━━━━━━━━━━━━━━━━━━━━┫${NC}"
echo -e "${GREEN}┃${NC} 总流量                ${GREEN}┃${NC} $total_human ${GREEN}┃${NC}"
echo -e "${GREEN}┣━━━━━━━━━━━━━━━━━━━━━━━━┻━━━━━━━━━━━━━━━━━━━━━━━━━━┫${NC}"

# 内存使用表格
echo -e "${GREEN}┃${NC} ${BOLD}内存使用情况${NC}                                        ${GREEN}┃${NC}"
echo -e "${GREEN}┣━━━━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━┫${NC}"
echo -e "${GREEN}┃${NC} 内存使用              ${GREEN}┃${NC} $mem_used MB / $mem_total MB ${GREEN}┃${NC}"
echo -e "${GREEN}┣━━━━━━━━━━━━━━━━━━━━━━━━╋━━━━━━━━━━━━━━━━━━━━━━━━━━┫${NC}"
echo -e "${GREEN}┃${NC} 使用率                ${GREEN}┃${NC} $mem_percent% ${GREEN}┃${NC}"
echo -e "${GREEN}┗━━━━━━━━━━━━━━━━━━━━━━━━┻━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"

echo -e "\n数据统计时间: $(date +"%Y-%m-%d %H:%M:%S")"
