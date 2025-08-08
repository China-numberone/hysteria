# ========== 6. 创建流量检测脚本 ==========
MONITOR_SCRIPT="/etc/hysteria/limit_check.sh"
cat > $MONITOR_SCRIPT <<EOF
#!/bin/bash

set -eo pipefail

# ---------- 检测并安装 bc ----------
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
    echo "$CURRENT_DATE: Skipping $config: Missing values (PORT=$PORT, LIMIT=$LIMIT_GB, DAYS=$DURATION_DAYS, CREATED=$CREATED_DATE)" >> "$LOG_FILE"
    continue
  fi

  SERVICE_NAME="hysteria-user$PORT"
  LIMIT_BYTES=$(echo "$LIMIT_GB * 1024 * 1024 * 1024" | bc)
  EXPIRY_TIMESTAMP=$((CREATED_TIMESTAMP + DURATION_DAYS * 86400))

  USED_BYTES_INPUT=$(iptables -nvx -L INPUT | awk -v p=$PORT '$0 ~ "udp" && $0 ~ "dpt:"p {s+=$2} END{printf "%d", s}')
  USED_BYTES_OUTPUT=$(iptables -nvx -L OUTPUT | awk -v p=$PORT '$0 ~ "udp" && $0 ~ "spt:"p {s+=$2} END{printf "%d", s}')
  TOTAL_BYTES=$(echo "$USED_BYTES_INPUT + $USED_BYTES_OUTPUT" | bc)

  USED_GB=$(echo "scale=2; $TOTAL_BYTES / (1024 * 1024 * 1024)" | bc)

  EXPIRED=false
  REASON=""

  if (( $(echo "$TOTAL_BYTES >= $LIMIT_BYTES" | bc -l) )); then
    EXPIRED=true
    REASON="traffic limit exceeded (${USED_GB}GB used / ${LIMIT_GB}GB)"
  fi

  if (( CURRENT_DATE >= EXPIRY_TIMESTAMP )); then
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
    echo "$CURRENT_DATE: ❌ $SERVICE_NAME (port: $PORT) stopped due to $REASON" >> "$LOG_FILE"
    echo "Stopped user on port $PORT due to: $REASON"
  else
    echo "$CURRENT_DATE: ✅ $SERVICE_NAME (port: $PORT) usage OK: ${USED_GB}GB / ${LIMIT_GB}GB" >> "$LOG_FILE"
    echo "User on port $PORT: ${USED_GB}GB / ${LIMIT_GB}GB - OK"
  fi
done

if [ "$ANY_EXPIRED" = false ]; then
  echo "$CURRENT_DATE: No ports expired" >> "$LOG_FILE"
fi

EOF

chmod +x /etc/hysteria/limit_check.sh

# ========== 7. 添加定时任务 grep CRON /var/log/syslog | grep limit_check.sh ==========
CRON_JOB="* * * * * root bash $MONITOR_SCRIPT"
grep -q "$MONITOR_SCRIPT" /etc/crontab || echo "$CRON_JOB" >> /etc/crontab
