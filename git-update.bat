@echo off
chcp 65001
cls

echo ===== 临时关闭 SSL 验证 =====
git config --global http.sslVerify false

echo ===== 获取最新更改 =====
git fetch origin main

echo ===== 合并远程更改 =====
git pull origin main

echo ===== 显示当前状态 =====
git status

echo ===== 添加所有更改 =====
git add .

echo ===== 提交更改 =====
set /p msg="请输入提交信息: "
git commit -m "%msg%"

echo ===== 推送更改 =====
git push origin main

echo ===== 重新开启 SSL 验证 =====
git config --global http.sslVerify true

echo ===== 更新完成 =====
pause 