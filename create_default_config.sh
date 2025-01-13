#!/bin/bash

# 定义基础路径
BASE_PATH="/home/wwwroot/lnmp01"
ETC_PATH="${BASE_PATH}/etc"
DEFAULT_PATH="${ETC_PATH}/default"

# 创建 default 目录
mkdir -p ${DEFAULT_PATH}

# 创建证书文件
cat > ${DEFAULT_PATH}/default_server.crt << 'EOL'
-----BEGIN CERTIFICATE-----
MIICAzCCAbWgAwIBAgIUDhjQ3XYSqVpmqUmuV2X7Sn60UewwBQYDK2VwMHcxCzAJ
BgNVBAYTAlVTMQ4wDAYDVQQIDAVTdGF0ZTENMAsGA1UEBwwEQ2l0eTEVMBMGA1UE
CgwMT3JnYW5pemF0aW9uMRwwGgYDVQQLDBNPcmdhbml6YXRpb25hbCBVbml0MRQw
EgYDVQQDDAtDb21tb24gTmFtZTAeFw0yNTAxMTMwNDI1MTlaFw00MDAxMTAwNDI1
MTlaMHcxCzAJBgNVBAYTAlVTMQ4wDAYDVQQIDAVTdGF0ZTENMAsGA1UEBwwEQ2l0
eTEVMBMGA1UECgwMT3JnYW5pemF0aW9uMRwwGgYDVQQLDBNPcmdhbml6YXRpb25h
bCBVbml0MRQwEgYDVQQDDAtDb21tb24gTmFtZTAqMAUGAytlcAMhAOmdW1i85B8n
XprLBQvUG43bQ4tFvsUN0Sh/Ly0y7WZ9o1MwUTAdBgNVHQ4EFgQUwG+/cU9Uro0c
44/8MGFdfmquVkEwHwYDVR0jBBgwFoAUwG+/cU9Uro0c44/8MGFdfmquVkEwDwYD
VR0TAQH/BAUwAwEB/zAFBgMrZXADQQDKHzg0o5Btu6kt+vsruG0mzrTomE6b/nrE
uwhyuwLroHpmTmuMwvWMxegB0mRNXQvfY3RUJxhbCRItD2FFv4EE
-----END CERTIFICATE-----
EOL

# 创建密钥文件
cat > ${DEFAULT_PATH}/default_server.key << 'EOL'
-----BEGIN PRIVATE KEY-----
MC4CAQAwBQYDK2VwBCIEIMV1Ce5chKgatmFNptfVYgtC7w3FoTFH25mF1HDLhQbV
-----END PRIVATE KEY-----
EOL

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