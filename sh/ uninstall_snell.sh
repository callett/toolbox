#!/bin/bash

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # 没颜色

set -e

echo -e "${GREEN}==========================${NC}"
echo -e "${GREEN}Snell Proxy 卸载脚本${NC}"
echo -e "${GREEN}==========================${NC}"

# 停止并禁用服务
if systemctl list-units --full -all | grep -q "snell.service"; then
    echo -e "${GREEN}停止 Snell 服务...${NC}"
    systemctl stop snell
    systemctl disable snell
    systemctl daemon-reload
    echo -e "${GREEN}服务已停止并禁用.${NC}"
else
    echo -e "${RED}未检测到 snell.service 服务，跳过服务停止.${NC}"
fi

# 删除 systemd 服务文件
if [ -f /lib/systemd/system/snell.service ]; then
    echo -e "${GREEN}删除 systemd 服务文件...${NC}"
    rm -f /lib/systemd/system/snell.service
    echo -e "${GREEN}systemd 服务文件已删除.${NC}"
fi

# 删除 Snell 二进制文件
if [ -f /usr/local/bin/snell-server ]; then
    echo -e "${GREEN}删除 Snell 二进制文件...${NC}"
    rm -f /usr/local/bin/snell-server
    echo -e "${GREEN}二进制文件已删除.${NC}"
fi

# 删除配置文件和目录
if [ -d /etc/snell ]; then
    echo -e "${GREEN}删除配置文件和目录...${NC}"
    rm -rf /etc/snell
    echo -e "${GREEN}配置文件已删除.${NC}"
fi

echo -e "${GREEN}==========================${NC}"
echo -e "${GREEN}Snell Proxy 已完全卸载.${NC}"
echo -e "${GREEN}==========================${NC}"