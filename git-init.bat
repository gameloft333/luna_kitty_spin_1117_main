@echo off
chcp 65001
cls

echo ===== 临时关闭 SSL 验证 =====
git config --global http.sslVerify false

echo ===== 初始化 Git 仓库 =====
git init

echo ===== 创建主分支 =====
git checkout -b main

echo ===== 添加远程仓库 =====
set /p repo="请输入 GitHub 仓库地址: "
git remote remove origin
git remote add origin %repo%

echo ===== 添加所有文件 =====
git add .

echo ===== 初始提交 =====
git commit -m "Initial commit"

echo ===== 推送到主分支 =====
git push -u origin main

echo ===== 重新开启 SSL 验证 =====
git config --global http.sslVerify true

echo ===== 初始化完成 =====
pause 