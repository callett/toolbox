#!/usr/bin/env bash
#
# Nacos 一键安装脚本 (Ubuntu)
# 支持: amd64 / arm64 架构自动识别
# 支持: 自动获取 GitHub 最新版本，或通过环境变量 NACOS_VERSION 指定版本
#
# 用法:
#   sudo bash install_nacos.sh                 # 安装最新版
#   sudo NACOS_VERSION=2.3.2 bash install_nacos.sh   # 安装指定版本
#
set -euo pipefail

# ------------------- 基础检查 -------------------
if [[ $EUID -ne 0 ]]; then
  echo "请使用 root 或 sudo 运行本脚本" >&2
  exit 1
fi

if ! grep -qi ubuntu /etc/os-release 2>/dev/null; then
  echo "警告: 未检测到 Ubuntu 系统，脚本仍会尝试继续执行..." >&2
fi

# ------------------- 参数 -------------------
NACOS_HOME="/opt/nacos"
NACOS_USER="nacos"
NACOS_MODE="${NACOS_MODE:-standalone}"     # standalone(单机) / cluster(集群，需自行配置cluster.conf)
NACOS_PORT="${NACOS_PORT:-8848}"
NACOS_VERSION="${NACOS_VERSION:-}"          # 不指定则自动获取最新版
JDK_PACKAGE="openjdk-17-jdk"
GITHUB_API="https://api.github.com/repos/alibaba/nacos/releases/latest"

# ------------------- 架构识别 -------------------
ARCH_RAW="$(uname -m)"
case "$ARCH_RAW" in
  x86_64|amd64)
    ARCH="amd64"
    JDK_ARCH="x64"
    ;;
  aarch64|arm64)
    ARCH="arm64"
    JDK_ARCH="aarch64"
    ;;
  *)
    echo "不支持的架构: $ARCH_RAW" >&2
    exit 1
    ;;
esac
echo ">>> 检测到系统架构: $ARCH_RAW -> $ARCH"

# ------------------- 安装基础依赖 (curl/wget/tar) -------------------
echo ">>> 更新软件源并安装基础依赖 (curl, wget, tar) ..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y curl wget tar

# ------------------- 检查系统 JDK -------------------
# Nacos 要求 JDK 版本 >= 8 (推荐 11/17)，此处最低要求设为 8
MIN_JAVA_VERSION=8
NEED_INSTALL_JDK=true

