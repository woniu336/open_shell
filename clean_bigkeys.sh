#!/bin/bash

REDIS_HOST="127.0.0.1"
REDIS_PORT=6379

THRESHOLD=$((1024 * 1024))  # 默认 1MB
DRY_RUN=false
TOP_N=0
EXPIRE_SECONDS=0  # 默认为立即删除

# 参数解析
while [[ "$1" != "" ]]; do
  case $1 in
    --dry-run ) DRY_RUN=true ;;
    --threshold ) shift; THRESHOLD=$1 ;;
    --top-n ) shift; TOP_N=$1 ;;
    --expire ) shift; EXPIRE_SECONDS=$1 ;;
    * ) echo "用法: $0 [--dry-run] [--threshold BYTES] [--expire SECONDS] [--top-n N]"; exit 1 ;;
  esac
  shift
done

# top-n 模式
if [ "$TOP_N" -gt 0 ]; then
  echo "📊 显示 Redis 中占用内存最多的前 $TOP_N 个 key..."
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

echo "🔍 扫描 Redis，查找大于 $THRESHOLD 字节的 key..."
$DRY_RUN && echo "⚠️ 当前为 dry-run 模式，不会删除或设置过期"

# 正常扫描处理
redis-cli -h $REDIS_HOST -p $REDIS_PORT --scan | while read key; do
  size=$(redis-cli -h $REDIS_HOST -p $REDIS_PORT memory usage "$key" 2>/dev/null)

  if [[ "$size" =~ ^[0-9]+$ ]] && [[ $size -gt $THRESHOLD ]]; then
    echo "➡️ 匹配到大 key: $key （$size 字节）"

    if [ "$DRY_RUN" = false ]; then
      if [ "$EXPIRE_SECONDS" -gt 0 ]; then
        echo "⏳ 设置 $key 在 $EXPIRE_SECONDS 秒后过期"
        redis-cli -h $REDIS_HOST -p $REDIS_PORT expire "$key" $EXPIRE_SECONDS > /dev/null
      else
        echo "🗑️ 立即删除 $key"
        redis-cli -h $REDIS_HOST -p $REDIS_PORT del "$key" > /dev/null
      fi
    fi
  fi
done

echo "✅ 扫描完成！"
$DRY_RUN && echo "🔒 未做任何修改（dry-run 模式）"
