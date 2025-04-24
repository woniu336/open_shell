#!/bin/bash

# 只检测 plausible 相关容器
declare -A containers=(
  ["plausible-ce-plausible-1"]="ghcr.io/plausible/community-edition:v3.0.1"
  ["plausible-ce-plausible_db-1"]="postgres:16-alpine"
  ["plausible-ce-plausible_events_db-1"]="clickhouse/clickhouse-server:24.12-alpine"
)

echo -e "容器名称\t\t\t内存占用\t镜像\t\t\t\t镜像大小"

total_mem_bytes=0
total_image_bytes=0

for container in "${!containers[@]}"; do
  image=$(docker inspect --format='{{.Config.Image}}' "$container")

  mem_str=$(docker stats --no-stream --format "{{.MemUsage}}" "$container" | awk '{print $1}')
  unit=$(echo $mem_str | grep -oEi '[a-zA-Z]+$')
  mem_value=$(echo $mem_str | grep -oE '^[0-9\.]+')

  case $unit in
    KiB) mem_bytes=$(echo "$mem_value * 1024" | bc) ;;
    MiB) mem_bytes=$(echo "$mem_value * 1024 * 1024" | bc) ;;
    GiB) mem_bytes=$(echo "$mem_value * 1024 * 1024 * 1024" | bc) ;;
    *) mem_bytes=0 ;;
  esac

  total_mem_bytes=$(echo "$total_mem_bytes + $mem_bytes" | bc)

  image_line=$(docker images --format "{{.Repository}}:{{.Tag}} {{.Size}}" | grep "^$image ")
  image_size=$(echo "$image_line" | awk '{print $2}')
  size_unit=$(echo "$image_size" | grep -oEi '[a-zA-Z]+$')
  size_value=$(echo "$image_size" | grep -oE '^[0-9\.]+')

  case $size_unit in
    kB) image_bytes=$(echo "$size_value * 1024" | bc) ;;
    MB) image_bytes=$(echo "$size_value * 1024 * 1024" | bc) ;;
    GB) image_bytes=$(echo "$size_value * 1024 * 1024 * 1024" | bc) ;;
    *) image_bytes=0 ;;
  esac

  total_image_bytes=$(echo "$total_image_bytes + $image_bytes" | bc)

  printf "%-30s %-10s %-35s %-10s\n" "$container" "$mem_str" "$image" "$image_size"
done

# 转换为人类可读单位
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
