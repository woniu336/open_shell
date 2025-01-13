#!/bin/bash

# 定义基础路径
BASE_PATH="/home/wwwroot/lnmp01"

# 创建 Nginx 配置文件
cat > ${BASE_PATH}/vhost/default.conf << 'EOL'
server {
    listen 80 default_server;
    listen [::]:80 default_server;   
    server_name _;
    return 444;
}


server {
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;    
    server_name _;
    
    ssl_reject_handshake on;
}
EOL

# 设置适当的权限
chmod 644 ${BASE_PATH}/vhost/default.conf

# 重新加载 Nginx 配置
amh nginx reload

echo "配置完成！" 