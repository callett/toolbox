#!/bin/bash

set -e

echo "更新系统并安装依赖..."
sudo apt update
sudo apt install -y wget lsb-release gnupg

# 获取当前系统发行版信息
DISTRO=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
RELEASE=$(lsb_release -cs)

# 下载最新版 MySQL APT 配置包（当前指向官方固定链接）
echo "下载 MySQL APT 配置包..."
wget https://dev.mysql.com/get/mysql-apt-config_0.8.34-1_all.deb -O mysql-apt-config.deb

# 安装 MySQL APT 配置包
echo "安装 MySQL APT 配置包（请在弹出的界面中选择 MySQL 8.0 或所需版本，然后按 Tab -> Enter）..."
sudo dpkg -i mysql-apt-config.deb

# 再次更新 apt 缓存
echo "更新软件包列表..."
sudo apt update

# 安装 MySQL Server
echo "安装 MySQL Server..."
sudo apt install -y mysql-server

# 启动并设置开机自启
echo "启动 MySQL 并设置为开机启动..."
sudo systemctl enable mysql
sudo systemctl start mysql
sudo rm -rf mysql-apt-config.deb

# 检查 MySQL 状态
echo "MySQL 安装完成，当前状态："
sudo systemctl status mysql --no-pager
