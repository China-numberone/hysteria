#!/bin/bash

# 安装 Xray
bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)

# 创建配置目录
mkdir -p /usr/local/etc/xray
mkdir -p /etc/ssl/xray

# 生成自签 TLS 证书（有效期10年）
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout /etc/ssl/xray/xray.key -out /etc/ssl/xray/xray.crt \
  -subj "/CN=bing.com"

# 创建 Xray 配置文件（VMess + TLS，监听 443 端口）
cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": {
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log",
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": 443,
      "listen": "::",
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "ba5c7e63-57b6-4511-a6ef-123456789abc",
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "/etc/ssl/xray/xray.crt",
              "keyFile": "/etc/ssl/xray/xray.key"
            }
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
EOF

# 创建 systemd 服务文件（通常安装脚本已创建，以下仅供参考）
cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
After=network.target nss-lookup.target

[Service]
User=root
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=always
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

# 启动服务
systemctl daemon-reload
systemctl enable xray
systemctl restart xray

# 显示服务状态
systemctl status xray
