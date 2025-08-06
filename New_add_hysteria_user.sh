#!/bin/bash

# ========== 1. 基本参数 ==========
PORT=$((RANDOM % 40000 + 20000))
USER="user${PORT}"
PASS="${USER}$(tr -dc 'a-z' < /dev/urandom | head -c 5)"
LIMIT_GB=1
LIMIT_BYTES=$((LIMIT_GB * 1024 * 1024 * 1024))

# ========== 2. 写入 Hysteria 配置 ==========
mkdir -p /etc/hysteria

cat > /etc/hysteria/${USER}.yaml <<EOF
listen: '0.0.0.0:$PORT'

auth:
  type: userpass
  userpass:
    $USER: $PASS

tls:
  cert: /etc/hysteria/cert.pem
  key: /etc/hysteria/key.pem

masquerade:
  type: proxy
  proxy:
    url: https://www.bilibili.com
    rewriteHost: true
    protocol: https

quic:
  initStreamReceiveWindow: 1024000
  maxStreamReceiveWindow: 4096000
  initConnReceiveWindow: 1024000
  maxConnReceiveWindow: 4096000
  maxIncomingStreams: 64
  maxIncomingUniStreams: 64
EOF

# ========== 3. 写入 systemd 服务 ==========
cat > /etc/systemd/system/hysteria-${USER}.service <<EOF
[Unit]
Description=Hysteria2 Service for $USER
After=network.target

[Service]
ExecStart=/usr/local/bin/hysteria server --config /etc/hysteria/${USER}.yaml
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# ========== 4. 启动服务 ==========
systemctl daemon-reload
systemctl enable hysteria-${USER}
systemctl start hysteria-${USER}

# ========== 5. 添加 iptables 流量统计规则 ==========
iptables -I INPUT -p udp --dport $PORT -j ACCEPT
iptables -I OUTPUT -p udp --sport $PORT -j ACCEPT

# ========== 6. 创建流量检测脚本 ==========
MONITOR_SCRIPT="/etc/hysteria/limit_check_${USER}.sh"
cat > $MONITOR_SCRIPT <<EOF
#!/bin/bash
PORT=$PORT
USER=$USER
LIMIT_BYTES=$LIMIT_BYTES
SERVICE_NAME=hysteria-\$USER

IN_BYTES=\$(iptables -L INPUT -v -n | grep "udp dpt:\$PORT" | awk '{print \$2}')
OUT_BYTES=\$(iptables -L OUTPUT -v -n | grep "udp spt:\$PORT" | awk '{print \$2}')
TOTAL=\$((IN_BYTES + OUT_BYTES))

if [ "\$TOTAL" -ge "\$LIMIT_BYTES" ]; then
    systemctl stop \$SERVICE_NAME
    systemctl disable \$SERVICE_NAME
    echo "\$(date): \$SERVICE_NAME exceeded limit, stopped." >> /var/log/hysteria_limit.log
fi
EOF

chmod +x $MONITOR_SCRIPT

# ========== 7. 添加定时任务 ==========
CRON_JOB="* * * * * root bash $MONITOR_SCRIPT"
grep -q "$MONITOR_SCRIPT" /etc/crontab || echo "$CRON_JOB" >> /etc/crontab

# ========== 8. 输出连接信息 ==========
IPV4=$(ip -4 addr show scope global | grep inet | head -n1 | awk '{print $2}' | cut -d'/' -f1)

echo -e "\n✅ 已部署 Hysteria2 测试用户"
echo -e "用户名：$USER"
echo -e "端口号：$PORT"
echo -e "密码：$PASS"
echo -e "限额：${LIMIT_GB} GB\n"
echo -e "连接信息："
echo -e "hy2://$USER:$PASS@$IPV4:$PORT?insecure=1&sni=bing.com#Hysteria2-${USER}\n"

systemctl status hysteria-${USER} --no-pager
