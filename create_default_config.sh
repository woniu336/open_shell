#!/bin/bash

# 定义基础路径
BASE_PATH="/home/wwwroot/lnmp01"
ETC_PATH="${BASE_PATH}/etc"
DEFAULT_PATH="${ETC_PATH}/default"

# 创建 default 目录
mkdir -p ${DEFAULT_PATH}

# 生成SSL证书和密钥
echo "生成SSL证书和密钥"
if command -v dnf &>/dev/null || command -v yum &>/dev/null; then
    openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -keyout ${DEFAULT_PATH}/default_server.key -out ${DEFAULT_PATH}/default_server.crt -days 5475 -subj "/C=US/ST=State/L=City/O=Organization/OU=Organizational Unit/CN=Common Name"
else
    openssl genpkey -algorithm Ed25519 -out ${DEFAULT_PATH}/default_server.key
    openssl req -x509 -key ${DEFAULT_PATH}/default_server.key -out ${DEFAULT_PATH}/default_server.crt -days 5475 -subj "/C=US/ST=State/L=City/O=Organization/OU=Organizational Unit/CN=Common Name"
fi

# 创建 Nginx 配置文件
cat > ${BASE_PATH}/vhost/default.conf << 'EOL'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;
    
    server_name _;

    # SSL 证书配置
    ssl_certificate /home/wwwroot/lnmp01/etc/default/default_server.crt;
    ssl_certificate_key /home/wwwroot/lnmp01/etc/default/default_server.key;

    # 返回 444 状态码以丢弃无效请求
    return 444;
}
EOL

# 设置适当的权限
chmod 644 ${DEFAULT_PATH}/default_server.crt
chmod 600 ${DEFAULT_PATH}/default_server.key
chmod 644 ${BASE_PATH}/vhost/default.conf

# 重新加载 Nginx 配置
amh nginx reload

echo "配置完成！"