#!/bin/bash

# 颜色定义
GREEN='\033[0;32m'
NC='\033[0m' # 无颜色

# 获取公网 IP
IP=$(curl -s https://api.ipify.org)

# 设置默认端口
DEFAULT_PORT=443
read -p "请输入端口号（默认: $DEFAULT_PORT）: " PORT
PORT=${PORT:-$DEFAULT_PORT}

# 生成 base64 密钥（32字节）
KEY=$(head -c 32 /dev/urandom | base64)

# 下载并解压 Shadowsocks-Rust（v1.23.0）
sudo apt update
sudo apt install xz-utils
mkdir -p ~/ss && cd ~/ss
wget -q https://github.com/shadowsocks/shadowsocks-rust/releases/download/v1.23.0/shadowsocks-v1.23.0.x86_64-unknown-linux-gnu.tar.xz
tar -xf shadowsocks-v1.23.0.x86_64-unknown-linux-gnu.tar.xz && rm -f shadowsocks-v1.23.0.x86_64-unknown-linux-gnu.tar.xz
sudo mv ssserver /usr/local/bin
sudo mkdir -p /etc/shadowsocks-rust

# 创建配置文件（支持 SS2022）
sudo tee /etc/shadowsocks-rust/config.json > /dev/null << EOF
{
  "server": "::",
  "server_port": $PORT,
  "method": "2022-blake3-aes-256-gcm",
  "password": "$KEY",
  "fast_open": true,
  "no_delay": true,
  "timeout": 300
}
EOF

# 创建 systemd 服务
sudo tee /etc/systemd/system/ssserver.service > /dev/null << EOF
[Unit]
Description=Shadowsocks Rust Server (SS2022)
After=network.target

[Service]
ExecStart=/usr/local/bin/ssserver -c /etc/shadowsocks-rust/config.json
Restart=on-failure
LimitNOFILE=51200

[Install]
WantedBy=multi-user.target
EOF

# 启动服务
sudo systemctl daemon-reexec
sudo systemctl enable ssserver --now

# 输出配置信息
echo
echo -e "${GREEN}Shadowsocks 2022 配置信息：${NC}"
echo -e "${GREEN}服务器地址：${IP}${NC}"
echo -e "${GREEN}端口：${PORT}${NC}"
echo -e "${GREEN}加密方式：2022-blake3-aes-256-gcm${NC}"
echo -e "${GREEN}密钥（base64）：${KEY}${NC}"
echo
echo -e "${GREEN}Clash.Meta 示例配置：${NC}"
echo -e "${GREEN}  - name: SS2022${NC}"
echo -e "${GREEN}    type: ss${NC}"
echo -e "${GREEN}    server: ${IP}${NC}"
echo -e "${GREEN}    port: ${PORT}${NC}"
echo -e "${GREEN}    cipher: 2022-blake3-aes-256-gcm${NC}"
echo -e "${GREEN}    password: ${KEY}${NC}"