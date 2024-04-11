#!/bin/bash

# 提示用户输入多少分钟执行一次任务
read -p "请输入执行任务的时间间隔（分钟）: " interval

# 提示用户输入命令
read -p "请输入要执行的命令: " command

# 将命令添加到计划任务中
cron_command="*/$interval * * * * $command"

# 将计划任务写入临时文件
echo "$cron_command" > /tmp/crontab_job

# 将临时文件中的计划任务加载到crontab中
crontab /tmp/crontab_job

# 清理临时文件
rm /tmp/crontab_job

echo "已成功添加计划任务：每隔 $interval 分钟执行一次命令"
