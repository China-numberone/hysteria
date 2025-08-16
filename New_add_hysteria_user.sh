#!/bin/bash
MAX_TRIES=3
TRIES=0
VALID_INPUT=0

# 等级信息数组
LEVEL_NAMES=("trial" "basic" "pro" "elite" "vip" "svip")
LEVEL_SIZES=("1GB" "30GB" "100GB" "200GB" "500GB" "1000GB")
LEVEL_DURATIONS=("1day" "30day" "90day" "120day" "365day" "365day")

while [[ $TRIES -lt $MAX_TRIES ]]; do
  echo "请选择用户等级:"
  echo "1) trial（试用） - 1GB / 1天"
  echo "2) basic（基础） - 30GB / 30天"
  echo "3) pro（专业）   - 100GB / 90天"
  echo "4) elite（精英） - 200GB / 120天"
  echo "5) vip（尊贵）   - 500GB / 365天"
  echo "6) svip（至尊）  - 1TB / 365天"
  read -rp "请输入等级编号 (1-6): " LEVEL_NUM

  if [[ "$LEVEL_NUM" =~ ^[1-6]$ ]]; then
    INDEX=$((LEVEL_NUM - 1))
    LEVEL_NAME="${LEVEL_NAMES[$INDEX]}"
    LEVEL_SIZE="${LEVEL_SIZES[$INDEX]}"
    LEVEL_DURATION="${LEVEL_DURATIONS[$INDEX]}"
    VALID_INPUT=1
    break
  else
    echo "输入无效，请输入 1-6 之间的数字。"
    ((TRIES++))
  fi
done

if [[ $VALID_INPUT -ne 1 ]]; then
  echo "输入无效超过三次，退出本次用户生成。"
  exit 1
fi

CREATED_DATE=$(date +%Y-%m-%d)

# ========== 1. 基本参数 ==========
PORT=$((RANDOM % 40000 + 20000))
USER="user${PORT}"
PASS="${USER}$(tr -dc 'a-z' < /dev/urandom | head -c 5)"

LEVEL_COMMENT="# level: $LEVEL_NAME (${PORT},$LEVEL_SIZE, $LEVEL_DURATION, created: $CREATED_DATE)"
# ========== 2. 写入 Hysteria 配置 ==========
mkdir -p /etc/hysteria

cat > /etc/hysteria/${USER}.yaml <<EOF
$LEVEL_COMMENT

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
    url: https://www.bing.com
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
iptables -C INPUT -p udp --dport $PORT -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport $PORT -j ACCEPT
iptables -C OUTPUT -p udp --sport $PORT -j ACCEPT 2>/dev/null || iptables -I OUTPUT -p udp --sport $PORT -j ACCEPT

# ========== 8. 输出连接信息 ==========
IPV4=$(ip -4 addr show scope global | grep inet | head -n1 | awk '{print $2}' | cut -d'/' -f1)

echo -e "\n✅ 已部署 Hysteria2 测试用户"
echo -e "连接信息："
echo -e "hy2://$USER:$PASS@$IPV4:$PORT?insecure=1&sni=bing.com#$LEVEL_COMMENT\n"

systemctl status hysteria-${USER} --no-pager
