#!/bin/bash

# 设置 Redis 信息
REDIS_HOST="127.0.0.1"
REDIS_PORT=6379

# 默认配置
THRESHOLD=$((1024 * 1024))  # 默认 1MB
DRY_RUN=false
TOP_N=0  # 不启用 top-n 模式

# 参数解析
while [[ "$1" != "" ]]; do
  case $1 in
    --dry-run ) DRY_RUN=true ;;
    --threshold ) shift; THRESHOLD=$1 ;;
    --top-n ) shift; TOP_N=$1 ;;
    * ) echo "用法: $0 [--dry-run] [--threshold BYTES] [--top-n N]"; exit 1 ;;
  esac
  shift
done

# 如果是 top-n 模式
if [ "$TOP_N" -gt 0 ]; then
  echo "📊 显示 Redis 中占用内存最多的前 $TOP_N 个 key..."

  # 临时文件保存 key 和内存大小
  TMP_FILE=$(mktemp)

  redis-cli -h $REDIS_HOST -p $REDIS_PORT --scan | while read key; do
    size=$(redis-cli -h $REDIS_HOST -p $REDIS_PORT memory usage "$key" 2>/dev/null)
    if [[ "$size" =~ ^[0-9]+$ ]]; then
      echo -e "$size\t$key" >> "$TMP_FILE"
    fi
  done

  echo -e "🧠 Top $TOP_N keys by memory usage:"
  sort -nr "$TMP_FILE" | head -n "$TOP_N" | awk -F '\t' '{printf " - %s bytes\t%s\n", $1, $2}'
  rm "$TMP_FILE"
  exit 0
fi

# 否则执行常规清理逻辑
echo "🔍 扫描 Redis，查找大于 $THRESHOLD 字节的 key..."
$DRY_RUN && echo "⚠️ 当前为 dry-run 模式，不会删除任何 key"

redis-cli -h $REDIS_HOST -p $REDIS_PORT --scan | while read key; do
  size=$(redis-cli -h $REDIS_HOST -p $REDIS_PORT memory usage "$key" 2>/dev/null)

  if [[ "$size" =~ ^[0-9]+$ ]] && [[ $size -gt $THRESHOLD ]]; then
    echo "➡️ 将删除 key: $key （$size 字节）"

    if [ "$DRY_RUN" = false ]; then
      redis-cli -h $REDIS_HOST -p $REDIS_PORT del "$key" > /dev/null
    fi
  fi
done

echo "✅ 扫描完成！"
$DRY_RUN && echo "🔒 未删除任何 key（dry-run 模式）"
