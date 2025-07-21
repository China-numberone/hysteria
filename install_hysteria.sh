#!/bin/bash

# 安装 Hysteria2 最新版本
curl -fsSL https://get.hy2.sh | bash

# 创建配置目录
mkdir -p /etc/hysteria

# 生成自签 TLS 证书（有效期10年）
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout /etc/hysteria/key.pem -out /etc/hysteria/cert.pem \
  -subj "/CN=bing.com"

# 写入配置文件（启用高并发 & 性能优化）
cat > /etc/hysteria/config.yaml <<EOF
listen: '[::]:443'
protocol: udp

auth:
  type: password
  password: 123456

tls:
  cert: /etc/hysteria/cert.pem
  key: /etc/hysteria/key.pem

masquerade:
  type: proxy
  proxy:
    url: https://www.bilibili.com
    rewriteHost: true

quic:
  initStreamReceiveWindow: 2097152       # 2MB
  maxStreamReceiveWindow: 4194304        # 4MB
  initConnReceiveWindow: 4194304         # 4MB
  maxConnReceiveWindow: 8388608          # 8MB
  maxIncomingStreams: 128
  maxIncomingUniStreams: 64

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
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

# 加载 systemd 服务并启动
systemctl daemon-reload
systemctl enable hysteria
systemctl restart hysteria

# 优化系统内核参数（UDP & 高并发）
cat >> /etc/sysctl.conf <<EOF

net.core.rmem_max = 8388608
net.core.wmem_max = 8388608
fs.file-max = 131072
fs.nr_open = 131072
net.netfilter.nf_conntrack_max = 32768
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 1024 65000

# IPv6 优化参数
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.default.forwarding = 1
net.ipv6.neigh.default.gc_thresh1 = 1024
net.ipv6.neigh.default.gc_thresh2 = 2048
net.ipv6.neigh.default.gc_thresh3 = 4096
net.ipv6.icmp.ratelimit = 1000
net.ipv6.route.flush = 1
EOF

# 应用内核参数
sysctl -p

# 提取 IPv6 地址（取第一个全局 IPv6）
IPV6=$(ip -6 addr show scope global | grep inet6 | head -n1 | awk '{print $2}' | cut -d'/' -f1)

# 提取端口号
PORT=$(grep '^listen:' /etc/hysteria/config.yaml | awk -F: '{print $NF}' | tr -d ' ')

# 提取认证密码
PASSWORD=$(awk '/^auth:/,/^$/{if($1=="password:"){print $2}}' /etc/hysteria/config.yaml)

systemctl status hysteria --no-pager

# 拼接输出
echo -e "\n客户端连接信息："
echo "[$IPV6]:$PORT@$PASSWORD"

# 输出状态

# 输出状态
echo -e "\n✅ Hysteria2 已部署完毕，使用端口 443，自签 TLS，已开启高并发优化。"
systemctl status hysteria --no-pager