check_java_version() {
  local java_bin="$1"
  local ver_str
  ver_str="$("$java_bin" -version 2>&1 | head -n1 | grep -oP '"\K[^"]+')"
  [[ -z "$ver_str" ]] && return 1

  # 处理 "1.8.0_xxx" 与 "17.0.x" 两种版本号格式
  local major
  if [[ "$ver_str" == 1.* ]]; then
    major="$(echo "$ver_str" | cut -d. -f2)"
  else
    major="$(echo "$ver_str" | cut -d. -f1)"
  fi

  if [[ "$major" =~ ^[0-9]+$ ]] && [[ "$major" -ge "$MIN_JAVA_VERSION" ]]; then
    echo "$ver_str"
    return 0
  fi
  return 1
}

if command -v java &>/dev/null; then
  if EXISTING_VER="$(check_java_version java)"; then
    echo ">>> 检测到系统已安装 Java，版本: ${EXISTING_VER}，满足 Nacos 运行要求(>= ${MIN_JAVA_VERSION})，跳过 JDK 安装"
    NEED_INSTALL_JDK=false
  else
    echo ">>> 检测到系统已安装 Java，但版本过低(不满足 >= ${MIN_JAVA_VERSION})，将安装 ${JDK_PACKAGE}"
  fi
else
  echo ">>> 未检测到系统 Java，将安装 ${JDK_PACKAGE}"
fi

if [[ "$NEED_INSTALL_JDK" == true ]]; then
  # apt 会根据系统架构 (amd64/arm64) 自动安装匹配的 JDK 包，无需额外区分
  apt-get install -y "${JDK_PACKAGE}"
fi

java -version

# ------------------- 获取最新版本号 -------------------
if [[ -z "$NACOS_VERSION" ]]; then
  echo ">>> 未指定 NACOS_VERSION，正在从 GitHub 获取最新版本号..."
  NACOS_VERSION="$(curl -fsSL "$GITHUB_API" | grep -oP '"tag_name":\s*"\K[^"]+' | sed 's/^v//')"
  if [[ -z "$NACOS_VERSION" ]]; then
    echo "获取最新版本失败，请通过 NACOS_VERSION 环境变量手动指定版本号" >&2
    exit 1
  fi
fi
echo ">>> 将安装 Nacos 版本: v${NACOS_VERSION}"

# ------------------- 下载 Nacos -------------------
# Nacos 发行包为 Java 通用包（不区分 CPU 架构），此处架构识别主要用于
# 保证 JDK 安装正确以及未来可能出现架构专属包时的扩展点。
DOWNLOAD_URL="https://github.com/alibaba/nacos/releases/download/${NACOS_VERSION}/nacos-server-${NACOS_VERSION}.tar.gz"
TMP_TAR="/tmp/nacos-server-${NACOS_VERSION}.tar.gz"

echo ">>> 下载地址: $DOWNLOAD_URL"
if ! wget -q --show-progress -O "$TMP_TAR" "$DOWNLOAD_URL"; then
  echo "下载失败，请检查版本号 ${NACOS_VERSION} 是否存在，或网络是否可访问 GitHub" >&2
  exit 1
fi

# ------------------- 创建用户 -------------------
if ! id "$NACOS_USER" &>/dev/null; then
  echo ">>> 创建运行用户: $NACOS_USER"
  useradd -r -m -s /usr/sbin/nologin "$NACOS_USER"
fi

# ------------------- 解压安装 -------------------
echo ">>> 安装到 $NACOS_HOME"
rm -rf "$NACOS_HOME"
mkdir -p "$NACOS_HOME"
tar -zxf "$TMP_TAR" -C /opt/
# 官方压缩包解压后目录名为 nacos
if [[ -d /opt/nacos && "$NACOS_HOME" != "/opt/nacos" ]]; then
  mv /opt/nacos "$NACOS_HOME"
fi
rm -f "$TMP_TAR"

chown -R "$NACOS_USER":"$NACOS_USER" "$NACOS_HOME"

# ------------------- 单机模式基础配置 -------------------
CONF_FILE="${NACOS_HOME}/conf/application.properties"
if [[ -f "$CONF_FILE" ]]; then
  # 设置端口
  if grep -q "^server.port=" "$CONF_FILE"; then
    sed -i "s/^server.port=.*/server.port=${NACOS_PORT}/" "$CONF_FILE"
  else
    echo "server.port=${NACOS_PORT}" >> "$CONF_FILE"
  fi
fi

# ------------------- systemd 服务 -------------------
SERVICE_FILE="/etc/systemd/system/nacos.service"
echo ">>> 写入 systemd 服务文件: $SERVICE_FILE"

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Nacos Server (${NACOS_MODE} mode, arch: ${ARCH})
After=network.target

[Service]
Type=forking
User=${NACOS_USER}
Group=${NACOS_USER}
Environment=MODE=${NACOS_MODE}
Environment=JAVA_HOME=$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")
ExecStart=${NACOS_HOME}/bin/startup.sh -m ${NACOS_MODE}
ExecStop=${NACOS_HOME}/bin/shutdown.sh
Restart=on-failure
RestartSec=10
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable nacos.service
systemctl restart nacos.service

# ------------------- 结果检查 -------------------
echo ">>> 等待 Nacos 启动 (约15秒)..."
sleep 15

if systemctl is-active --quiet nacos.service; then
  IP_ADDR="$(hostname -I 2>/dev/null | awk '{print $1}')"
  echo "=================================================="
  echo " Nacos 安装成功！"
  echo " 版本      : v${NACOS_VERSION}"
  echo " 架构      : ${ARCH_RAW} (${ARCH})"
  echo " 模式      : ${NACOS_MODE}"
  echo " 安装路径  : ${NACOS_HOME}"
  echo " 控制台地址: http://${IP_ADDR:-<服务器IP>}:${NACOS_PORT}/nacos"
  echo " 默认账号  : nacos / nacos"
  echo " 服务管理  : systemctl [start|stop|restart|status] nacos"
  echo " 日志目录  : ${NACOS_HOME}/logs"
  echo "=================================================="
else
  echo "Nacos 服务未能正常启动，请查看日志排查:"
  echo "  journalctl -u nacos -f"
  echo "  tail -f ${NACOS_HOME}/logs/start.out"
  exit 1
fi
