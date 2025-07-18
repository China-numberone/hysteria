#!/bin/bash

# 定义变量
PORT="443"
PASSWORD="123456"
DOMAIN="bing.com"
IPV6=$(ip -6 addr show scope global | grep inet6 | head -n1 | awk '{print $2}' | cut -d'/' -f1)

# 安装 Hysteria2 最新版本
curl -fsSL https://get.hy2.sh  | bash

# 创建配置目录
mkdir -p /etc/hysteria

# 生成自签 TLS 证书（有效期10年）
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout /etc/hysteria/key.pem -out /etc/hysteria/cert.pem \
  -subj "/CN=$DOMAIN"

# 写入配置文件（启用高并发 & 性能优化）
cat > /etc/hysteria/config.yaml <<EOF
listen: "[::]:$PORT"
protocol: udp

auth:
  type: password
  password: $PASSWORD

tls:
  cert: /etc/hysteria/cert.pem
  key: /etc/hysteria/key.pem

masquerade:
  type: proxy
  proxy:
    url: https://www.bilibili.com   
    rewriteHost: true

quic:
  initStreamReceiveWindow: 8388608
  maxStreamReceiveWindow: 33554432
  initConnReceiveWindow: 8388608
  maxConnReceiveWindow: 33554432
  maxIncomingStreams: 1024
  maxIncomingUniStreams: 512

# 可选日志配置
# log:
#   level: info
#   file: /var/log/hysteria.log
EOF

# 写入 systemd 启动服务配置
cat > /etc/systemd/system/hysteria.service <<EOF
[Unit]
Description=Hysteria2 Server
After=network.target

[Service]
ExecStart=/usr/local/bin/hysteria server --config /etc/hysteria/config.yaml
Restart=always
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

# 加载 systemd 服务并启动
systemctl daemon-reload
systemctl enable hysteria
systemctl restart hysteria

# 优化系统内核参数（UDP & 高并发）
cat >> /etc/sysctl.conf <<EOF

# Hysteria2 性能优化参数
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
fs.file-max = 1048576
fs.nr_open = 1048576
net.netfilter.nf_conntrack_max = 262144
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 1024 65000
EOF

# 应用内核参数
sysctl -p

# 提取端口号和认证密码（使用变量已定义，无需再次提取）
# PORT 和 PASSWORD 已定义为变量

# 检查服务状态
systemctl status hysteria --no-pager

# 输出客户端连接信息
echo -e "\n客户端连接信息："
echo "[$IPV6]:$PORT@$PASSWORD"

# 输出状态
echo -e "\n✅ Hysteria2 已部署完毕，使用端口 $PORT，自签 TLS，已开启高并发优化。"
systemctl status hysteria --no-pager
