#!/usr/bin/env bash
set -euo pipefail

# ================== 在这里修改（必填） ==================
DOMAIN="example.com"                       # <-- 改成你的域名 (必须解析到本机IP)
EMAIL="admin@example.com"                  # <-- acme 注册邮箱（可留空）
PASSWORD=""                                # <-- trojan 密码（留空脚本会自动生成）
CERT_BASE_DIR="/cert"                      # <-- 证书基目录，最终证书路径: $CERT_BASE_DIR/$DOMAIN
LISTEN_ADDR="0.0.0.0"                      # <-- trojan-go 监听地址
LISTEN_PORT=443                            # <-- trojan-go 监听端口（建议 443 或 8443）
FALLBACK_PORT=80                           # <-- fallback_port（回落 HTTP）
# ======================================================

# 路径与文件
WORKDIR="/root/trojan_go_install"
TG_BIN="/usr/local/bin/trojan-go"
CONFIG_DIR="/etc/trojan-go"
SERVICE_PATH="/etc/systemd/system/trojan-go.service"
LOG_FILE="/var/log/trojan-go.log"
ACME_SH="/root/.acme.sh/acme.sh"
CERT_DIR="${CERT_BASE_DIR}/${DOMAIN}"
CRT_PATH="${CERT_DIR}/fullchain.pem"
KEY_PATH="${CERT_DIR}/privkey.pem"

# =========== 权限检查 ===========
if [[ $EUID -ne 0 ]]; then
  echo "请以 root 运行此脚本 (sudo)." >&2
  exit 1
fi

# 生成密码（如未提供）
if [[ -z "${PASSWORD}" ]]; then
  PASSWORD=$(cat /proc/sys/kernel/random/uuid)
  echo "未输入密码，已自动生成：${PASSWORD}"
fi

echo "准备在 Debian 12 上安装 trojan-go 并用 acme.sh 为 ${DOMAIN} 申请证书"
mkdir -p "${WORKDIR}"
cd "${WORKDIR}"

# =========== 安装依赖 ===========
apt update
DEPS="curl wget tar unzip jq ca-certificates socat cron"
apt install -y ${DEPS} || { echo "apt install 失败，请检查网络与 apt 源"; exit 1; }

# =========== 停止可能占用 80 端口的服务（以便证书申请） ===========
if ss -ltnp | grep -q ":80 "; then
  echo "发现 80 端口被占用，尝试停止常见服务：nginx / apache2"
  systemctl stop nginx 2>/dev/null || true
  systemctl stop apache2 2>/dev/null || true
fi

# =========== 安装 acme.sh ===========
if [[ ! -f "${ACME_SH}" ]]; then
  echo "安装 acme.sh ..."
  curl https://get.acme.sh | sh
  # 把 acme.sh 链接到 /usr/local/bin（方便使用）
  ln -sf /root/.acme.sh/acme.sh /usr/local/bin/acme.sh
else
  echo "acme.sh 已存在，跳过安装"
fi

# 确保 acme.sh 在 PATH
export PATH="/root/.acme.sh:${PATH}"

# =========== 设置默认 CA 并注册（可选） ===========
echo "设置默认 CA 为 Let's Encrypt ..."
/root/.acme.sh/acme.sh --set-default-ca --server letsencrypt

if [[ -n "${EMAIL}" ]]; then
  echo "注册 acme 账号邮箱为 ${EMAIL}（若已注册会忽略）"
  /root/.acme.sh/acme.sh --register-account -m "${EMAIL}" || true
fi

# =========== 申请证书（standalone 模式） ===========
echo "开始申请证书：acme.sh --issue -d ${DOMAIN} --standalone"
# 重试机制：若 1 次申请失败，最多重试 2 次
set +e
ATTEMPTS=0
MAX_ATTEMPTS=3
ISSUE_OK=1
while [[ ${ATTEMPTS} -lt ${MAX_ATTEMPTS} ]]; do
  /root/.acme.sh/acme.sh --issue -d "${DOMAIN}" --standalone
  if [[ $? -eq 0 ]]; then
    ISSUE_OK=0
    break
  fi
  ATTEMPTS=$((ATTEMPTS+1))
  echo "申请失败，重试 ${ATTEMPTS}/${MAX_ATTEMPTS} ..."
  sleep 2
done
set -e

if [[ ${ISSUE_OK} -ne 0 ]]; then
  echo "证书申请失败。请检查域名解析、80 端口是否被屏蔽或服务器能否被外网访问。" >&2
  exit 1
fi

# =========== 安装证书到指定路径并设置续期 reloadcmd ===========
echo "创建证书目录：${CERT_DIR}"
mkdir -p "${CERT_DIR}"

# reloadcmd 会在证书续期后执行，我们让它重启 trojan-go（以及 nginx，若存在）
RELOAD_CMD="systemctl restart trojan-go || true; systemctl restart nginx 2>/dev/null || true"

