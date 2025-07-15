#!/bin/bash

set -e

echo "=== 更新系统 ==="
sudo apt update

echo "=== 安装依赖 ==="
sudo apt install -y curl gnupg2

echo "=== 添加 Redis 官方源 ==="
curl -fsSL https://packages.redis.io/gpg | sudo gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/redis.list

echo "=== 更新软件源并安装 Redis ==="
sudo apt update
sudo apt install -y redis

echo "=== 启动 Redis 并设置开机启动 ==="
sudo systemctl enable redis-server.service
sudo systemctl start redis

echo "=== 验证 Redis 安装 ==="
redis-server --version