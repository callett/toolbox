#!/bin/bash

# ========== 颜色定义 ==========
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

set -e

echo -e "${GREEN}==== VLESS + Reality 一键安装脚本（Xray / sing-box 二选一）====${NC}"

# ========== 检查 root ==========
if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}请使用 root 用户运行此脚本${NC}"
    exit 1
fi

# ========== 选择核心 ==========
echo ""
echo -e "${YELLOW}请选择要安装的核心：${NC}"
echo "  1) Xray"
echo "  2) sing-box"
read -r -p "请输入选项 [1/2，默认 1]: " CORE_CHOICE
CORE_CHOICE=${CORE_CHOICE:-1}

case "$CORE_CHOICE" in
    1) CORE="xray" ;;
    2) CORE="singbox" ;;
    *) echo -e "${RED}无效选项${NC}"; exit 1 ;;
esac

# ========== 公共参数输入 ==========
echo ""
read -r -p "请输入监听端口 [默认: 443]: " LISTEN_PORT
LISTEN_PORT=${LISTEN_PORT:-443}

read -r -p "请输入伪装域名 server_name (SNI) [默认: www.microsoft.com]: " SERVER_NAME
SERVER_NAME=${SERVER_NAME:-www.microsoft.com}

read -r -p "请输入节点链接备注名（可选，直接回车跳过）: " LINK_NAME

USER_NAME="user"
if [ "$CORE" = "singbox" ]; then
    read -r -p "请输入用户名 [默认: user]: " USER_NAME
    USER_NAME=${USER_NAME:-user}
fi

# ========== 安装 Xray ==========
install_xray() {
    echo -e "${YELLOW}正在安装 Xray...${NC}"
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

    UUID=$(xray uuid)
    KEYS=$(xray x25519)
    # 兼容新旧版本输出格式（新版: PrivateKey / Password；旧版: Private key / Public key）
    PRIVATE_KEY=$(echo "$KEYS" | grep -iE 'PrivateKey|Private key' | awk '{print $NF}')
    PUBLIC_KEY=$(echo "$KEYS" | grep -iE 'Password|Public key|PublicKey' | awk '{print $NF}')
    SHORT_ID=$(openssl rand -hex 8)

    CONFIG_PATH="/usr/local/etc/xray/config.json"
    cat > "$CONFIG_PATH" << EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": ${LISTEN_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "dest": "${SERVER_NAME}:443",
          "serverNames": [
            "${SERVER_NAME}"
          ],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": [
            "",
            "${SHORT_ID}"
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ],
        "routeOnly": true
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    }
  ]
}
EOF

    systemctl enable xray
    systemctl restart xray
    sleep 1
    systemctl status xray --no-pager || true
}

# ========== 安装 sing-box ==========
install_singbox() {
    echo -e "${YELLOW}正在下载并安装 sing-box 最新版本...${NC}"

    case "$(uname -m)" in
        x86_64|amd64)  ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        *) echo -e "${RED}不支持的架构: $(uname -m)${NC}"; exit 1 ;;
    esac

    cd /tmp
    SINGBOX_VERSION=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest \
        | grep '"tag_name":' \
        | sed -E 's/.*"v([^"]+)".*/\1/')

    if [ -z "$SINGBOX_VERSION" ]; then
        echo -e "${RED}获取 sing-box 最新版本失败${NC}"
        exit 1
    fi
    echo "Latest sing-box version: ${SINGBOX_VERSION}"

    PKG="sing-box-${SINGBOX_VERSION}-linux-${ARCH}"
    wget -q "https://github.com/SagerNet/sing-box/releases/download/v${SINGBOX_VERSION}/${PKG}.tar.gz"
    tar -xzf "${PKG}.tar.gz"
    install -m 755 "${PKG}/sing-box" /usr/local/bin/
    rm -rf "/tmp/${PKG}" "/tmp/${PKG}.tar.gz"

    if ! command -v sing-box &> /dev/null; then
        echo -e "${RED}sing-box 安装失败${NC}"
        exit 1
    fi
    echo -e "${GREEN}sing-box 安装成功，版本信息：${NC}"
    sing-box version

    echo -e "${YELLOW}正在生成 UUID、Reality 密钥对、ShortID...${NC}"
    UUID=$(sing-box generate uuid)
    KEYPAIR=$(sing-box generate reality-keypair)
    PRIVATE_KEY=$(echo "$KEYPAIR" | grep -i "PrivateKey" | awk '{print $2}')
    PUBLIC_KEY=$(echo "$KEYPAIR" | grep -i "PublicKey" | awk '{print $2}')
    SHORT_ID=$(openssl rand -hex 8)

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
      "tcp_fast_open": true,
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

    echo -e "${YELLOW}正在校验配置文件...${NC}"
    if ! sing-box check -c /etc/sing-box/config.json; then
        echo -e "${RED}配置文件校验失败，请检查${NC}"
        exit 1
    fi
    sing-box format -w -c /etc/sing-box/config.json
    echo -e "${GREEN}配置文件校验通过${NC}"

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
    systemctl status sing-box --no-pager || true
}

# ========== 执行安装 ==========
echo ""
if [ "$CORE" = "xray" ]; then
    install_xray
else
    install_singbox
fi

# ========== 获取公网 IP ==========
echo ""
echo -e "${YELLOW}正在获取本机公网IP...${NC}"
IP=$(curl -s https://api.ipify.org || true)
if [ -z "$IP" ]; then
    echo -e "${RED}获取公网IP失败，请手动替换链接中的IP${NC}"
    IP="替换成你的IP"
fi

# ========== 组装 vless 链接 ==========
if [ -n "$LINK_NAME" ]; then
    ENCODED_NAME=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$LINK_NAME" 2>/dev/null || echo "$LINK_NAME")
else
    ENCODED_NAME="${CORE}-reality"
fi

VLESS_LINK="vless://${UUID}@${IP}:${LISTEN_PORT}?encryption=none&security=reality&type=tcp&flow=xtls-rprx-vision&pbk=${PUBLIC_KEY}&fp=chrome&sni=${SERVER_NAME}&sid=${SHORT_ID}#${ENCODED_NAME}"

# ========== 输出结果 ==========
echo ""
echo -e "${GREEN}==== 安装完成（核心: ${CORE}）====${NC}"
echo -e "${GREEN}监听端口：${LISTEN_PORT}${NC}"
echo -e "${GREEN}UUID: ${UUID}${NC}"
echo -e "${GREEN}公钥: ${PUBLIC_KEY}${NC}"
echo -e "${GREEN}ShortID: ${SHORT_ID}${NC}"
echo -e "${GREEN}伪装域名: ${SERVER_NAME}${NC}"
echo ""
echo -e "${GREEN}节点链接：${NC}"
echo -e "${GREEN}${VLESS_LINK}${NC}"
echo ""
echo -e "${YELLOW}请妥善保存以上信息${NC}"
