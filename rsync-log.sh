#!/bin/bash
set -e

echo "[1/7] 安装依赖"
apt update
apt install -y rsync openssl

echo "[2/7] 创建目录"
mkdir -p /data/nginx_logs/active
chown -R nobody:nogroup /data/nginx_logs
chmod 755 /data/nginx_logs

echo "[3/7] 配置 rsync daemon"
cat > /etc/rsyncd.conf << 'EOF'
uid = nobody
gid = nogroup
use chroot = no
max connections = 10
timeout = 600
pid file = /run/rsyncd.pid
log file = /var/log/rsyncd.log

# 生产环境请限制来源 IP
hosts allow = *

[active]
path = /data/nginx_logs/active
comment = 所有 nginx 日志（实时 + 轮转）
read only = no
auth users = log_sync
secrets file = /etc/rsyncd.secrets
EOF

echo "[4/7] 生成账号密码"
PASSWORD=$(openssl rand -base64 12)
echo "log_sync:$PASSWORD" > /etc/rsyncd.secrets
chmod 600 /etc/rsyncd.secrets

echo "[5/7] 创建 systemd 服务"
cat > /etc/systemd/system/rsync-log.service << 'EOF'
[Unit]
Description=Log Rsync Daemon
After=network.target

[Service]
Type=forking
ExecStart=/usr/bin/rsync --daemon --port=8873 --config=/etc/rsyncd.conf
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

echo "[6/7] 启动并设为开机自启"
systemctl daemon-reload
systemctl enable --now rsync-log.service

echo "[7/7] 完成"
echo "========================================="
echo "RSYNC 服务已启动"
echo "端口: 8873"
echo "模块: active"
echo "用户名: log_sync"
echo "密码: $PASSWORD"
echo "目录: /data/nginx_logs/active"
echo "========================================="
