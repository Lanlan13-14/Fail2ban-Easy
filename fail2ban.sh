#!/usr/bin/env bash
# Fail2ban-easy 管理脚本 (systemd backend)
# 功能：安装/配置/启停/重启/日志/黑名单/查看/修改配置/导出/清空/删除/更新

JAIL_FILE="/etc/fail2ban/jail.local"
SCRIPT_FILE="/usr/local/bin/fail2ban-easy"
SCRIPT_URL="https://raw.githubusercontent.com/Lanlan13-14/Fail2ban-easy/refs/heads/main/fail2ban.sh"
# 自动滥用投诉配置文件
ABUSE_AUTO_REPORT_FILE="/etc/fail2ban/auto_report.conf"
ABUSE_API_KEY=""        # 保存用户输入的 API Key
ABUSE_ENABLED=0         # 默认关闭

check_fail2ban() {
    if ! command -v fail2ban-client &>/dev/null; then
        echo "⚠️ Fail2ban 未安装，请先选择 [1] 安装。"
        return 1
    fi
    return 0
}

install_fail2ban() {
    echo "🚀 安装 Fail2ban 及依赖..."
    # 更新并安装 Fail2ban 及必要依赖
    sudo apt update && sudo apt install -y fail2ban python3-systemd sqlite3 systemd-journal-remote

    # 确保 systemd journal 持久化
    sudo mkdir -p /var/log/journal
    sudo systemd-tmpfiles --create --prefix /var/log/journal
    sudo systemctl restart systemd-journald

    # 启用 Fail2ban 服务
    sudo systemctl enable fail2ban

    echo "✅ Fail2ban 安装并启用完成，systemd journal 已启用"
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
ignoreip = 127.0.0.1/8 ::1
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

    # 只提取 IP
    ips=$(sudo fail2ban-client status sshd | grep 'Banned IP list' | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}')
    [ -z "$ips" ] && echo "⚠️ 当前没有封禁的 IP" && return

    ip_array=($ips)

    echo "当前封禁的 IP："
    for i in "${!ip_array[@]}"; do
        echo "[$((i+1))] ${ip_array[$i]}"
    done

    echo "输入编号解封（可用空格分隔多个编号），输入 'all' 解封全部，输入 0 返回"
    read -p "请选择操作: " choice

    if [[ "$choice" == "all" ]]; then
        for ip in "${ip_array[@]}"; do
            sudo fail2ban-client set sshd unbanip "$ip"
        done
        echo "✅ 已解封所有封禁 IP"

    elif [[ "$choice" =~ ^[0-9\ ]+$ ]]; then
        for num in $choice; do
            if [ "$num" -ge 1 ] && [ "$num" -le "${#ip_array[@]}" ]; then
                sudo fail2ban-client set sshd unbanip "${ip_array[$((num-1))]}"
                echo "✅ IP ${ip_array[$((num-1))]} 已解封"
            elif [ "$num" -eq 0 ]; then
                echo "返回"
                return
            else
                echo "❌ 编号 $num 无效"
            fi
        done
    else
        echo "❌ 输入无效"
    fi

    # 显示解封后的最新封禁 IP
    new_ips=$(sudo fail2ban-client status sshd | grep 'Banned IP list' | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}')
    if [ -z "$new_ips" ]; then
        echo "当前没有封禁的 IP"
    else
        echo "当前封禁的 IP："
        new_ip_array=($new_ips)
        for i in "${!new_ip_array[@]}"; do
            echo "[$((i+1))] ${new_ip_array[$i]}"
        done
    fi
}

view_config() { [ -f "$JAIL_FILE" ] && sudo cat $JAIL_FILE || echo "⚠️ 配置文件不存在"; }

edit_config() { command -v vim >/dev/null || sudo apt update && sudo apt install vim -y; [ -f "$JAIL_FILE" ] && sudo vim $JAIL_FILE || echo "⚠️ 配置文件不存在"; }

export_banned_ips() { check_fail2ban || return; ips=$(sudo fail2ban-client status sshd | grep 'Banned IP list' | sed 's/.*://;s/ //g'); [ -z "$ips" ] && echo "⚠️ 当前没有封禁 IP" && return; read -p "请输入导出文件路径(默认 ./banned_ips.txt): " filepath; filepath=${filepath:-./banned_ips.txt}; echo "$ips" | tr ',' '\n' > "$filepath"; echo "✅ 已导出封禁 IP 到 $filepath"; }

