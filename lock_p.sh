#!/bin/bash

# 检查参数
if [ "$1" != "lock" ] && [ "$1" != "unlock" ]; then
    echo "用法: $0 [lock|unlock]"
    exit 1
fi

# 定义基础目录
BASE_DIR="/www/wwwroot/123.cc"
# 定义要处理的子目录数组
SUBDIRS=("123" "456" "789")

# 检查是否以root权限运行
if [ "$EUID" -ne 0 ]; then 
    echo "请使用root权限运行此脚本"
    exit 1
fi

# 检查基础目录是否存在
if [ ! -d "$BASE_DIR" ]; then
    echo "错误：目录 $BASE_DIR 不存在"
    exit 1
fi

# 根据参数设置操作类型
if [ "$1" == "lock" ]; then
    OPERATION="+i"
    ACTION="锁定"
else
    OPERATION="-i"
    ACTION="解锁"
fi

# 遍历并处理每个子目录
for subdir in "${SUBDIRS[@]}"; do
    FULL_PATH="$BASE_DIR/$subdir"
    
    if [ -d "$FULL_PATH" ]; then
        echo "正在${ACTION}目录: $FULL_PATH"
        chattr $OPERATION -R "$FULL_PATH"
        if [ $? -eq 0 ]; then
            echo "成功${ACTION}目录: $FULL_PATH"
        else
            echo "${ACTION}目录失败: $FULL_PATH"
        fi
    else
        echo "警告：目录不存在: $FULL_PATH"
    fi
done

echo "操作完成！"