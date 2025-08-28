#!/usr/bin/env bash
# Fail2ban-easy 管理脚本 (systemd backend)
# 功能：安装/配置/启停/重启/日志/黑名单/查看/修改配置/导出/清空/删除/更新

JAIL_FILE="/etc/fail2ban/jail.local"
SCRIPT_FILE="/usr/local/bin/fail2ban-easy"
SCRIPT_URL="https://raw.githubusercontent.com/Lanlan13-14/Fail2ban-easy/refs/heads/main/fail2ban.sh"

check_fail2ban() {
    if ! command -v fail2ban-client &>/dev/null; then
        echo "⚠️ Fail2ban 未安装，请先选择 [1] 安装。"
        return 1
    fi
    return 0
}

install_fail2ban() {
    echo "🚀 安装 Fail2ban..."
    sudo apt update && sudo apt install -y fail2ban python3-systemd python3-sqlite3
    sudo systemctl enable fail2ban
    echo "✅ 安装完成"
}

configure_fail2ban() {
    if ! check_fail2ban; then return; fi
    if [ -f "$JAIL_FILE" ]; then
        read -p "配置文件已存在，是否覆盖？(y/N): " overwrite
        overwrite=${overwrite:-N}
        [[ ! "$overwrite" =~ ^[Yy]$ ]] && echo "❌ 已取消生成配置" && return
    fi
    read -p "请输入 SSH 端口 (默认 22): " ssh_port
    ssh_port=${ssh_port:-22}
    read -p "请输入最大失败次数 (默认 5): " max_retry
    max_retry=${max_retry:-5}
    read -p "请输入封禁时间(秒) (默认 3600): " ban_time
    ban_time=${ban_time:-3600}

    sudo tee $JAIL_FILE > /dev/null <<EOF
# =========================================
# Fail2ban SSH 配置文件 (systemd backend)
# 生成时间: $(date)
# 注释：
# bantime  : 封禁时间(秒)
# findtime : 失败次数统计时间窗口(秒)
# maxretry : 最大失败次数
# ignoreip : 忽略的 IP 列表
# backend  : 使用 systemd 日志
# sshd     : SSH 服务监控
# =========================================

[DEFAULT]
bantime  = ${ban_time}
findtime = 600
maxretry = ${max_retry}
ignoreip = 127.0.0.1/8
backend  = systemd

[sshd]
enabled  = true
port     = ${ssh_port}
filter   = sshd
logpath  = journal
EOF

    echo "✅ 配置已生成并保存到 $JAIL_FILE"
    read -p "是否立即启动并应用 Fail2ban 配置？(y/N): " start_choice
    start_choice=${start_choice:-N}
    [[ "$start_choice" =~ ^[Yy]$ ]] && sudo systemctl restart fail2ban && echo "🔄 Fail2ban 已启动并应用配置" || echo "⚠️ 请手动启动或重启 Fail2ban 以应用配置"
}

start_fail2ban() { check_fail2ban && sudo systemctl start fail2ban && echo "✅ Fail2ban 已启动"; }
stop_fail2ban() { check_fail2ban && sudo systemctl stop fail2ban && echo "🛑 Fail2ban 已停止"; }
restart_fail2ban() { check_fail2ban && sudo systemctl restart fail2ban && echo "🔄 Fail2ban 已重启"; }
view_status() { check_fail2ban && sudo fail2ban-client status sshd; }
view_log() { check_fail2ban && echo "📜 查看日志（Ctrl+C 退出）" && sudo journalctl -u ssh -f; }
add_ip() { check_fail2ban && read -p "请输入要封禁的 IP: " ip && [ -n "$ip" ] && sudo fail2ban-client set sshd banip "$ip" && echo "✅ IP $ip 已封禁"; }

