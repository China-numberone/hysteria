
#!/bin/bash

set -e

# 安装依赖
apt update && apt install -y curl unzip jq

# 下载最新版本 sing-box
latest=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | jq -r '.tag_name')
url="https://github.com/SagerNet/sing-box/releases/download/${latest}/sing-box-${latest}-linux-amd64.zip"

mkdir -p /opt/sing-box
cd /opt/sing-box
curl -LO "$url"
unzip "sing-box-${latest}-linux-amd64.zip"
chmod +x sing-box
mv sing-box /usr/local/bin/sing-box

# 生成私钥和公钥
mkdir -p /etc/sing-box
cd /etc/sing-box
sing-box generate reality-keypair > keypair.json
private_key=$(jq -r .private_key keypair.json)
public_key=$(jq -r .public_key keypair.json)

# 生成UUID
uuid=$(cat /proc/sys/kernel/random/uuid)

# 设置SNI（你也可以改成别的合法站点）
server_name="www.cloudflare.com"
short_id=$(openssl rand -hex 8)

# 写入配置文件
cat > /etc/sing-box/config.json <<EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "in-reality",
      "listen": "::",
      "listen_port": 443,
      "users": [
        {
          "uuid": "$uuid",
          "flow": ""
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "$server_name",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "$server_name",
            "server_port": 443
          },
          "private_key": "$private_key",
          "short_id": ["$short_id"]
        }
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct"
    }
  ]
}
EOF

# 创建 systemd 服务
cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
Description=sing-box service
After=network.target

[Service]
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# 启动并设置开机启动
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable sing-box
systemctl start sing-box

# 输出信息
echo -e "\n✅ Reality 安装完成"
echo "--------------------------------"
echo "UUID:           $uuid"
echo "Public Key:     $public_key"
echo "Short ID:       $short_id"
echo "SNI:            $server_name"
echo "端口:           443"
echo "传输层:         Reality (VLESS over TCP)"
echo "--------------------------------"
