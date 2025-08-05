#!/bin/bash

# 随机端口（20000-59999）
PORT=$((RANDOM % 40000 + 20000))

# 用户名 = user + 端口
USER="user${PORT}"

# 密码 = 用户名 + 随机5位小写字母
PASS="${USER}$(tr -dc 'a-z' < /dev/urandom | head -c 5)"

# 写入配置文件
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
  initStreamReceiveWindow: 512000
  maxStreamReceiveWindow: 1536000
  initConnReceiveWindow: 512000
  maxConnReceiveWindow: 1536000
  maxIncomingStreams: 32
  maxIncomingUniStreams: 32
EOF

# 写入 systemd 服务文件
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

# 启动服务
systemctl daemon-reload
systemctl enable hysteria-${USER}
systemctl restart hysteria-${USER}

# 获取公网 IPv4 地址
IPV4=$(ip -4 addr show scope global | grep inet | head -n1 | awk '{print $2}' | cut -d'/' -f1)

PASSWORD=$(awk '/userpass:/ {in_userpass=1; next} /^[^[:space:]]/ {in_userpass=0} in_userpass && /^[[:space:]]*[a-zA-Z0-9_-]+:[[:space:]]*/ { gsub(/^[ \t]+/, "", $0); last=$0 } END { gsub(/[[:space:]]+/, "", last); print last }' /etc/hysteria/${USER}.yaml)

# 输出连接信息
echo -e "\n✅ Hysteria2 用户 $USER 部署完成，端口 $PORT"
echo -e "\n连接信息：\nhy2://$PASSWORD@$IPV4:$PORT?insecure=1&sni=bing.com#Hysteria2-$USER-$IPV4"

# 显示 systemd 状态
echo -e "\n服务状态："
systemctl status hysteria-${USER} --no-pager