clear_all_banned() { check_fail2ban || return; ips=$(sudo fail2ban-client status sshd | grep 'Banned IP list' | sed 's/.*://;s/ //g'); [ -z "$ips" ] && echo "⚠️ 当前没有封禁 IP" && return; for ip in $(echo $ips | tr ',' ' '); do sudo fail2ban-client set sshd unbanip "$ip"; done; echo "✅ 已清空所有封禁 IP"; }

setup_abuse_api_key() {
    # 如果配置文件存在则加载
    [ -f "$ABUSE_AUTO_REPORT_FILE" ] && source "$ABUSE_AUTO_REPORT_FILE"

    # 如果没有 API Key，提示用户输入
    if [ -z "$ABUSE_API_KEY" ]; then
        echo "⚠️ 检测到未配置 AbuseIPDB API Key"
        echo "请前往 https://www.abuseipdb.com/ 注册并获取 API Key"
        read -p "请输入你的 AbuseIPDB API Key: " key
        ABUSE_API_KEY="$key"
        # 保存配置
        mkdir -p "$(dirname "$ABUSE_AUTO_REPORT_FILE")"
        echo "ABUSE_ENABLED=$ABUSE_ENABLED" > "$ABUSE_AUTO_REPORT_FILE"
        echo "ABUSE_API_KEY=$ABUSE_API_KEY" >> "$ABUSE_AUTO_REPORT_FILE"
        echo "✅ API Key 已保存到 $ABUSE_AUTO_REPORT_FILE"
    fi
}

