
## 路飞工具箱


文件行结束符格式不一致，Git 会自动转换.


```bash
git config --global core.autocrlf true
```



添加gitee仓库

1. 生成一个Gitee用的SSH-Key

```
ssh-keygen -q -t ed25519 -C "2761282805@qq.com" -N "" -f ~/.ssh/gitee_id_rsa
```

2. 添加公钥地址：

```
https://gitee.com/profile/sshkeys
```

3. 在 ~/.ssh 目录下新建一个config文件，添加如下内容

```
# gitee
Host gitee.com
HostName gitee.com
PreferredAuthentications publickey
IdentityFile ~/.ssh/gitee_id_rsa

```

4. 用ssh命令测试


```
ssh -T git@gitee.com
```

5. 添加仓库

```
git remote set-url --add origin git@gitee.com:dayu777/open_shell.git
```




<br>

```shell

curl -sS -O https://raw.githubusercontent.com/woniu336/open_shell/main/tool.sh && chmod +x tool.sh && ./tool.sh

```

<br>





                   _ooOoo_
                  o8888888o
                  88" . "88
                  (| -_- |)
                  O\  =  /O
               ____/`---'\____
             .'  \\|     |//  `。
            /  \\|||  :  |||//  \
           /  _||||| -:- |||||-  \
           |   | \\\  -  /// |   |
           | \_|  ''\---/''  |   |
           \  .-\__  `-`  ___/-. /
         ___`. .'  /--.--\  `. . __
      ."" '<  `.___\_<|>_/___.'  >'"".
     | | :  `- \`.;`\ _ /`;.`/ - ` : | |
     \  \ `-.   \_ __\ /__ _/   .-` /  /
======`-.____`-.___\_____/___.-`____.-'======
                   `=---='
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
