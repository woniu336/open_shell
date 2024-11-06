#!/bin/bash

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 [test]"
    exit 1
fi

SERVERCHAN_KEY=""  # 替换为你的 Server酱 SCKEY
TEST_MODE=$1
API_URL="https://ca.ovh.com/engine/apiv6/dedicated/server/datacenter/availabilities/?excludeDatacenters=false&planCode=24ska01&server=24ska01"

send_serverchan_notification() {
    local datacenter=$1
    local availability=$2
    local title="OVHKS-A可用性更新"
    local desp="数据中心: ${datacenter}\n可用性状态: ${availability}"
    
    echo "发送通知: $desp"

    # 使用 POST 方法发送通知
    curl -s -X POST "https://sctapi.ftqq.com/${SERVERCHAN_KEY}.send" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        --data-urlencode "title=$title" \
        --data-urlencode "desp=$desp"

    echo "通知已发送"
}

check_availability() {
    echo "获取服务器可用性数据..."

    response=$(curl -s "$API_URL")

    if [ -z "$response" ]; then
        echo "获取数据失败"
        return
    fi  # 这里修正了语法错误，删除了多余的大括号

    echo "收到 JSON 响应: $response"

    if [ "$TEST_MODE" == "test" ]; then
        echo "测试模式启用，强制 bhs 数据中心可用性为 72H"
        response=$(echo "$response" | jq '.[0].datacenters |= map(if .datacenter == "bhs" then .availability = "72H" else . end)')
    fi

    echo "$response" | jq -c '.[0].datacenters[]' | while read -r datacenter; do
        availability=$(echo "$datacenter" | jq -r '.availability')
        name=$(echo "$datacenter" | jq -r '.datacenter')

        echo "检查数据中心: $name, 可用性: $availability"

        if [ "$availability" != "unavailable" ]; then
            echo "检测到可用性变化: $availability in datacenter: $name"
            send_serverchan_notification "$name" "$availability"
            break
        fi
    done

    echo "完成所有数据中心检查"
}

while true; do
    check_availability
    sleep 15
done