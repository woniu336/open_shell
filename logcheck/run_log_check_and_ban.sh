#!/bin/bash

# 记录脚本开始运行的时间
echo "Script started at $(date)" >> /root/logcheck/cron_run.log

# 设置工作目录
cd /root/logcheck

# 运行 logcheck.py
/usr/bin/python3 logcheck.py

# 运行 web_log_monitor.py
/usr/bin/python3 web_log_monitor.py

# 运行 ban_severe_risk_ips.py
/usr/bin/python3 ban_severe_risk_ips.py

# 记录运行完成的时间
echo "Scripts completed at $(date)" >> /root/logcheck/cron_run.log