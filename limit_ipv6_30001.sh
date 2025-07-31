#!/bin/bash
set -e

# === 配置变量 ===
IFACE="eth0"
PORT=30001
RATE="50mbit"
CLASSID="10"
MARK="10"

echo "=== 清除旧规则 ==="
tc qdisc del dev $IFACE root 2>/dev/null || true
tc qdisc del dev $IFACE ingress 2>/dev/null || true
tc qdisc del dev ifb0 root 2>/dev/null || true
ip link set dev ifb0 down 2>/dev/null || true

ip6tables -t mangle -D OUTPUT -p tcp --dport $PORT -j MARK --set-mark $MARK 2>/dev/null || true
ip6tables -t mangle -D OUTPUT -p udp --dport $PORT -j MARK --set-mark $MARK 2>/dev/null || true
ip6tables -t mangle -D INPUT  -p tcp --sport $PORT -j MARK --set-mark $MARK 2>/dev/null || true
ip6tables -t mangle -D INPUT  -p udp --sport $PORT -j MARK --set-mark $MARK 2>/dev/null || true

echo "=== 加载 ifb 模块 ==="
modprobe ifb
ip link set dev ifb0 up

echo "=== ip6tables 打标记 ==="
ip6tables -t mangle -A OUTPUT -p tcp --dport $PORT -j MARK --set-mark $MARK
ip6tables -t mangle -A OUTPUT -p udp --dport $PORT -j MARK --set-mark $MARK
ip6tables -t mangle -A INPUT  -p tcp --sport $PORT -j MARK --set-mark $MARK
ip6tables -t mangle -A INPUT  -p udp --sport $PORT -j MARK --set-mark $MARK

echo "=== 出站限速（egress） ==="
tc qdisc add dev $IFACE root handle 1: htb default 9999
tc class add dev $IFACE parent 1: classid 1:1 htb rate $RATE ceil $RATE
tc class add dev $IFACE parent 1:1 classid 1:$CLASSID htb rate $RATE ceil $RATE
tc filter add dev $IFACE parent 1: protocol ipv6 handle $MARK fw flowid 1:$CLASSID

echo "=== 入站限速（ingress） ==="
tc qdisc add dev $IFACE handle ffff: ingress
tc filter add dev $IFACE parent ffff: protocol ipv6 handle $MARK fw action mirred egress redirect dev ifb0

tc qdisc add dev ifb0 root handle 1: htb default 9999
tc class add dev ifb0 parent 1: classid 1:1 htb rate $RATE ceil $RATE
tc class add dev ifb0 parent 1:1 classid 1:$CLASSID htb rate $RATE ceil $RATE
tc filter add dev ifb0 parent 1: protocol ipv6 handle $MARK fw flowid 1:$CLASSID

echo "✅ 已对 $IFACE IPv6 端口 $PORT 设置上下行限速 $RATE"
