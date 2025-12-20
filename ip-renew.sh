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
    echo "证书文件路径: ${CERT_FILE}"
    echo "私钥文件路径: ${KEY_FILE}"
    
    # 调用首次申请脚本
    /root/ip-cert-apply.sh
    exit $?
fi

# 停止nginx服务
echo "停止nginx服务..."
sudo systemctl stop nginx 2>/dev/null || true
echo "继续执行证书续期..."

# 续期证书
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
    echo "检查证书文件..."
    
    # 尝试重新申请
    echo "尝试重新申请证书..."
    /root/ip-cert-apply.sh
    exit $?
fi

# 启动nginx服务
echo "启动nginx服务..."
sudo systemctl start nginx 2>/dev/null || echo "提示: nginx服务启动失败或未安装"

echo "=== 证书续期完成 ==="
echo "续期时间: $(date)"
echo "IP地址: ${IP_ADDRESS}"
