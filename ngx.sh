#!/usr/bin/env bash
set -e

# ===== 基本配置 =====
APP_NAME="nginx-mgr"
VERSION="1.3.3"
WORKDIR="/opt/nginx-mgr"
BIN_PATH="/usr/local/bin/nginx-mgr"
SERVICE_FILE="/etc/systemd/system/nginx-mgr.service"
DOWNLOAD_URL="https://github.com/woniu336/ngx-nova/releases/download/${VERSION}/nginx-mgr-linux-amd64.tar.gz"

echo "==> Installing ${APP_NAME} v${VERSION}"

# ===== 前置检查 =====
if [ "$(id -u)" != "0" ]; then
  echo "❌ 请使用 root 用户运行该脚本"
  exit 1
fi

for cmd in wget tar systemctl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "❌ 缺少依赖命令: $cmd"
    exit 1
  fi
done

# ===== 创建工作目录 =====
echo "==> Creating work directory: ${WORKDIR}"
mkdir -p "${WORKDIR}"
cd "${WORKDIR}"

# ===== 下载 =====
echo "==> Downloading package"
rm -f nginx-mgr-linux-amd64.tar.gz
wget -q --show-progress "${DOWNLOAD_URL}"

# ===== 解压 =====
echo "==> Extracting package"
tar -xzf nginx-mgr-linux-amd64.tar.gz

# ===== 清理压缩包 =====
rm -f nginx-mgr-linux-amd64.tar.gz
echo "==> Cleaned up package"

# ===== 安装二进制 =====
echo "==> Installing binary to ${BIN_PATH}"
mv -f nginx-mgr "${BIN_PATH}"
chmod +x "${BIN_PATH}"

# ===== 安装 tokenctl 到 /usr/local/bin =====
if [ -f "./tokenctl" ]; then
    echo "==> Installing tokenctl to /usr/local/bin/"
    mv -f tokenctl /usr/local/bin/
    chmod +x /usr/local/bin/tokenctl
    echo "✅ tokenctl installed"
fi

# ===== 创建 systemd 服务 =====
echo "==> Creating systemd service"

cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=nginx-mgr API/UI
After=network.target
Wants=network.target

[Service]
Type=simple
WorkingDirectory=${WORKDIR}
ExecStart=${BIN_PATH}
Restart=on-failure
RestartSec=5s
User=root
LimitNOFILE=1048576
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# ===== 启动服务 =====
echo "==> Reloading systemd"
systemctl daemon-reload

echo "==> Enabling and starting service"
systemctl enable --now nginx-mgr

# ===== 完成 =====
echo
echo "✅ nginx-mgr 安装完成"
echo "📍 服务状态："
systemctl --no-pager status nginx-mgr
echo
echo "🌐 访问地址: http://IP:8083/ui/"
echo
