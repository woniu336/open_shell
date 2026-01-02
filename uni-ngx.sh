#!/usr/bin/env bash
set -e

APP_NAME="nginx-mgr"
WORKDIR="/opt/nginx-mgr"
BIN_PATH="/usr/local/bin/nginx-mgr"
TOKENCTL_PATH="/usr/local/bin/tokenctl"
SERVICE_FILE="/etc/systemd/system/nginx-mgr.service"

echo "==> Uninstalling ${APP_NAME}"

# ===== 权限检查 =====
if [ "$(id -u)" != "0" ]; then
  echo "❌ 请使用 root 用户运行该脚本"
  exit 1
fi

# ===== 停止服务 =====
if systemctl list-units --full -all | grep -q "${APP_NAME}.service"; then
  echo "==> Stopping service"
  systemctl stop ${APP_NAME}
fi

# ===== 禁用自启 =====
if systemctl list-unit-files | grep -q "${APP_NAME}.service"; then
  echo "==> Disabling service"
  systemctl disable ${APP_NAME}
fi

# ===== 删除 systemd 服务文件 =====
if [ -f "${SERVICE_FILE}" ]; then
  echo "==> Removing systemd service file"
  rm -f "${SERVICE_FILE}"
  systemctl daemon-reload
fi

# ===== 删除主程序 =====
if [ -f "${BIN_PATH}" ]; then
  echo "==> Removing binary: ${BIN_PATH}"
  rm -f "${BIN_PATH}"
fi

# ===== 删除 tokenctl =====
if [ -f "${TOKENCTL_PATH}" ]; then
  echo "==> Removing tokenctl: ${TOKENCTL_PATH}"
  rm -f "${TOKENCTL_PATH}"
fi

# ===== 删除工作目录（包含 auth_token.json）=====
if [ -d "${WORKDIR}" ]; then
  echo "==> Removing work directory: ${WORKDIR}"
  rm -rf "${WORKDIR}"
fi

echo
echo "✅ nginx-mgr 已完全卸载"
echo "🧹 已清理内容："
echo "  - systemd 服务"
echo "  - /usr/local/bin/nginx-mgr"
echo "  - /usr/local/bin/tokenctl"
echo "  - /opt/nginx-mgr（含 auth_token.json）"
echo
