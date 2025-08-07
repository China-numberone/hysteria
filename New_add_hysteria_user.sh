#!/bin/bash
MAX_TRIES=3
TRIES=0
VALID_INPUT=0

while [[ $TRIES -lt $MAX_TRIES ]]; do
  echo "请选择用户等级:"
  echo "1) trial（试用） - 3GB / 3天"
  echo "2) basic（基础） - 30GB / 30天"
  echo "3) pro（专业）   - 100GB / 90天"
  echo "4) elite（精英） - 200GB / 120天"
  echo "5) vip（尊贵）   - 500GB / 365天"
  echo "6) svip（至尊）  - 1TB / 365天"
  read -rp "请输入等级编号 (1-6): " LEVEL_NUM

  case "$LEVEL_NUM" in
    1)
      LEVEL_NAME="trial"
      LEVEL_SIZE="3GB"
      LEVEL_DURATION="3day"
      VALID_INPUT=1
      break
      ;;
    2)
      LEVEL_NAME="basic"
      LEVEL_SIZE="30GB"
      LEVEL_DURATION="30day"
      VALID_INPUT=1
      break
      ;;
    3)
      LEVEL_NAME="pro"
      LEVEL_SIZE="100GB"
      LEVEL_DURATION="90day"
      VALID_INPUT=1
      break
      ;;
    4)
      LEVEL_NAME="elite"
      LEVEL_SIZE="200GB"
      LEVEL_DURATION="120day"
      VALID_INPUT=1
      break
      ;;
    5)
      LEVEL_NAME="vip"
      LEVEL_SIZE="500GB"
      LEVEL_DURATION="365day"
      VALID_INPUT=1
      break
      ;;
    6)
      LEVEL_NAME="svip"
      LEVEL_SIZE="1000GB"
      LEVEL_DURATION="365day"
      VALID_INPUT=1
      break
      ;;
    *)
      echo "输入无效，请输入 1-6 之间的数字。"
      ((TRIES++))
      ;;
  esac
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
iptables -C INPUT -p udp --dport $PORT -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport $PORT -j ACCEPT
iptables -C OUTPUT -p udp --sport $PORT -j ACCEPT 2>/dev/null || iptables -I OUTPUT -p udp --sport $PORT -j ACCEPT

# ========== 6. 创建流量检测脚本 ==========
MONITOR_SCRIPT="/etc/hysteria/limit_check.sh"
cat > $MONITOR_SCRIPT <<EOF
#!/bin/bash

CONFIG_DIR="/etc/hysteria"
LOG_FILE="/var/log/hysteria_limit.log"
CURRENT_DATE=$(date +%s)
ANY_EXPIRED=false

[ ! -f "$LOG_FILE" ] && touch "$LOG_FILE"
echo "----- $(date) -----" >> "$LOG_FILE"

for config in "$CONFIG_DIR"/user*.yaml; do
    [ ! -f "$config" ] && {
        echo "$(date): Skipping $config: File not found" >> "$LOG_FILE"
        continue
    }

    LEVEL_LINE=$(grep "# level" "$config")
    [[ -z "$LEVEL_LINE" ]] && {
        echo "$(date): Skipping $config: No level comment found" >> "$LOG_FILE"
        continue
    }

    INFO=$(echo "$LEVEL_LINE" | grep -oP '\(.*?\)' | tr -d '()')
    [[ -z "$INFO" ]] && {
        echo "$(date): Skipping $config: Invalid level format ($LEVEL_LINE)" >> "$LOG_FILE"
        continue
    }

    PORT=$(echo "$INFO" | cut -d',' -f1)
    LIMIT_GB_RAW=$(echo "$INFO" | cut -d',' -f2)
    DURATION_RAW=$(echo "$INFO" | cut -d',' -f3)
    CREATED_RAW=$(echo "$INFO" | cut -d',' -f4)

    LIMIT_GB=$(echo "$LIMIT_GB_RAW" | grep -oP '\d+')
    DURATION_DAYS=$(echo "$DURATION_RAW" | grep -oP '\d+')
    CREATED_DATE=$(echo "$CREATED_RAW" | grep -oP '\d{4}-\d{2}-\d{2}')
    CREATED_TIMESTAMP=$(date -d "$CREATED_DATE" +%s 2>/dev/null)

    [[ -z "$PORT" || -z "$LIMIT_GB" || -z "$DURATION_DAYS" || -z "$CREATED_TIMESTAMP" ]] && {
        echo "$(date): Skipping $config: Missing values (PORT=$PORT, LIMIT=$LIMIT_GB, DAYS=$DURATION_DAYS, CREATED=$CREATED_DATE)" >> "$LOG_FILE"
        continue
    }

    SERVICE_NAME="hysteria-user$PORT"
    LIMIT_BYTES=$((LIMIT_GB * 1024 * 1024 * 1024))
    EXPIRY_TIMESTAMP=$((CREATED_TIMESTAMP + DURATION_DAYS * 86400))

    # 计算端口流量（INPUT + OUTPUT）
    USED_BYTES_INPUT=$(iptables -nvx -L INPUT | awk -v p=$PORT '$0 ~ "udp" && $0 ~ "dpt:"p {s+=$2} END{printf "%d", s}')
    USED_BYTES_OUTPUT=$(iptables -nvx -L OUTPUT | awk -v p=$PORT '$0 ~ "udp" && $0 ~ "spt:"p {s+=$2} END{printf "%d", s}')
    TOTAL_BYTES=$((USED_BYTES_INPUT + USED_BYTES_OUTPUT))
    USED_GB=$(awk "BEGIN {printf \"%.2f\", $TOTAL_BYTES / (1024 * 1024 * 1024)}")

    EXPIRED=false
    REASON=""

    if [ "$TOTAL_BYTES" -ge "$LIMIT_BYTES" ]; then
        EXPIRED=true
        REASON="traffic limit exceeded ($USED_GB GB used / ${LIMIT_GB} GB)"
    fi

    if [ "$CURRENT_DATE" -ge "$EXPIRY_TIMESTAMP" ]; then
        EXPIRED=true
        REASON="time limit expired"
    fi

    if [ "$EXPIRED" = true ]; then
        ANY_EXPIRED=true
        systemctl stop "$SERVICE_NAME" 2>/dev/null
        systemctl disable "$SERVICE_NAME" 2>/dev/null
        iptables -D INPUT -p udp --dport "$PORT" -j ACCEPT 2>/dev/null
        iptables -D OUTPUT -p udp --sport "$PORT" -j ACCEPT 2>/dev/null
        iptables-save > /etc/iptables/rules.v4 2>/dev/null
        echo "$(date): ❌ $SERVICE_NAME (port: $PORT) stopped due to $REASON" >> "$LOG_FILE"
        echo "Stopped user on port $PORT due to: $REASON"
    else
        echo "$(date): ✅ $SERVICE_NAME (port: $PORT) usage OK: ${USED_GB}GB / ${LIMIT_GB}GB" >> "$LOG_FILE"
        echo "User on port $PORT: ${USED_GB}GB / ${LIMIT_GB}GB - OK"
    fi
done

if [ "$ANY_EXPIRED" = false ]; then
    echo "$(date): No ports expired" >> "$LOG_FILE"
fi


EOF

chmod +x /etc/hysteria/limit_check.sh

# ========== 7. 添加定时任务 grep CRON /var/log/syslog | grep limit_check.sh ==========
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
