#!/bin/bash

# ========== 颜色定义 ==========
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # 没颜色

set -e

echo -e "${GREEN}==== sing-box VLESS + Reality 自动安装脚本 ====${NC}"

# ========== 检查是否为root ==========
if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}请使用 root 用户运行此脚本${NC}"
    exit 1
fi

# ========== 下载安装 sing-box ==========
echo -e "${YELLOW}正在下载并安装 sing-box 最新版本...${NC}"

cd /tmp

SINGBOX_VERSION=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest \
| grep '"tag_name":' \
| sed -E 's/.*"v([^"]+)".*/\1/')

echo "Latest sing-box version: ${SINGBOX_VERSION}"

wget -q "https://github.com/SagerNet/sing-box/releases/download/v${SINGBOX_VERSION}/sing-box-${SINGBOX_VERSION}-linux-amd64.tar.gz"

tar -xzf sing-box-*.tar.gz

cd sing-box-*/

install -m 755 sing-box /usr/local/bin/

cd /tmp

rm -rf "sing-box-${SINGBOX_VERSION}-linux-amd64"
rm -f sing-box-*.tar.gz

if ! command -v sing-box &> /dev/null; then
    echo -e "${RED}sing-box 安装失败${NC}"
    exit 1
fi

echo -e "${GREEN}sing-box 安装成功，版本信息：${NC}"
sing-box version

# ========== 交互式输入参数 ==========
echo ""
echo -e "${YELLOW}请输入监听端口 [默认: 443]:${NC}"
read -r LISTEN_PORT
LISTEN_PORT=${LISTEN_PORT:-443}

echo -e "${YELLOW}请输入用户名 [默认: user]:${NC}"
read -r USER_NAME
USER_NAME=${USER_NAME:-user}

echo -e "${YELLOW}请输入伪装的 server_name (SNI) [默认: www.microsoft.com]:${NC}"
read -r SERVER_NAME
SERVER_NAME=${SERVER_NAME:-www.microsoft.com}

echo -e "${YELLOW}请输入节点链接备注名（可选，直接回车跳过）:${NC}"
read -r LINK_NAME

# ========== 生成 UUID、密钥对、ShortID ==========
echo ""
echo -e "${YELLOW}正在生成 UUID、Reality 密钥对、ShortID...${NC}"

UUID=$(sing-box generate uuid)

KEYPAIR=$(sing-box generate reality-keypair)
PRIVATE_KEY=$(echo "$KEYPAIR" | grep -i "PrivateKey" | awk '{print $2}')
PUBLIC_KEY=$(echo "$KEYPAIR" | grep -i "PublicKey" | awk '{print $2}')

SHORT_ID=$(openssl rand -hex 8)

echo -e "${GREEN}UUID: ${NC}${UUID}"
echo -e "${GREEN}私钥: ${NC}${PRIVATE_KEY}"
echo -e "${GREEN}公钥: ${NC}${PUBLIC_KEY}"
echo -e "${GREEN}ShortID: ${NC}${SHORT_ID}"

# ========== 创建配置文件 ==========
echo ""
echo -e "${YELLOW}正在生成配置文件...${NC}"
mkdir -p /etc/sing-box

cat > /etc/sing-box/config.json <<EOF
{
  "log": {
    "level": "warn",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-reality-vision",
      "listen": "0.0.0.0",
      "listen_port": ${LISTEN_PORT},
      "users": [
        {
          "name": "${USER_NAME}",
          "uuid": "${UUID}",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${SERVER_NAME}",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "${SERVER_NAME}",
            "server_port": 443,
            "connect_timeout": "10s"
          },
          "private_key": "${PRIVATE_KEY}",
          "short_id": [
            "${SHORT_ID}"
          ],
          "max_time_difference": "1m"
        }
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
    "final": "direct"
  }
}
EOF

# ========== 检查并格式化配置文件 ==========
echo -e "${YELLOW}正在校验配置文件...${NC}"
if ! sing-box check -c /etc/sing-box/config.json; then
    echo -e "${RED}配置文件校验失败，请检查${NC}"
    exit 1
fi
sing-box format -w -c /etc/sing-box/config.json
echo -e "${GREEN}配置文件校验通过${NC}"

# ========== 编写 systemd 服务 ==========
echo -e "${YELLOW}正在配置 systemd 服务...${NC}"

cat > /etc/systemd/system/sing-box.service <<'EOF'
[Unit]
Description=sing-box service
After=network-online.target
Wants=network-online.target
[Service]
Type=simple
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576
# 安全加固（可选但推荐）
NoNewPrivileges=true
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable sing-box
systemctl restart sing-box

sleep 1
echo ""
echo -e "${GREEN}==== sing-box 服务状态 ====${NC}"
systemctl status sing-box --no-pager

# ========== 获取公网IP ==========
echo ""
echo -e "${YELLOW}正在获取本机公网IP...${NC}"
IP=$(curl -s https://api.ipify.org)

if [ -z "$IP" ]; then
    echo -e "${RED}获取公网IP失败，请手动替换链接中的IP${NC}"
    IP="替换成你的IP"
fi

# ========== 组装 vless 链接 ==========
if [ -n "$LINK_NAME" ]; then
    ENCODED_NAME=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$LINK_NAME" 2>/dev/null || echo "$LINK_NAME")
else
    ENCODED_NAME="sing-box-reality"
fi

VLESS_LINK="vless://${UUID}@${IP}:${LISTEN_PORT}?encryption=none&security=reality&type=tcp&flow=xtls-rprx-vision&pbk=${PUBLIC_KEY}&fp=chrome&sni=${SERVER_NAME}&sid=${SHORT_ID}#${ENCODED_NAME}"

echo ""
echo -e "${GREEN}==== 安装完成，节点链接如下 ====${NC}"
echo -e "${GREEN}${VLESS_LINK}${NC}"
echo ""
echo -e "${YELLOW}请妥善保存以上链接，可直接导入支持 VLESS+Reality 的客户端使用${NC}"