report_to_abuseipdb() {
    # 读取自动投诉配置
    [ -f "$ABUSE_AUTO_REPORT_FILE" ] && source "$ABUSE_AUTO_REPORT_FILE"
    [ "$ABUSE_ENABLED" -ne 1 ] && echo "⚠️ 自动投诉功能未开启" && return

    # 检查 API Key
    setup_abuse_api_key

    # 获取 Fail2ban 封禁 IP - 使用更可靠的方法
    ip_line=$(sudo fail2ban-client status sshd | grep 'Banned IP list')
    
    # 使用 sed 提取 IP 部分，去除所有非IP字符
    ips=$(echo "$ip_line" | sed 's/.*Banned IP list://' | sed 's/[^0-9\. ]//g' | xargs)
    
    if [ -z "$ips" ] || [ "$ips" = " " ]; then
        echo "⚠️ 当前没有任何封禁 IP"
        return
    fi

    success_count=0
    fail_count=0

    # 将空格分隔的 IP 字符串转换为数组
    read -ra ip_array <<< "$ips"
    total_ips=${#ip_array[@]}
    current=0

    echo "📊 开始处理 $total_ips 个封禁 IP..."

    for ip in "${ip_array[@]}"; do
        ((current++))
        
        # 跳过空值
        [ -z "$ip" ] && continue
        
        # 过滤私有 IP
        if [[ $ip =~ ^(10\.|192\.168\.|172\.1[6-9]\.|172\.2[0-9]\.|172\.3[0-1]\.|127\.|169\.254\.|224\.) ]]; then
            echo "⏩ 跳过私有 IP: $ip ($current/$total_ips)"
            continue
        fi

        timestamp=$(date -Iseconds)

        # 提交单个 IP
        response=$(curl -s -w "\n%{http_code}" -X POST "https://api.abuseipdb.com/api/v2/report" \
            --data-urlencode "ip=$ip" \
            -d "categories=18" \
            --data-urlencode "comment=Detected brute force attempt" \
            --data-urlencode "timestamp=$timestamp" \
            -H "Key: $ABUSE_API_KEY" \
            -H "Accept: application/json" 2>/dev/null)

        http_code=$(echo "$response" | tail -n1)
        body=$(echo "$response" | sed '$d')

        if [ "$http_code" -eq 200 ]; then
            echo "[✅] 成功提交: $ip ($current/$total_ips)"
            ((success_count++))
        else
            echo "❌ 提交失败: $ip (HTTP $http_code) - ${body:0:100}"
            ((fail_count++))
        fi

        # 添加延迟避免触发 API 限制
        if [ $current -lt $total_ips ]; then
            sleep 1
        fi
    done

    echo "🎉 自动投诉执行完毕"
    echo "   ✅ 成功提交: $success_count 个 IP"
    echo "   ❌ 提交失败: $fail_count 个 IP"
    skipped=$((total_ips - success_count - fail_count))
    echo "   ⏩ 跳过私有: $skipped 个 IP"
}

# 切换自动投诉开关
toggle_abuse_report() {
    # 先加载配置
    [ -f "$ABUSE_AUTO_REPORT_FILE" ] && source "$ABUSE_AUTO_REPORT_FILE"

    ABUSE_ENABLED=$((1-ABUSE_ENABLED))  # 0->1 或 1->0
    echo "ABUSE_ENABLED=$ABUSE_ENABLED" > "$ABUSE_AUTO_REPORT_FILE"
    echo "ABUSE_API_KEY=$ABUSE_API_KEY" >> "$ABUSE_AUTO_REPORT_FILE"

    if [ "$ABUSE_ENABLED" -eq 1 ]; then
        echo "✅ 自动投诉已开启"
    else
        echo "⚠️ 自动投诉已关闭"
    fi
}

# 设置每天凌晨 2 点自动投诉定时任务
setup_abuse_cron() {
    [ -f "$ABUSE_AUTO_REPORT_FILE" ] || setup_abuse_api_key

    # 删除原有 cron
    (crontab -l 2>/dev/null | grep -v "$SCRIPT_FILE") | crontab -

    # 添加每天 2 点自动执行
    (crontab -l 2>/dev/null; echo "0 2 * * * sudo $SCRIPT_FILE --auto-report") | crontab -
    echo "⏰ 每天凌晨 2 点自动投诉任务已设置"
}

# 处理命令行参数 --auto-report
if [ "$1" == "--auto-report" ]; then
    report_to_abuseipdb
    exit 0
fi



remove_fail2ban() {
    echo "⚠️ 确认删除 Fail2ban 并清理所有配置、管理脚本及自动投诉配置？(y/n)"
    read -r confirm
    [[ "$confirm" != "y" ]] && echo "❌ 已取消删除" && return

    # 停止 Fail2ban
    sudo systemctl stop fail2ban

    # 卸载 Fail2ban
    sudo apt purge fail2ban -y

    # 删除 Fail2ban 配置文件
    sudo rm -f "$JAIL_FILE"

    # 删除管理脚本
    [[ -f "$SCRIPT_FILE" ]] && sudo rm -f "$SCRIPT_FILE"

    # 删除自动投诉配置文件
    [[ -f "$ABUSE_AUTO_REPORT_FILE" ]] && sudo rm -f "$ABUSE_AUTO_REPORT_FILE"

    # 删除与脚本相关的 cron 定时任务
    (crontab -l 2>/dev/null | grep -v "$SCRIPT_FILE") | crontab -

    echo "🗑️ Fail2ban、管理脚本及自动投诉配置已删除"
    exit 0
}

update_script() {
    echo "📦 更新脚本前备份当前配置和脚本..."
    [ -f "$JAIL_FILE" ] && sudo cp "$JAIL_FILE" "${JAIL_FILE}.bak_$(date +%F_%H%M%S)"
    [ -f "$SCRIPT_FILE" ] && sudo cp "$SCRIPT_FILE" "${SCRIPT_FILE}.bak_$(date +%F_%H%M%S)"

    echo "🔄 下载新脚本..."
    TMP_FILE="/tmp/fail2ban-easy.new"
    curl -L "$SCRIPT_URL" -o "$TMP_FILE"
    chmod +x "$TMP_FILE"

    # 语法检查
    if bash -n "$TMP_FILE"; then
        echo "✅ 新脚本语法检查通过，应用更新..."
        sudo mv "$TMP_FILE" "$SCRIPT_FILE"
        read -p "是否立即重启 Fail2ban 并重新运行脚本？(y/N): " reload
        reload=${reload:-N}
        if [[ "$reload" =~ ^[Yy]$ ]]; then
            exec sudo "$SCRIPT_FILE"
        fi
    else
        echo "❌ 新脚本存在语法错误，更新已取消，保持旧版本。"
        rm -f "$TMP_FILE"
    fi
}

# 支持命令行参数 --auto-report
if [ "$1" == "--auto-report" ]; then
    report_to_abuseipdb
    exit 0
fi

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
    echo "16) 自动投诉设置 (开启/关闭)"
    echo "17) 设置每天 2 点自动投诉任务"
    echo "18) 设置/修改 AbuseIPDB API Key"
    echo "19) 退出"
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
        16) toggle_abuse_report ;;
        17) setup_abuse_cron ;;
        18) setup_abuse_api_key ;;
        19) echo "👋 退出"; echo "⚡ 下次使用直接运行: sudo fail2ban-easy"; exit 0 ;;
        *) echo "❌ 无效选项，请重新选择" ;;
    esac
done