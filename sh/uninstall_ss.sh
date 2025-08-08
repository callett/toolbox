#!/bin/bash

# 停止服务
sudo systemctl stop ssserver
sudo systemctl disable ssserver

# 删除 systemd 服务文件
sudo rm -f /etc/systemd/system/ssserver.service

# 删除 Shadowsocks-Rust 可执行文件
sudo rm -f /usr/local/bin/ssserver

# 删除配置目录
sudo rm -rf /etc/shadowsocks-rust

# 删除安装时的临时目录
rm -rf ~/ss

# 重新加载 systemd
sudo systemctl daemon-reload

echo "✅ Shadowsocks-Rust (SS2022) 已卸载并清理相关文件"