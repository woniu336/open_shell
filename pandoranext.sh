#!/bin/bash

# 创建并切换到pandora-next目录
mkdir -p pandora-next
cd pandora-next

# 提示用户输入license.jwt的下载地址
read -p "请输入license.jwt的下载地址: " license_url

# 下载license.jwt文件
curl -fLO "$license_url"

# 获取license.jwt的值
license_jwt=$(cat license.jwt)

# 创建docker-compose.yml文件
cat <<EOF > docker-compose.yml
version: '3'
services:
  pandora-next:
    image: pengzhile/pandora-next
    container_name: PandoraNext
    network_mode: bridge
    restart: always
    ports:
      - "8181:8181"
    environment:
      - PANDORA_NEXT_LICENSE=$license_jwt
    volumes:
      - ./data:/data
EOF

# 切换到data目录
mkdir -p data
cd data

# 创建config.json文件
cat <<EOF > config.json
{
  "bind": "0.0.0.0:8181",
  "timeout": 600,
  "proxy_url": "",
  "public_share": false,
  "site_password": "",
  "whitelist": null
}
EOF

# 创建tokens.json文件
cat <<EOF > tokens.json
{
  "test-1": {
    "token": "access token / session token / refresh token / share token",
    "shared": true,
    "show_user_info": false
  },
  "test-2": {
    "token": "access token / session token / refresh token / share token",
    "shared": true,
    "show_user_info": true,
    "plus": true
  },
  "test2": {
    "token": "access token / session token / refresh token / share token",
    "password": "12345"
  }
}
EOF

# 回到pandora-next目录
cd ..

# 执行容器运行命令
docker-compose up -d

# 检查容器是否成功启动
docker-compose ps
