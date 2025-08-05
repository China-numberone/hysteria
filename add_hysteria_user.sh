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
  initStreamReceiveWindow: 1024000
  maxStreamReceiveWindow: 4096000
  initConnReceiveWindow: 1024000
  maxConnReceiveWindow: 4096000
  maxIncomingStreams: 64
  maxIncomingUniStreams: 64
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

# 输出连接信息
echo -e "\n✅ Hysteria2 用户 $USER 部署完成，端口 $PORT"
echo -e "\n连接信息：\nhy2://$USER:$PASS@$IPV4:$PORT?insecure=1&sni=bing.com#Hysteria2-$USER-$IPV4"

# 显示 systemd 状态
echo -e "\n服务状态："
systemctl status hysteria-${USER} --no-pager
