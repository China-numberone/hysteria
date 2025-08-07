#!/bin/bash

# 输入端口
read -p "请输入要删除的端口号: " PORT

# 构建用户名和路径
USER="user${PORT}"
CONF_PATH="/etc/hysteria/${USER}.yaml"
SERVICE_PATH="/etc/systemd/system/hysteria-${USER}.service"

# 检查配置文件是否存在
if [[ ! -f "$CONF_PATH" ]]; then
    echo "❌ 找不到用户配置文件: $CONF_PATH"
    exit 1
fi

# 停止服务
echo "🛑 停止服务 hysteria-${USER} ..."
systemctl stop hysteria-${USER}
systemctl disable hysteria-${USER}

# 删除 iptables 规则
echo "🧹 删除 iptables 规则 ..."
iptables -D INPUT -p udp --dport "$PORT" -j ACCEPT 2>/dev/null
iptables -D OUTPUT -p udp --sport "$PORT" -j ACCEPT 2>/dev/null

# 删除配置文件和服务文件
echo "🧹 删除配置和服务文件 ..."
rm -f "$CONF_PATH"
rm -f "$SERVICE_PATH"

# 重新加载 systemd
systemctl daemon-reload

# 保存 iptables 规则
echo "💾 保存 iptables 规则 ..."
iptables-save > /etc/iptables/rules.v4

echo "✅ 用户 $USER（端口 $PORT）已删除。"
