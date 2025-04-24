#!/bin/bash

# 定义容器与其用途
declare -A containers=(
  ["hosting-plausible-1"]="plausible/analytics"
  ["hosting-plausible_events_db-1"]="clickhouse/clickhouse-server"
  ["hosting-plausible_db-1"]="postgres"
)

echo -e "容器名称\t\t\t内存占用\t镜像\t\t\t\t镜像大小"

total_mem_bytes=0
total_image_bytes=0

for container in "${!containers[@]}"; do
  # 获取镜像名（带tag）
  image=$(docker inspect --format='{{.Config.Image}}' "$container")

  # 获取内存使用（单位可能为 KiB, MiB, GiB）
  mem_str=$(docker stats --no-stream --format "{{.MemUsage}}" "$container" | awk '{print $1}')
  unit=$(echo $mem_str | grep -oEi '[a-zA-Z]+$')
  mem_value=$(echo $mem_str | grep -oE '^[0-9\.]+')

  # 转换为字节
  case $unit in
    KiB) mem_bytes=$(echo "$mem_value * 1024" | bc) ;;
    MiB) mem_bytes=$(echo "$mem_value * 1024 * 1024" | bc) ;;
    GiB) mem_bytes=$(echo "$mem_value * 1024 * 1024 * 1024" | bc) ;;
    *) mem_bytes=0 ;;
  esac

  total_mem_bytes=$(echo "$total_mem_bytes + $mem_bytes" | bc)

  # 获取镜像大小（从 docker images 中查找）
  image_line=$(docker images --format "{{.Repository}}:{{.Tag}} {{.Size}}" | grep "^$image ")
  image_size=$(echo "$image_line" | awk '{print $2}')
  size_unit=$(echo "$image_line" | awk '{print $2}' | grep -oEi '[a-zA-Z]+$')
  size_value=$(echo "$image_line" | awk '{print $2}' | grep -oE '^[0-9\.]+')

  # 转换为字节
  case $size_unit in
    kB) image_bytes=$(echo "$size_value * 1024" | bc) ;;
    MB) image_bytes=$(echo "$size_value * 1024 * 1024" | bc) ;;
    GB) image_bytes=$(echo "$size_value * 1024 * 1024 * 1024" | bc) ;;
    *) image_bytes=0 ;;
  esac

  total_image_bytes=$(echo "$total_image_bytes + $image_bytes" | bc)

  printf "%-30s %-10s %-35s %-10s\n" "$container" "$mem_str" "$image" "$image_size"
done

# 转换总和为人类可读格式
to_human() {
  local bytes=$1
  if (( $(echo "$bytes > 1073741824" | bc -l) )); then
    echo "$(echo "scale=2; $bytes / 1073741824" | bc) GiB"
  elif (( $(echo "$bytes > 1048576" | bc -l) )); then
    echo "$(echo "scale=2; $bytes / 1048576" | bc) MiB"
  elif (( $(echo "$bytes > 1024" | bc -l) )); then
    echo "$(echo "scale=2; $bytes / 1024" | bc) KiB"
  else
    echo "${bytes} B"
  fi
}

echo
echo "🔢 总内存占用：$(to_human $total_mem_bytes)"
echo "📦 总镜像大小：$(to_human $total_image_bytes)"
