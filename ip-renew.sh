#!/bin/bash

# 证书续期脚本
# 定时任务执行续期，自动读取保存的IP地址

# 固定邮箱
EMAIL="example@gmail.com"

# 路径配置
LEGO_DIR="/root/lego"

# 读取保存的IP地址
IP_FILE="${LEGO_DIR}/current_ip.txt"
if [ ! -f "${IP_FILE}" ]; then
    echo "错误: 未找到保存的IP地址文件"
    echo "尝试动态获取公网IP..."
    IP_ADDRESS=$(curl -s ip.sb)
    if [ -z "${IP_ADDRESS}" ]; then
        echo "错误: 无法获取公网IP地址"
        exit 1
    fi
    echo "获取到公网IP: ${IP_ADDRESS}"
else
    IP_ADDRESS=$(cat "${IP_FILE}")
    echo "读取保存的IP地址: ${IP_ADDRESS}"
fi

# 验证IP地址格式
if [[ ! "${IP_ADDRESS}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "错误: IP地址格式不正确: ${IP_ADDRESS}"
    echo "尝试重新获取公网IP..."
    IP_ADDRESS=$(curl -s ip.sb)
    if [[ ! "${IP_ADDRESS}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "错误: 无法获取有效的公网IP地址"
        exit 1
    fi
    echo "重新获取到公网IP: ${IP_ADDRESS}"
fi

NGINX_SSL_DIR="/etc/nginx/ssl/ip"
CERT_FILE="${LEGO_DIR}/certificates/${IP_ADDRESS}.crt"
KEY_FILE="${LEGO_DIR}/certificates/${IP_ADDRESS}.key"

echo "=== 开始检查 ${IP_ADDRESS} 证书续期 ==="
date

# 检查证书文件是否存在
if [[ ! -f "${CERT_FILE}" || ! -f "${KEY_FILE}" ]]; then
    echo "错误: 未找到证书文件，尝试重新申请..."
    /root/ip-cert-apply.sh
    exit $?
fi

# 检查并停止nginx-ui服务
NGINX_UI_RUNNING=false
echo "检查nginx-ui服务状态..."
if systemctl list-units --type=service --all | grep -q nginx-ui; then
    echo "发现nginx-ui服务，正在停止..."
    sudo systemctl stop nginx-ui 2>/dev/null && NGINX_UI_RUNNING=true
    echo "nginx-ui服务已停止"
elif ps aux | grep -q "[n]ginx-ui"; then
    echo "发现nginx-ui进程，正在停止..."
    sudo pkill -f nginx-ui 2>/dev/null && NGINX_UI_RUNNING=true
    echo "nginx-ui进程已停止"
fi

# 停止nginx服务
echo "停止nginx服务..."
sudo systemctl stop nginx 2>/dev/null || true

# 清理nginx相关进程
echo "清理nginx相关进程..."
sudo pkill -9 nginx 2>/dev/null || true
sleep 2

# 检查80端口
echo "检查80端口状态..."
if ss -tuln 2>/dev/null | grep -q ":80 "; then
    echo "释放80端口..."
    sudo fuser -k 80/tcp 2>/dev/null || true
    sleep 2
fi

# 续期证书（设置为提前30天续期）
echo "执行证书续期..."
docker run --rm \
  -v "${LEGO_DIR}":/.lego \
  -p 80:8888 \
  goacme/lego \
  --email="${EMAIL}" \
  --path="/.lego" \
  --server="https://acme-v02.api.letsencrypt.org/directory" \
  --http --http.port=":8888" \
  --domains="${IP_ADDRESS}" \
  renew --profile "shortlived" --days 2 --reuse-key

# 检测续期是否成功
if [[ -f "${CERT_FILE}" && -f "${KEY_FILE}" ]]; then
    echo "✓ 证书续期成功！"
    
    # 复制证书到nginx目录
    echo "更新nginx证书文件..."
    sudo mkdir -p "${NGINX_SSL_DIR}"
    sudo cp -f "${CERT_FILE}" "${NGINX_SSL_DIR}/"
    sudo cp -f "${KEY_FILE}" "${NGINX_SSL_DIR}/"
    
    echo "✓ 证书文件已更新"
else
    echo "✗ 证书续期失败！"
    echo "尝试重新申请证书..."
    /root/ip-cert-apply.sh
    exit $?
fi

# 重新启动nginx服务
echo "重新启动nginx服务..."
sudo systemctl start nginx 2>/dev/null || echo "警告: nginx启动失败"

# 重新启动nginx-ui服务（如果之前运行的话）
if [ "$NGINX_UI_RUNNING" = true ]; then
    echo "重新启动nginx-ui服务..."
    sudo systemctl start nginx-ui 2>/dev/null || echo "警告: nginx-ui启动失败"
fi

echo "=== 证书续期完成 ==="
echo "续期时间: $(date)"
echo "IP地址: ${IP_ADDRESS}"
