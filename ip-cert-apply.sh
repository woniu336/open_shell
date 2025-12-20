#!/bin/bash

# 首次申请IP证书脚本
# 自动获取公网IP并申请SSL证书
# 使用方法：sudo ./ip-cert-apply.sh

# 固定邮箱
EMAIL="example@gmail.com"

# 动态获取公网IP
echo "正在获取公网IP地址..."
IP_ADDRESS=$(curl -s ip.sb)
if [ -z "${IP_ADDRESS}" ]; then
    echo "错误: 无法获取公网IP地址"
    echo "尝试备用方案..."
    IP_ADDRESS=$(curl -s ifconfig.me)
    if [ -z "${IP_ADDRESS}" ]; then
        IP_ADDRESS=$(curl -s icanhazip.com)
    fi
fi

if [ -z "${IP_ADDRESS}" ]; then
    echo "错误: 无法获取公网IP地址，请检查网络连接"
    exit 1
fi

echo "✓ 获取到公网IP地址: ${IP_ADDRESS}"

# 路径配置
LEGO_DIR="/root/lego"
NGINX_SSL_DIR="/etc/nginx/ssl/ip"
CERT_FILE="${LEGO_DIR}/certificates/${IP_ADDRESS}.crt"
KEY_FILE="${LEGO_DIR}/certificates/${IP_ADDRESS}.key"

echo "=== 开始申请 ${IP_ADDRESS} 的SSL证书 ==="

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

# 确保所有nginx相关进程都停止
echo "清理nginx相关进程..."
sudo pkill -9 nginx 2>/dev/null || true

# 短暂等待
sleep 2

# 检查80端口是否已释放
echo "检查80端口状态..."
if ss -tuln 2>/dev/null | grep -q ":80 "; then
    echo "警告: 端口80仍被占用，尝试强制释放..."
    sudo fuser -k 80/tcp 2>/dev/null || true
    sleep 2
    
    if ss -tuln 2>/dev/null | grep -q ":80 "; then
        echo "错误: 无法释放80端口，请手动检查"
        echo "运行: sudo ss -tulnp | grep :80"
        exit 1
    fi
fi

echo "✓ 80端口已释放，继续申请证书..."

# 申请证书
echo "正在申请证书..."
docker run --rm -it \
  -v "${LEGO_DIR}":/.lego \
  -p 80:8888 \
  goacme/lego \
  --email="${EMAIL}" \
  --accept-tos \
  --server="https://acme-v02.api.letsencrypt.org/directory" \
  --http \
  --http.port=":8888" \
  --key-type="rsa2048" \
  --domains="${IP_ADDRESS}" \
  --disable-cn \
  run --profile "shortlived"

# 检测证书是否申请成功
echo "检测证书申请结果..."
if [[ -f "${CERT_FILE}" && -f "${KEY_FILE}" ]]; then
    echo "✓ 证书申请成功！"
    echo "证书文件: ${CERT_FILE}"
    echo "私钥文件: ${KEY_FILE}"
    
    # 确保.lego目录存在
    mkdir -p /root/.lego
    cp -r "${LEGO_DIR}"/* /root/.lego/ 2>/dev/null || true
    
    # 复制证书到nginx目录
    echo "复制证书到nginx目录..."
    sudo mkdir -p "${NGINX_SSL_DIR}"
    sudo cp "${CERT_FILE}" "${NGINX_SSL_DIR}/"
    sudo cp "${KEY_FILE}" "${NGINX_SSL_DIR}/"
    
    # 保存IP地址到文件，供续期脚本使用
    echo "${IP_ADDRESS}" > "${LEGO_DIR}/current_ip.txt"
    
    echo "✓ 证书已复制到 ${NGINX_SSL_DIR}"
else
    echo "✗ 证书申请失败！"
    echo "请检查:"
    echo "  1. IP地址是否正确可访问 (当前IP: ${IP_ADDRESS})"
    echo "  2. 服务器80端口是否可从公网访问"
    echo "  3. 防火墙是否开放80端口"
    exit 1
fi

# 重新启动nginx服务
echo "重新启动nginx服务..."
sudo systemctl start nginx 2>/dev/null || echo "警告: nginx启动失败"

# 重新启动nginx-ui服务（如果之前运行的话）
if [ "$NGINX_UI_RUNNING" = true ]; then
    echo "重新启动nginx-ui服务..."
    sudo systemctl start nginx-ui 2>/dev/null || echo "警告: nginx-ui启动失败"
fi

echo "=== 证书申请完成 ==="
echo "公网IP: ${IP_ADDRESS}"
echo "证书文件: ${NGINX_SSL_DIR}/${IP_ADDRESS}.crt"
echo "私钥文件: ${NGINX_SSL_DIR}/${IP_ADDRESS}.key"
