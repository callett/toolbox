#!/usr/bin/env bash
set -euo pipefail

# ========== 交互输入 ==========
read -p "请输入域名 (SNI/证书使用的域名，例如 example.com): " DOMAIN
read -p "请输入 trojan-go 监听端口 (默认 443): " LISTEN_PORT
LISTEN_PORT=${LISTEN_PORT:-443}
read -p "请输入 trojan 密码 (留空则自动生成): " PASSWORD

if [[ -z "$PASSWORD" ]]; then
    PASSWORD=$(cat /proc/sys/kernel/random/uuid)
    echo "未输入密码，已自动生成：$PASSWORD"
fi

FALLBACK_PORT=80              # fallback HTTP 可改
LISTEN_ADDR="0.0.0.0"
CERT_BASE_DIR="/cert"
CERT_DIR="${CERT_BASE_DIR}/${DOMAIN}"
CRT_PATH="${CERT_DIR}/fullchain.pem"
KEY_PATH="${CERT_DIR}/privkey.pem"
WORKDIR="/root/trojan_go_install"
TG_BIN="/usr/local/bin/trojan-go"
CONFIG_DIR="/etc/trojan-go"
SERVICE_PATH="/etc/systemd/system/trojan-go.service"
LOG_FILE="/var/log/trojan-go.log"
RELOAD_CMD="systemctl restart trojan-go || true; systemctl restart nginx 2>/dev/null || true"

# ========== 检查 root ==========
if [[ $EUID -ne 0 ]]; then
    echo "请以 root 或 sudo 运行此脚本" >&2
    exit 1
fi

mkdir -p "$WORKDIR"
cd "$WORKDIR"

# ========== 安装依赖 ==========
apt update
apt install -y curl wget tar unzip jq ca-certificates socat cron

# ========== 停止可能占用 80 端口的服务 ==========
if ss -ltnp | grep -q ":80 "; then
    echo "80端口被占用，尝试停止 nginx / apache2"
    systemctl stop nginx 2>/dev/null || true
    systemctl stop apache2 2>/dev/null || true
fi

# ========== 安装 acme.sh ==========
if [[ ! -f /root/.acme.sh/acme.sh ]]; then
    curl https://get.acme.sh | sh
fi
ln -sf /root/.acme.sh/acme.sh /usr/local/bin/acme.sh
export PATH="/root/.acme.sh:${PATH}"

# ========== 设置默认 CA ==========
acme.sh --set-default-ca --server letsencrypt

# ========== 申请证书 ==========
mkdir -p "$CERT_DIR"
echo "申请 TLS 证书..."
acme.sh --issue -d "$DOMAIN" --standalone
acme.sh --install-cert -d "$DOMAIN" \
    --key-file "$KEY_PATH" \
    --fullchain-file "$CRT_PATH" \
    --reloadcmd "$RELOAD_CMD"

# ========== 下载 trojan-go ==========
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

# ========== 写配置 ==========
mkdir -p "$CONFIG_DIR"
cat > "$CONFIG_DIR/config.json" <<EOF
{
  "run_type": "server",
  "local_addr": "$LISTEN_ADDR",
  "local_port": $LISTEN_PORT,
  "remote_addr": "127.0.0.1",
  "remote_port": 80,
  "password": ["$PASSWORD"],
  "ssl": {
    "cert": "$CRT_PATH",
    "key": "$KEY_PATH",
    "sni": "$DOMAIN",
    "fallback_port": $FALLBACK_PORT
  },
  "websocket": { "enabled": false },
  "transport_plugin": { "enabled": false },
  "log_level": 1,
  "log_file": "$LOG_FILE"
}
EOF

# ========== systemd 服务 ==========
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

# ========== 防火墙 ==========
# if command -v ufw >/dev/null 2>&1; then
#     ufw allow "$LISTEN_PORT/tcp" || true
# fi
# if command -v iptables >/dev/null 2>&1; then
#     iptables -C INPUT -p tcp --dport "$LISTEN_PORT" -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport "$LISTEN_PORT" -j ACCEPT
# fi

# ========== 输出 Surge 配置 ==========
echo
echo "================ 安装完成 ================="
echo "Surge 配置示例："
echo "-----------------------------------------------------"
echo "TrojanProxy = trojan, $DOMAIN, $LISTEN_PORT, password=$PASSWORD, sni=$DOMAIN"
echo "-----------------------------------------------------"
echo "trojan-go 已启动，服务状态: systemctl status trojan-go -l"
echo "证书续期时 acme.sh 会执行 reloadcmd 重启 trojan-go"
echo "====================================================="