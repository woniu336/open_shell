#!/bin/sh

SITE=$1
if [ -z "$SITE" ]; then
  echo "请输入查询域名！正确打开方式：sh getOCSP.sh example.com"
  exit 1
fi

# Certbot 证书目录
CERTBOT_DIR="/etc/letsencrypt/live/$SITE"
CERT_FILE="$CERTBOT_DIR/cert.pem"
CHAIN_FILE="$CERTBOT_DIR/chain.pem"

# 检查文件是否存在
if [ ! -f "$CERT_FILE" ] || [ ! -f "$CHAIN_FILE" ]; then
  echo "错误：找不到 $SITE 的证书或链文件，请确认 Certbot 证书是否存在。"
  exit 1
fi

# 提取 OCSP URI
OCSP_URI=$(openssl x509 -noout -ocsp_uri -in "$CERT_FILE")
if [ -z "$OCSP_URI" ]; then
  echo "错误：未能从证书中提取 OCSP URI。"
  exit 1
fi

# 输出目录
OUTDIR="/etc/letsencrypt/ocsp/${SITE}"
mkdir -p "$OUTDIR/log"

# 日志文件
LOGFILE="$OUTDIR/log/get-ocsp_$(date +\%Y\%m\%d).log"
echo "$(date +"%Y-%m-%d %H:%M:%S") ----- 域名: $SITE 开始请求 OCSP 响应 -----" >> "$LOGFILE"

# 请求 OCSP 响应
openssl ocsp -no_nonce \
  -respout "$OUTDIR/$SITE.ocsp.resp.new" \
  -issuer "$CHAIN_FILE" \
  -verify_other "$CHAIN_FILE" \
  -cert "$CERT_FILE" \
  -url "$OCSP_URI" > "$OUTDIR/$SITE.ocsp-reply.txt" 2>&1

# 判断结果
if grep -q ": good" "$OUTDIR/$SITE.ocsp-reply.txt"; then
  if cmp -s "$OUTDIR/$SITE.ocsp.resp.new" "$OUTDIR/$SITE.ocsp.resp"; then
    rm "$OUTDIR/$SITE.ocsp.resp.new"
  else
    mv "$OUTDIR/$SITE.ocsp.resp.new" "$OUTDIR/$SITE.ocsp.resp"
    systemctl force-reload nginx.service > /dev/null
  fi
else
  echo "OCSP error for $SITE" | tee -a "$LOGFILE"
fi

# 输出和归档
cat "$OUTDIR/$SITE.ocsp-reply.txt" | tee -a "$LOGFILE"
mv "$OUTDIR/$SITE.ocsp-reply.txt" "$OUTDIR/$SITE.ocsp-reply-old.txt"

echo "$(date +"%Y-%m-%d %H:%M:%S") ------------ OCSP 响应请求完毕 ------------" >> "$LOGFILE"
