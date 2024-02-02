#!/bin/bash
git add .
read -p "Please enter commit message: " commitMsg
if [ -z $commitMsg ];then
  commitMsg="Docs: 『note』内容更新 $(date +'%F %a %T')"
fi
git commit -m "$commitMsg"
git push -f origin --all  #向存储库推送