remove_ip() {
    if ! check_fail2ban; then return; fi
    ips=$(sudo fail2ban-client status sshd | grep 'Banned IP list' | sed 's/.*://;s/ //g')
    [ -z "$ips" ] && echo "⚠️ 当前没有封禁的 IP" && return
    ip_array=(${ips//,/ })
    echo "当前封禁的 IP："
    for i in "${!ip_array[@]}"; do echo "$((i+1)) ${ip_array[$i]}"; done
    echo "输入编号解封，输入 'all' 解封全部，输入 0 返回"
    read -p "请选择操作: " choice
    if [[ "$choice" == "all" ]]; then
        for ip in "${ip_array[@]}"; do sudo fail2ban-client set sshd unbanip "$ip"; done
        echo "✅ 已解封所有封禁 IP"
    elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#ip_array[@]}" ]; then
        sudo fail2ban-client set sshd unbanip "${ip_array[$((choice-1))]}"
        echo "✅ IP ${ip_array[$((choice-1))]} 已解封"
    else
        echo "❌ 输入无效"
    fi
}

view_config() { [ -f "$JAIL_FILE" ] && sudo cat $JAIL_FILE || echo "⚠️ 配置文件不存在"; }

edit_config() { command -v vim >/dev/null || sudo apt update && sudo apt install vim -y; [ -f "$JAIL_FILE" ] && sudo vim $JAIL_FILE || echo "⚠️ 配置文件不存在"; }

export_banned_ips() { check_fail2ban || return; ips=$(sudo fail2ban-client status sshd | grep 'Banned IP list' | sed 's/.*://;s/ //g'); [ -z "$ips" ] && echo "⚠️ 当前没有封禁 IP" && return; read -p "请输入导出文件路径(默认 ./banned_ips.txt): " filepath; filepath=${filepath:-./banned_ips.txt}; echo "$ips" | tr ',' '\n' > "$filepath"; echo "✅ 已导出封禁 IP 到 $filepath"; }

clear_all_banned() { check_fail2ban || return; ips=$(sudo fail2ban-client status sshd | grep 'Banned IP list' | sed 's/.*://;s/ //g'); [ -z "$ips" ] && echo "⚠️ 当前没有封禁 IP" && return; for ip in $(echo $ips | tr ',' ' '); do sudo fail2ban-client set sshd unbanip "$ip"; done; echo "✅ 已清空所有封禁 IP"; }

remove_fail2ban() {
    echo "⚠️ 确认删除 Fail2ban 并清理所有配置和管理脚本？(y/n)"
    read -r confirm
    [[ "$confirm" != "y" ]] && echo "❌ 已取消删除" && return
    sudo systemctl stop fail2ban
    sudo apt purge fail2ban -y
    sudo rm -f $JAIL_FILE
    [[ -f "$SCRIPT_FILE" ]] && sudo rm -f "$SCRIPT_FILE"
    echo "🗑️ Fail2ban 和管理脚本已删除"
    exit 0
}

update_script() {
    echo "📦 更新脚本前备份配置..."
    [ -f "$JAIL_FILE" ] && sudo cp "$JAIL_FILE" "${JAIL_FILE}.bak_$(date +%F_%H%M%S)"
    echo "🔄 更新脚本..."
    curl -L "$SCRIPT_URL" -o /tmp/fail2ban-easy && chmod +x /tmp/fail2ban-easy && sudo mv /tmp/fail2ban-easy "$SCRIPT_FILE"
    echo "✅ 脚本更新完成"
    read -p "是否立即重载 Fail2ban 配置？(y/N): " reload
    reload=${reload:-N}
    [[ "$reload" =~ ^[Yy]$ ]] && sudo systemctl restart fail2ban && echo "🔄 Fail2ban 已重载"
}

while true; do
    echo -e "\n====== Fail2ban-easy 菜单 ======"
    echo "1) 安装 Fail2ban"
    echo "2) 配置 Fail2ban"
    echo "3) 启动 Fail2ban"
    echo "4) 停止 Fail2ban"
    echo "5) 重启 Fail2ban"
    echo "6) 查看状态"
    echo "7) 查看日志"
    echo "8) 添加黑名单 IP"
    echo "9) 删除黑名单 IP"
    echo "10) 查看配置"
    echo "11) 编辑配置"
    echo "12) 导出封禁 IP"
    echo "13) 清空所有封禁 IP"
    echo "14) 删除 Fail2ban"
    echo "15) 更新脚本"
    echo "16) 退出"
    echo "================================"
    read -p "请选择操作: " choice
    case $choice in
        1) install_fail2ban ;;
        2) configure_fail2ban ;;
        3) start_fail2ban ;;
        4) stop_fail2ban ;;
        5) restart_fail2ban ;;
        6) view_status ;;
        7) view_log ;;
        8) add_ip ;;
        9) remove_ip ;;
        10) view_config ;;
        11) edit_config ;;
        12) export_banned_ips ;;
        13) clear_all_banned ;;
        14) remove_fail2ban ;;
        15) update_script ;;
        16) echo "👋 退出"; echo "⚡ 下次使用直接运行: sudo fail2ban-easy"; exit 0 ;;
        *) echo "❌ 无效选项，请重新选择" ;;
    esac
done