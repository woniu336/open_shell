#!/bin/bash

# 创建并切换到pandora-next目录
mkdir -p pandora-next
cd pandora-next

# 提示用户输入License Id
read -p "请输入License Id: " license_id

# 创建data目录
mkdir -p data

# 创建config.json文件
cat <<EOF > data/config.json
{
  "bind": "0.0.0.0:8181",
  "timeout": 600,
  "proxy_url": "",
  "license_id": "$license_id",
  "public_share": false,
  "site_password": "",
  "setup_password": "",
  "server_tokens": true,
  "server_mode": "web",
  "captcha": {
    "provider": "",
    "site_key": "",
    "site_secret": "",
    "site_login": false,
    "setup_login": false,
    "oai_username": false,
    "oai_password": false
  },
  "whitelist": null
}
EOF

# 创建tokens.json文件
cat <<EOF > data/tokens.json
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
    volumes:
      - ./data:/data
      - ./sessions:/root/.cache/PandoraNext
EOF

# 执行容器运行命令
docker-compose up -d

# 检查容器是否成功启动
docker-compose ps | grep "PandoraNext" > /dev/null
if [ $? -eq 0 ]; then
    echo "PandoraNext 容器已成功启动！"
else
    echo "启动失败，请检查日志以获取更多信息。"
fi
