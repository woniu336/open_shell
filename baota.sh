#!/bin/bash


# 安装宝塔面板 7.7
curl -sSO https://raw.githubusercontent.com/woniu336/btpanel-v7.7.0/main/install/install_panel.sh && bash install_panel.sh

# 一键破解
curl -sSO https://raw.githubusercontent.com/woniu336/open_shell/main/one_key_happy.sh && bash one_key_happy.sh

# 美化主题
wget -O btpanel_theme.zip https://raw.githubusercontent.com/woniu336/open_shell/main/bt/BTPanel_theme_linux_770.zip && unzip -o btpanel_theme.zip -d /www/server/ && /etc/init.d/bt restart

# 去除网站默认文件
sed -i "/htaccess = self.sitePath+'\/.htaccess'/, /public.ExecShell('chown -R www:www ' + htaccess)/d" /www/server/panel/class/panelSite.py
sed -i "/index = self.sitePath+'\/index.html'/, /public.ExecShell('chown -R www:www ' + index)/d" /www/server/panel/class/panelSite.py
sed -i "/doc404 = self.sitePath+'\/404.html'/, /public.ExecShell('chown -R www:www ' + doc404)/d"/www/server/panel/class/panelSite.py

# 关闭未绑定域名提示
sed -i "s/root \/www\/server\/nginx\/html/return 400/" /www/server/panel/class/panelSite.py
sed -i "s/root \/www\/server\/nginx\/html/return 400/" /www/server/panel/vhost/nginx/0.default.conf

# 关闭安全入口提示
sed -i "s/return render_template('autherr.html')/return abort(404)/" /www/server/panel/BTPanel/__init__.py

# 去除消息推送
sed -i "/p = threading.Thread(target=check_panel_msg)/, /p.start()/d" /www/server/panel/task.py
sed -i '/\"check_panel_msg\":/d' /www/server/panel/task.py

# 去除文件校验
sed -i "/p = threading.Thread(target=check_files_panel)/, /p.start()/d" /www/server/panel/task.py
sed -i '/\"check_files_panel\":/d' /www/server/panel/task.py
rm -f /www/server/panel/script/check_files.py

# 去除云端验证
sed -i "/p = threading.Thread(target=update_software_list)/, /p.start()/d" /www/server/panel/task.py
sed -i '/\"update_software_list\":/d' /www/server/panel/task.py
sed -i '/self.get_cloud_list_status/d' /www/server/panel/class/panelPlugin.py
sed -i '/PluginLoader.daemon_task()/d' /www/server/panel/task.py

# 关闭活动推荐与在线客服
echo "True" > /www/server/panel/data/not_recommend.pl
echo "True" > /www/server/panel/data/not_workorder.pl

# 关闭首页软件推荐与广告
sed -i '/def get_pay_type(self,get):/a \ \ \ \ \ \ \ \ return [];' /www/server/panel/class/ajax.py

# 关闭拉黑检测与提示
sed -i '/self._check_url/d' /www/server/panel/class/panelPlugin.py

# 关闭面板日志与绑定域名上报
sed -i "/^logs_analysis()/d" /www/server/panel/script/site_task.py
sed -i "s/run_thread(cloud_check_domain,(domain,))/return/" /www/server/panel/class/public.py

# 关闭面板强制更新
sed -i "/#是否执行升级程序/a \ \ \ \ \ \ \ \ \ \ \ \ updateInfo[\'force\'] = False;" /www/server/panel/class/ajax.py
rm -f /www/server/panel/data/autoUpdate.pl

# 关闭自动更新软件列表
sed -i "/plugin_timeout = 86400/d" /www/server/panel/class/public.py
sed -i "/list_body = None/a \ \ \ \ \plugin_timeout = 0;" /www/server/panel/class/public.py

# 去后门
sudo echo "" > /www/server/panel/script/site_task.py
sudo chattr +i /www/server/panel/script/site_task.py
sudo rm -rf /www/server/panel/logs/request/*
sudo chattr +i -R /www/server/panel/logs/request


# 重启面板
/etc/init.d/bt restart