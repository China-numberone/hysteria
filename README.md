# hysteria
# install_hysteria.sh免下载安装脚本命令
bash <(curl -fsSL https://raw.githubusercontent.com/China-numberone/hysteria/main/install_hysteria.sh)

bash <(wget -qO- https://raw.githubusercontent.com/China-numberone/hysteria/main/install_hysteria.sh)

bash <(wget -qO- https://raw.githubusercontent.com/China-numberone/hysteria/main/add_hysteria_user.sh)

bash <(wget -qO- https://raw.githubusercontent.com/China-numberone/hysteria/main/delete_hysteria_user.sh)

bash <(wget -qO- https://raw.githubusercontent.com/China-numberone/hysteria/main/New_add_hysteria_user.sh)

bash <(wget -qO- https://raw.githubusercontent.com/China-numberone/hysteria/main/limit_check.sh)

wget -qO /etc/hysteria/limit_check.sh https://raw.githubusercontent.com/China-numberone/hysteria/main/limit_check.sh && bash /etc/hysteria/limit_check.sh
