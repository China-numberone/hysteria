#!/bin/bash
MAX_TRIES=3
TRIES=0
VALID_INPUT=0

# 等级信息数组
LEVEL_NAMES=("trial" "basic" "pro" "elite" "vip" "svip")
LEVEL_SIZES=("3GB" "30GB" "100GB" "200GB" "500GB" "1000GB")
LEVEL_DURATIONS=("3day" "30day" "90day" "120day" "365day" "365day")

while [[ $TRIES -lt $MAX_TRIES ]]; do
  echo "请选择用户等级:"
  echo "1) trial（试用） - 3GB / 3天"
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

# 检查并安装 bc
if ! command -v bc >/dev/null 2>&1; then
  echo "$(date '+%F %T'): bc not found, installing..."
  if [ -f /etc/debian_version ]; then
    apt update && apt install -y bc
  elif [ -f /etc/redhat-release ]; then
    yum install -y bc || dnf install -y bc
  elif [ -f /etc/alpine-release ]; then
    apk add --no-cache bc
  else
    echo "Unsupported OS, please manually install bc"
    exit 1
  fi
fi

CONFIG_DIR="/etc/hysteria"
LOG_FILE="/var/log/hysteria_limit.log"
STOP_TIME_DIR="/var/log/hysteria/stop_times"
mkdir -p "$STOP_TIME_DIR"

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

  PORT=$(echo "$INFO" | cut -d',' -f1 | tr -d ' ')
  LIMIT_GB_RAW=$(echo "$INFO" | cut -d',' -f2 | tr -d ' ')
  DURATION_RAW=$(echo "$INFO" | cut -d',' -f3 | tr -d ' ')
  CREATED_RAW=$(echo "$INFO" | cut -d',' -f4 | tr -d ' ')

  LIMIT_GB=$(echo "$LIMIT_GB_RAW" | grep -oP '\d+')
  DURATION_DAYS=$(echo "$DURATION_RAW" | grep -oP '\d+')
  CREATED_DATE=$(echo "$CREATED_RAW" | grep -oP '\d{4}-\d{2}-\d{2}')

  CREATED_TIMESTAMP=$(date -d "$CREATED_DATE" +%s 2>/dev/null)
  
  if [[ -z "$PORT" || -z "$LIMIT_GB" || -z "$DURATION_DAYS" || -z "$CREATED_TIMESTAMP" ]]; then
    echo "$(date): Skipping $config: Missing values (PORT=$PORT, LIMIT=$LIMIT_GB, DAYS=$DURATION_DAYS, CREATED=$CREATED_DATE)" >> "$LOG_FILE"
    continue
  fi

  SERVICE_NAME="hysteria-user$PORT"
  LIMIT_BYTES=$(echo "$LIMIT_GB * 1024 * 1024 * 1024" | bc)
  EXPIRY_TIMESTAMP=$((CREATED_TIMESTAMP + DURATION_DAYS * 86400))

  USED_BYTES_INPUT=$(iptables -nvx -L INPUT | awk -v p=$PORT '$0 ~ "udp" && $0 ~ "dpt:"p {s+=$2} END{printf "%d", s}')
  USED_BYTES_OUTPUT=$(iptables -nvx -L OUTPUT | awk -v p=$PORT '$0 ~ "udp" && $0 ~ "spt:"p {s+=$2} END{printf "%d", s}')
  TOTAL_BYTES=$(echo "$USED_BYTES_INPUT + $USED_BYTES_OUTPUT" | bc)

  USED_GB=$(echo "scale=2; $TOTAL_BYTES / (1024 * 1024 * 1024)" | bc)

  STOP_FILE="$STOP_TIME_DIR/$PORT.stop"

  EXPIRED=false
  REASON=""

  # 如果已有停用时间文件，读取并固定停用时间
  if [ -f "$STOP_FILE" ]; then
    STOP_TIMESTAMP=$(cat "$STOP_FILE")
    # 不重复停用，保持之前停用时间和状态
    EXPIRED=true
    REASON="previously stopped at $(date -d "@$STOP_TIMESTAMP" '+%F %T')"
  else
    if (( $(echo "$TOTAL_BYTES >= $LIMIT_BYTES" | bc -l) )); then
      EXPIRED=true
      REASON="traffic limit exceeded (${USED_GB}GB used / ${LIMIT_GB}GB)"
    fi

    if (( CURRENT_DATE >= EXPIRY_TIMESTAMP )); then
      EXPIRED=true
      REASON="time limit expired"
    fi
  fi

  if [ "$EXPIRED" = true ]; then
    ANY_EXPIRED=true

    if [ ! -f "$STOP_FILE" ]; then
      echo "$CURRENT_DATE" > "$STOP_FILE"
      echo "$(date): Stopping user $SERVICE_NAME (port: $PORT) due to $REASON" >> "$LOG_FILE"

      systemctl stop "$SERVICE_NAME" 2>/dev/null
      systemctl disable "$SERVICE_NAME" 2>/dev/null
      iptables -D INPUT -p udp --dport "$PORT" -j ACCEPT 2>/dev/null
      iptables -D OUTPUT -p udp --sport "$PORT" -j ACCEPT 2>/dev/null
      iptables-save > /etc/iptables/rules.v4 2>/dev/null

      echo "Stopped user on port $PORT due to: $REASON"
    else
      echo "$(date): User $SERVICE_NAME (port: $PORT) already stopped previously at $(date -d "@$STOP_TIMESTAMP" '+%F %T')" >> "$LOG_FILE"
    fi
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
