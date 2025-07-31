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

listen: '[::]:443'  # 监听 IPv4 + IPv6

auth:
  type: userpass
  userpass:
    main: abc123a
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
  initStreamReceiveWindow: 2048000
  maxStreamReceiveWindow: 6144000
  initConnReceiveWindow: 2048000
  maxConnReceiveWindow: 6144000
  maxIncomingStreams: 128
  maxIncomingUniStreams: 128
  
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
CPUSchedulingPolicy=rr
CPUSchedulingPriority=10
CPUAffinity=0-3

[Install]
WantedBy=multi-user.target

EOF

# 加载 systemd 服务并启动
systemctl daemon-reload
systemctl enable hysteria
systemctl restart hysteria

# 优化系统内核参数（UDP & 高并发）
cat >> /etc/sysctl.conf <<EOF

fs.file-max = 65536
fs.nr_open = 65536
net.netfilter.nf_conntrack_max = 16384

# IPv6转发开启
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.default.forwarding = 1

# IPv6邻居缓存阈值，防止邻居缓存表溢出
net.ipv6.neigh.default.gc_thresh1 = 1024
net.ipv6.neigh.default.gc_thresh2 = 2048
net.ipv6.neigh.default.gc_thresh3 = 4096

# IPv6 ICMP 限速
net.ipv6.icmp.ratelimit = 1000

# UDP 网络缓冲区提升，减少丢包
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.rmem_default = 262144
net.core.wmem_default = 262144

# 网络接收队列长度
net.core.netdev_max_backlog = 5000

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
echo -e "\n✅ Hysteria2 已部署完毕，使用端口 443，自签 TLS，已开启高并发优化。"
systemctl status hysteria --no-pager

