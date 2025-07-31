#!/bin/bash

IFACE="eth0"
PORT=30001
RATE="50mbit"

# 清理旧规则
tc qdisc del dev $IFACE root 2>/dev/null
tc qdisc del dev $IFACE ingress 2>/dev/null
tc qdisc del dev ifb0 root 2>/dev/null
ip link set dev ifb0 down 2>/dev/null

# 加载 ifb模块并启用ifb0
modprobe ifb
ip link set dev ifb0 up

echo "=== 设置出站限速 ==="
tc qdisc add dev $IFACE root handle 1: htb default 10
tc class add dev $IFACE parent 1: classid 1:1 htb rate $RATE ceil $RATE
tc class add dev $IFACE parent 1:1 classid 1:10 htb rate $RATE ceil $RATE

# 出站过滤：IPv6 tcp/udp目标端口30001流量限速
tc filter add dev $IFACE protocol ipv6 parent 1: prio 1 flower dst_port $PORT ip_proto tcp flowid 1:10
tc filter add dev $IFACE protocol ipv6 parent 1: prio 2 flower dst_port $PORT ip_proto udp flowid 1:10

echo "=== 设置入站限速（通过 ifb0） ==="
# 设置 ingress qdisc，镜像入站流量到 ifb0
tc qdisc add dev $IFACE handle ffff: ingress
tc filter add dev $IFACE parent ffff: protocol ipv6 prio 1 flower src_port $PORT ip_proto tcp action mirred egress redirect dev ifb0
tc filter add dev $IFACE parent ffff: protocol ipv6 prio 2 flower src_port $PORT ip_proto udp action mirred egress redirect dev ifb0

# ifb0 限速设置
tc qdisc add dev ifb0 root handle 1: htb default 10
tc class add dev ifb0 parent 1: classid 1:1 htb rate $RATE ceil $RATE
tc class add dev ifb0 parent 1:1 classid 1:10 htb rate $RATE ceil $RATE

# 过滤 ifb0 入站流量限速
tc filter add dev ifb0 protocol ipv6 parent 1: prio 1 flower src_port $PORT ip_proto tcp flowid 1:10
tc filter add dev ifb0 protocol ipv6 parent 1: prio 2 flower src_port $PORT ip_proto udp flowid 1:10

echo "✅ 限速设置完成: $IFACE 端口 $PORT 上下行限速 $RATE"
