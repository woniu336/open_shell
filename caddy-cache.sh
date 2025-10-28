# 下载压缩包
cd /tmp
wget https://github.com/jimugou/jimugou.github.io/releases/download/v1.0.0/caddy-custom-with-cache.tar.gz

# 解压
tar -xzf caddy-custom-with-cache.tar.gz

# 停止旧服务
sudo systemctl stop caddy 2>/dev/null || true

# 备份原版（可选但推荐）
sudo cp /usr/bin/caddy /usr/bin/caddy.backup 2>/dev/null || true

# 替换二进制文件
sudo mv /tmp/caddy-custom /usr/bin/caddy
sudo chmod +x /usr/bin/caddy
sudo chown root:root /usr/bin/caddy

# 验证
caddy version
caddy list-modules | grep cache

# 启动服务
sudo systemctl start caddy
sudo systemctl status caddy