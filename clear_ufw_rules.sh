#!/bin/bash

# 获取所有DENY规则的编号
rules=$(sudo ufw status numbered | grep "\[.*\].*DENY IN" | cut -d"[" -f2 | cut -d"]" -f1 | sort -rn)

# 逐个删除规则
for rule in $rules
do
    sudo ufw --force delete $rule
    echo "已删除规则 $rule"
done

echo "所有DENY规则已清除"

# 重新加载UFW
sudo ufw reload
