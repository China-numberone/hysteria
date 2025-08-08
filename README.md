# hysteria
bash <(wget -qO- https://raw.githubusercontent.com/China-numberone/hysteria/main/install_hysteria.sh)

bash <(wget -qO- https://raw.githubusercontent.com/China-numberone/hysteria/main/delete_hysteria_user.sh)

bash <(wget -qO- https://raw.githubusercontent.com/China-numberone/hysteria/main/New_add_hysteria_user.sh)

bash <(wget -qO- https://raw.githubusercontent.com/China-numberone/hysteria/main/limit_check.sh)


# 更新本地文件且运行限额检查
wget -qO /etc/hysteria/limit_check.sh https://raw.githubusercontent.com/China-numberone/hysteria/main/limit_check.sh && bash /etc/hysteria/limit_check.sh
