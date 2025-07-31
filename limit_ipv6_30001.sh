#!/bin/bash
set -e

IFACE="eth0"
PORT=30001
RATE="50mbit"
CLASSID="10"
MARK=10

echo "=== 检查并安装 ip6tables ==="
if ! command -v ip6tables >/dev/null 2>&1; then
    echo "未检测到 ip6tables，尝试强制安装 iptables..."
    apt-get update -y
    apt-get install -y --force-yes iptables || {
        echo "❌ 安装 iptables 失败，请手动安装。"
        exit 1
    }
fi

echo "=== 清除旧规则 ==="
tc qdisc del dev $IFACE root 2>/dev/null || true
tc qdisc del dev $IFACE ingress 2>/dev/null || true
tc qdisc del dev ifb0 root 2>/dev/null || true
ip link set dev ifb0 down 2>/dev/null || true

ip6tables -t mangle -D OUTPUT -p tcp --dport $PORT -j MARK --set-mark $MARK 2>/dev/null || true
ip6tables -t mangle -D OUTPUT -p udp --dport $PORT -j MARK --set-mark $MARK 2>/dev/null || true
ip6tables -t mangle -D INPUT -p tcp --sport $PORT -j MARK --set-mark $MARK 2>/dev/null || true
ip6tables -t mangle -D INPUT -p udp --sport $PORT -j MARK --set-mark $MARK 2>/dev/null || true

echo "=== 加载 ifb 模块并启用 ==="
modprobe ifb || true
ip link set dev ifb0 up

echo "=== 添加 ip6tables 打标 ==="
ip6tables -t mangle -A OUTPUT -p tcp --dport $PORT -j MARK --set-mark $MARK
ip6tables -t mangle -A OUTPUT -p udp --dport $PORT -j MARK --set-mark $MARK
ip6tables -t mangle -A INPUT -p tcp --sport $PORT -j MARK --set-mark $MARK
ip6tables -t mangle -A INPUT -p udp --sport $PORT -j MARK --set-mark $MARK

echo "=== 设置出站限速 ==="
tc qdisc add dev $IFACE root handle 1: htb default 9999
tc class add dev $IFACE parent 1: classid 1:1 htb rate $RATE ceil $RATE
tc class add dev $IFACE parent 1:1 classid 1:$CLASSID htb rate $RATE ceil $RATE
tc filter add dev $IFACE parent 1:0 protocol ipv6 prio 1 handle $MARK fw flowid 1:$CLASSID

echo "=== 设置入站限速（借助 ifb0）==="
tc qdisc add dev $IFACE handle ffff: ingress
tc filter add dev $IFACE parent ffff: protocol ipv6 prio 1 handle $MARK fw action mirred egress redirect dev ifb0

tc qdisc add dev ifb0 root handle 1: htb default 9999
tc class add dev ifb0 parent 1: classid 1:1 htb rate $RATE ceil $RATE
tc class add dev ifb0 parent 1:1 classid 1:$CLASSID htb rate $RATE ceil $RATE
tc filter add dev ifb0 parent 1:0 protocol ipv6 prio 1 handle $MARK fw flowid 1:$CLASSID

echo "✅ 成功为 IPv6 端口 $PORT 设置上下行限速 $RATE"
