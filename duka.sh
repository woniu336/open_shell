#!/bin/bash

# 定义颜色代码，用于美化输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # 无颜色

# 打印彩色消息的函数
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# 获取本机 IP 地址的函数
get_ip() {
    hostname -I | awk '{print $1}'
}

# 默认域名和店铺名
domain=$(get_ip)
app_name="dujiaoshuka"

# 创建必要的目录
mkdir -p dujiao/{storage,uploads,data,redis}
chmod 777 dujiao/{storage,uploads,data,redis}

# 切换到 dujiao 目录
cd dujiao || exit

# 生成密码和密钥
mysql_pwd=$(echo "${domain}mysql" | md5sum | awk '{print $1}')
app_key=$(echo "${domain}app" | md5sum | awk '{print $1}')

print_message "$GREEN" "MySQL 密码: $mysql_pwd"
print_message "$GREEN" "应用密钥: $app_key"

# 创建 docker-compose.yaml 文件
cat <<EOF >docker-compose.yaml
version: "3"
services:
  faka:
    image: ghcr.io/apocalypsor/dujiaoka:latest
    container_name: faka
    environment:
        - INSTALL=true
    volumes:
      - ./env.conf:/dujiaoka/.env:rw
      - ./uploads:/dujiaoka/public/uploads:rw
      - ./storage:/dujiaoka/storage:rw
    ports:
      - 3080:80
    restart: always
 
  db:
    image: mariadb:focal
    container_name: faka-data
    restart: always
    environment:
      - MYSQL_ROOT_PASSWORD=${mysql_pwd}
      - MYSQL_DATABASE=dujiaoka
      - MYSQL_USER=dujiaoka
      - MYSQL_PASSWORD=${mysql_pwd}
    volumes:
      - ./data:/var/lib/mysql:rw

  redis:
    image: redis:alpine
    container_name: faka-redis
    restart: always
    volumes:
      - ./redis:/data:rw
EOF

# 默认不启用 HTTPS
app_url="http://${domain}"

print_message "$YELLOW" "应用 URL 是 ${app_url}:3080"

# 创建 env.conf 文件
cat <<EOF > env.conf
APP_NAME=${app_name}
APP_ENV=local
APP_KEY=${app_key}
APP_DEBUG=false
APP_URL=${app_url}:3080
ADMIN_HTTPS=false

LOG_CHANNEL=stack

# 数据库配置
DB_CONNECTION=mysql
DB_HOST=db
DB_PORT=3306
DB_DATABASE=dujiaoka
DB_USERNAME=dujiaoka
DB_PASSWORD=${mysql_pwd}

# Redis 配置
REDIS_HOST=redis
REDIS_PASSWORD=
REDIS_PORT=6379

BROADCAST_DRIVER=log
SESSION_DRIVER=file
SESSION_LIFETIME=120

# 缓存配置
CACHE_DRIVER=file

# 异步消息队列
QUEUE_CONNECTION=redis

# 管理后台语言
## zh_CN 简体中文
## zh_TW 繁体中文
## en    英文
DUJIAO_ADMIN_LANGUAGE=zh_CN

# 管理后台登录路径
ADMIN_ROUTE_PREFIX=/admin
EOF

chmod 777 env.conf

# 启动容器
print_message "$GREEN" "正在启动容器..."
docker-compose up -d 

# 打印最终信息
cat << EOF

$(print_message "$GREEN" "安装成功完成！")

$(print_message "$YELLOW" "访问您的网站：${app_url}:3080")

============== 部署完成 ==============

重要信息（请保存）：
- 数据库地址: db
- 数据库用户: dujiaoka
- 数据库密码: ${mysql_pwd}
- Redis地址: redis

注意：
1. 请及时修改后台管理员密码
2. 建议定期更换数据库密码
3. 请妥善保管以上信息，切勿泄露

祝您使用愉快！
======================================

EOF
