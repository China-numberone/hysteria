#!/bin/bash
set -e

# 变量定义
IFACE="eth0"
PORT=30001
RATE="50mbit"
CLASSID="10"
MARK=10

echo "=== 检查 ip6tables 是否存在 ==="
if ! command -v ip6tables >/dev/null 2>&1; then
    echo "未安装 ip6tables，正在尝试安装..."
    apt update && apt install -y iptables || {
        echo "❌ 安装 ip6tables 失败，请手动安装后重试。"
        exit 1
    }
fi

# 清理旧规则
echo "=== 清除旧的限速规则 ==="
tc qdisc del dev $IFACE root 2>/dev/null || true
tc qdisc del dev $IFACE ingress 2>/dev/null || true
tc qdisc del dev ifb0 root 2>/dev/null || true
ip link set dev ifb0 down 2>/dev/null || true

ip6tables -t mangle -D OUTPUT -p tcp --dport $PORT -j MARK --set-mark $MARK 2>/dev/null || true
ip6tables -t mangle -D OUTPUT -p udp --dport $PORT -j MARK --set-mark $MARK 2>/dev/null || true
ip6tables -t mangle -D INPUT -p tcp --sport $PORT -j MARK --set-mark $MARK 2>/dev/null || true
ip6tables -t mangle -D INPUT -p udp --sport $PORT -j MARK --set-mark $MARK 2>/dev/null || true

# 加载 ifb 模块并启用
echo "=== 启用 ifb0 设备 ==="
modprobe ifb || true
ip link set dev ifb0 up

# 添加 ip6tables 打标
echo "=== 添加 ip6tables 端口打标规则 ==="
ip6tables -t mangle -A OUTPUT -p tcp --dport $PORT -j MARK --set-mark $MARK
ip6tables -t mangle -A OUTPUT -p udp --dport $PORT -j MARK --set-mark $MARK
ip6tables -t mangle -A INPUT -p tcp --sport $PORT -j MARK --set-mark $MARK
ip6tables -t mangle -A INPUT -p udp --sport $PORT -j MARK --set-mark $MARK

# 设置出站限速
echo "=== 设置出站限速 ==="
tc qdisc add dev $IFACE root handle 1: htb default 9999
tc class add dev $IFACE parent 1: classid 1:1 htb rate $RATE ceil $RATE
tc class add dev $IFACE parent 1:1 classid 1:$CLASSID htb rate $RATE ceil $RATE
tc filter add dev $IFACE parent 1:0 protocol ipv6 prio 1 handle $MARK fw flowid 1:$CLASSID

# 设置入站限速
echo "=== 设置入站限速 ==="
tc qdisc add dev $IFACE handle ffff: ingress
tc filter add dev $IFACE parent ffff: protocol ipv6 prio 1 handle $MARK fw action mirred egress redirect dev ifb0

tc qdisc add dev ifb0 root handle 1: htb default 9999
tc class add dev ifb0 parent 1: classid 1:1 htb rate $RATE ceil $RATE
tc class add dev ifb0 parent 1:1 classid 1:$CLASSID htb rate $RATE ceil $RATE
tc filter add dev ifb0 parent 1:0 protocol ipv6 prio 1 handle $MARK fw flowid 1:$CLASSID

echo "✅ 已成功为接口 $IFACE 设置 IPv6 端口 $PORT 上下行限速 $RATE"