echo "安装证书到："
echo "  证书: ${CRT_PATH}"
echo "  私钥: ${KEY_PATH}"
/root/.acme.sh/acme.sh --install-cert -d "${DOMAIN}" \
  --key-file "${KEY_PATH}" \
  --fullchain-file "${CRT_PATH}" \
  --reloadcmd "${RELOAD_CMD}"

# 确认证书文件存在
if [[ ! -f "${CRT_PATH}" || ! -f "${KEY_PATH}" ]]; then
  echo "证书文件未找到：${CRT_PATH} 或 ${KEY_PATH}" >&2
  exit 1
fi

# =========== 下载并安装 trojan-go ===========
ARCH=$(uname -m)
echo "检测架构: ${ARCH}"
if [[ "${ARCH}" == "x86_64" || "${ARCH}" == "amd64" ]]; then
  ASSET_REGEX="linux-amd64.zip"
elif [[ "${ARCH}" == "aarch64" || "${ARCH}" == "arm64" ]]; then
  ASSET_REGEX="linux-arm64.zip"
else
  ASSET_REGEX="linux-amd64.zip"
fi

echo "获取 trojan-go release 下载地址..."
TG_URL=$(curl -s "https://api.github.com/repos/p4gefau1t/trojan-go/releases/latest" \
  | jq -r --arg re "${ASSET_REGEX}" '.assets[] | select(.name | test($re)) | .browser_download_url' \
  | head -n1)

if [[ -z "${TG_URL}" || "${TG_URL}" == "null" ]]; then
  echo "无法从 GitHub API 获取 trojan-go 下载地址，请手动下载并放到 ${WORKDIR}，然后解压并复制 trojan-go 到 ${TG_BIN}。" >&2
  exit 1
fi

echo "下载 trojan-go：${TG_URL}"
curl -L -o trojan-go.zip "${TG_URL}"
unzip -o trojan-go.zip -d trojan-go-bin
if [[ -f trojan-go-bin/trojan-go ]]; then
  cp trojan-go-bin/trojan-go "${TG_BIN}"
elif [[ -f trojan-go ]]; then
  cp trojan-go "${TG_BIN}"
else
  echo "未找到 trojan-go 可执行文件，请检查压缩包内容" >&2
  exit 1
fi
chmod +x "${TG_BIN}"

# =========== 写入 trojan-go 配置 ===========
mkdir -p "${CONFIG_DIR}"

cat > "${CONFIG_DIR}/config.json" <<EOF
{
  "run_type": "server",
  "local_addr": "${LISTEN_ADDR}",
  "local_port": ${LISTEN_PORT},
  "remote_addr": "127.0.0.1",
  "remote_port": 80,
  "password": [
    "${PASSWORD}"
  ],
  "ssl": {
    "cert": "${CRT_PATH}",
    "key": "${KEY_PATH}",
    "sni": "${DOMAIN}",
    "fallback_port": ${FALLBACK_PORT}
  },
  "websocket": {
    "enabled": false
  },
  "transport_plugin": {
    "enabled": false
  },
  "log_level": 1,
  "log_file": "${LOG_FILE}"
}
EOF

# =========== systemd 服务 ===========
cat > "${SERVICE_PATH}" <<'SERVICE'
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

# 日志文件
touch "${LOG_FILE}"
chown root:root "${LOG_FILE}"
chmod 644 "${LOG_FILE}"

# 启用并启动
systemctl daemon-reload
systemctl enable trojan-go
systemctl restart trojan-go

# 防火墙规则
if command -v ufw >/dev/null 2>&1; then
  echo "配置 ufw 允许端口 ${LISTEN_PORT}..."
  ufw allow "${LISTEN_PORT}/tcp" || true
fi
if command -v iptables >/dev/null 2>&1; then
  iptables -C INPUT -p tcp --dport "${LISTEN_PORT}" -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport "${LISTEN_PORT}" -j ACCEPT
fi

# 输出 Surge 配置
echo
echo "================ trojan-go 安装完成 ================="
echo "域名 (SNI): ${DOMAIN}"
echo "监听: ${LISTEN_ADDR}:${LISTEN_PORT}"
echo "密码: ${PASSWORD}"
echo "证书: ${CRT_PATH}"
echo "私钥: ${KEY_PATH}"
echo "配置文件: ${CONFIG_DIR}/config.json"
echo "日志: ${LOG_FILE}"
echo "服务状态: systemctl status trojan-go -l"
echo
echo "Surge 配置示例（可直接复制到 Surge 的 [Proxy] 节）:"
echo "-----------------------------------------------------"
echo "TrojanProxy = trojan, ${DOMAIN}, ${LISTEN_PORT}, password=${PASSWORD}, sni=${DOMAIN}"
echo "-----------------------------------------------------"
echo
echo "acme.sh 已设置 --reloadcmd 为： ${RELOAD_CMD}"
echo "证书续期时 acme.sh 会执行 reloadcmd 来重启 trojan-go（和 nginx，如果存在）。"
echo "====================================================="