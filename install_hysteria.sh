#!/bin/bash

set -e

# 安装依赖
apt update -y
apt install curl wget unzip -y

# 下载 Hysteria2 最新版
HY2_VERSION=$(curl -s https://api.github.com/repos/apernet/hysteria/releases/latest | grep tag_name | cut -d '"' -f 4)
wget -O hysteria-linux-amd64.tar.gz https://github.com/apernet/hysteria/releases/download/${HY2_VERSION}/hysteria-linux-amd64.tar.gz
tar -xvzf hysteria-linux-amd64.tar.gz -C /usr/local/bin
chmod +x /usr/local/bin/hysteria

# 创建 TLS 自签证书
mkdir -p /etc/hysteria2
openssl req -x509 -newkey rsa:2048 -nodes -keyout /etc/hysteria2/key.pem -out /etc/hysteria2/cert.pem -days 3650 -subj "/CN=bing.com"

# 创建配置文件
cat > /etc/hysteria2/config.yaml << EOF
listen: :5678
protocol: udp
tls:
  cert: /etc/hysteria2/cert.pem
  key: /etc/hysteria2/key.pem
auth:
  type: password
  password: 123456
masquerade:
  type: proxy
  proxy:
    url: https://www.bing.com
    rewriteHost: true
EOF

# 创建 systemd 服务
cat > /etc/systemd/system/hysteria2.service << EOF
[Unit]
Description=Hysteria2 Server
After=network.target

[Service]
ExecStart=/usr/local/bin/hysteria server --config /etc/hysteria2/config.yaml
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

# 启动服务
systemctl daemon-reload
systemctl enable hysteria2
systemctl restart hysteria2

# 输出连接信息
echo "✅ Hysteria2 已安装完成"
echo "➡ IP: $(curl -s ipv4.ip.sb || curl -s ifconfig.me)"
echo "➡ 端口: 5678 (UDP)"
echo "➡ 密码: 123456"
