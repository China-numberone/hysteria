#!/bin/bash

# 用户名与端口配置
USER_NAME="user123"
PORT="30001"
PASSWORD="abc123user123"
CONFIG_PATH="/etc/hysteria/${USER_NAME}.yaml"
SERVICE_PATH="/etc/systemd/system/hysteria-${USER_NAME}.service"

# 写入独立用户配置
cat > "$CONFIG_PATH" <<EOF
listen: '[::]:$PORT'

auth:
  type: userpass
  userpass:
    $USER_NAME: $PASSWORD

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
  initStreamReceiveWindow: 512000      # 0.5MB
  maxStreamReceiveWindow: 1536000      # 1.5MB
  initConnReceiveWindow: 512000        # 0.5MB
  maxConnReceiveWindow: 1536000        # 1.5MB
  maxIncomingStreams: 32
  maxIncomingUniStreams: 32
EOF

# 写入 systemd 服务
cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=Hysteria2 $USER_NAME Service
After=network.target

[Service]
ExecStart=/usr/local/bin/hysteria server --config $CONFIG_PATH
Restart=always
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

# 启动服务
systemctl daemon-reload
systemctl enable hysteria-${USER_NAME}
systemctl restart hysteria-${USER_NAME}

# 获取 IPv6 地址（第一个全局地址）
IPV6=$(ip -6 addr show scope global | grep inet6 | head -n1 | awk '{print $2}' | cut -d'/' -f1)

# 输出客户端连接信息
echo -e "\n客户端连接信息：\nhy2://$PASSWORD@[$IPV6]:$PORT?insecure=1&sni=bing.com#Hysteria2-IPv6"

# 状态反馈
echo -e "\n✅ 用户 $USER_NAME 的 Hysteria2 服务已部署，监听端口 $PORT。"
systemctl status hysteria-${USER_NAME} --no-pager
