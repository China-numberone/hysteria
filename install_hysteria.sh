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

[Install]
WantedBy=multi-user.target

EOF

# 加载 systemd 服务并启动
systemctl daemon-reload
systemctl enable hysteria
systemctl restart hysteria

cat >> /etc/sysctl.conf <<EOF

# 文件描述符限制（建议更大，适配高并发）
fs.file-max = 1048576
fs.nr_open = 1048576

# 连接跟踪表大小（适用于代理、NAT 等）
net.netfilter.nf_conntrack_max = 262144

# IPv6 转发和邻居表优化
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.default.forwarding = 1
net.ipv6.neigh.default.gc_thresh1 = 1024
net.ipv6.neigh.default.gc_thresh2 = 2048
net.ipv6.neigh.default.gc_thresh3 = 4096
net.ipv6.icmp.ratelimit = 1000

# IPv4 网络优化参数

net.ipv4.ip_forward = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_tw_recycle = 0

# TCP 内存和缓冲区优化
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# 可用端口范围扩大
net.ipv4.ip_local_port_range = 10240 65535

# 接收队列长度
net.core.netdev_max_backlog = 5000

EOF

# 应用内核参数
sysctl -p

# 提取 IPv6 地址（取第一个全局 IPv6）
IPV6=$(ip -6 addr show scope global | grep inet6 | head -n1 | awk '{print $2}' | cut -d'/' -f1)

# 提取第一个全局 IPv4 地址
IPV4=$(ip -4 addr show scope global | grep inet | head -n1 | awk '{print $2}' | cut -d'/' -f1)

# 提取端口号
PORT=$(grep '^listen:' /etc/hysteria/config.yaml | sed -E 's/.*\]:([0-9]+).*$/\1/')

# 提取认证密码
# PASSWORD=$(awk '/^auth:/,/^$/{if($1=="userpass:"){print $2}}' /etc/hysteria/config.yaml)
PASSWORD=$(awk '/userpass:/ {flag=1; next} /^[^ ]/ {flag=0} flag && /^[[:space:]]+[a-zA-Z0-9_-]+: /' /etc/hysteria/config.yaml)

systemctl status hysteria --no-pager

# 拼接输出
#echo "[$IPV6]:$PORT@$PASSWORD"
echo -e "\n客户端连接信息：\nhy2://$PASSWORD@[$IPV6]:$PORT?insecure=1&sni=bing.com#Hysteria2-IPv6"

echo -e "\n客户端连接信息：\nhy2://$PASSWORD@[$IPV4]:$PORT?insecure=1&sni=bing.com#Hysteria2-IPv6"

# 输出状态
echo -e "\n✅ Hysteria2 已部署完毕，使用端口 443，自签 TLS，已开启高并发优化。"
systemctl status hysteria --no-pager

