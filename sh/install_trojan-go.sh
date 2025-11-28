#!/usr/bin/env bash
set -e

# 颜色定义
GREEN='\033[0;32m'
NC='\033[0m' # 没颜色

echo "${GREEN}======================"
echo "Trojan-Go 一键安装配置脚本"
echo "======================${NC}"

# 安装依赖
echo "${GREEN}安装必要依赖${NC}"
apt update -y && apt install -y curl sudo nano unzip socat cron jq ca-certificates

# 获取公网 IP
IP=$(curl -s https://api.ipify.org)

# 输入端口
read -p "${GREEN}请输入 Trojan-Go 监听端口（默认 443）: ${NC}" PORT
PORT=${PORT:-443}

# 输入域名
read -p "${GREEN}请输入你的域名（用于 ACME 证书）: ${NC}" DOMAIN
if [[ -z "$DOMAIN" ]]; then
  echo "域名不能为空"
  exit 1
fi

# 输入邮箱
read -p "${GREEN}请输入你的邮箱（ACME 注册用）: ${NC}" EMAIL
if [[ -z "$EMAIL" ]]; then
  echo "邮箱不能为空"
  exit 1
fi

# 输入密码，可选
read -p "${GREEN}请输入 Trojan-Go 密码（留空则随机生成）: ${NC}" PASSWORD
if [[ -z "$PASSWORD" ]]; then
    PASSWORD=$(cat /proc/sys/kernel/random/uuid)
    echo "未输入密码，已随机生成：$PASSWORD"
fi

# 目录和文件
CERT_DIR="/cert/${DOMAIN}"
CRT_PATH="${CERT_DIR}/fullchain.pem"
KEY_PATH="${CERT_DIR}/privkey.pem"
CONFIG_DIR="/etc/trojan-go"
TG_BIN="/usr/local/bin/trojan-go"
SERVICE_PATH="/etc/systemd/system/trojan-go.service"
LOG_FILE="/var/log/trojan-go.log"
RELOAD_CMD="systemctl restart trojan-go || true; systemctl restart nginx 2>/dev/null || true"

mkdir -p "$CERT_DIR" "$CONFIG_DIR"

# 安装 acme.sh 并注册账号
if [[ ! -f /root/.acme.sh/acme.sh ]]; then
    curl https://get.acme.sh | sh
fi
ln -sf /root/.acme.sh/acme.sh /usr/local/bin/acme.sh
export PATH="/root/.acme.sh:${PATH}"
/root/.acme.sh/acme.sh --register-account -m "$EMAIL"
acme.sh --set-default-ca --server letsencrypt

# 申请证书
echo "${GREEN}申请 TLS 证书...${NC}"
acme.sh --issue -d "$DOMAIN" --standalone
acme.sh --install-cert -d "$DOMAIN" \
    --key-file "$KEY_PATH" \
    --fullchain-file "$CRT_PATH" \
    --reloadcmd "$RELOAD_CMD"

# 下载 trojan-go
ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" || "$ARCH" == "amd64" ]]; then
    ASSET_REGEX="linux-amd64.zip"
elif [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
    ASSET_REGEX="linux-arm64.zip"
else
    ASSET_REGEX="linux-amd64.zip"
fi

TG_URL=$(curl -s "https://api.github.com/repos/p4gefau1t/trojan-go/releases/latest" \
    | jq -r --arg re "$ASSET_REGEX" '.assets[] | select(.name | test($re)) | .browser_download_url' | head -n1)
curl -L -o trojan-go.zip "$TG_URL"
unzip -o trojan-go.zip -d trojan-go-bin
cp trojan-go-bin/trojan-go "$TG_BIN"
chmod +x "$TG_BIN"

# 写配置文件
cat > "$CONFIG_DIR/config.json" <<EOF
{
  "run_type": "server",
  "local_addr": "0.0.0.0",
  "local_port": $PORT,
  "remote_addr": "127.0.0.1",
  "remote_port": 80,
  "password": ["$PASSWORD"],
  "ssl": {
    "cert": "$CRT_PATH",
    "key": "$KEY_PATH",
    "sni": "$DOMAIN",
    "fallback_port": 80
  },
  "websocket": { "enabled": false },
  "transport_plugin": { "enabled": false },
  "log_level": 1,
  "log_file": "$LOG_FILE"
}
EOF

# systemd 服务
cat > "$SERVICE_PATH" <<'SERVICE'
[Unit]
Description=trojan-go
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/trojan-go -config /etc/trojan-go/config.json
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
SERVICE

touch "$LOG_FILE"
chown root:root "$LOG_FILE"
chmod 644 "$LOG_FILE"

systemctl daemon-reload
systemctl enable trojan-go
systemctl restart trojan-go

# 输出结果
echo "${GREEN}======================"
echo "Trojan-Go 安装完成！"
echo "端口: $PORT"
echo "域名: $DOMAIN"
echo "密码: $PASSWORD"
echo ""
echo "Surge 配置示例:"
echo "TrojanProxy = trojan, $IP, $PORT, password=$PASSWORD, sni=$DOMAIN"
echo "======================${NC}"