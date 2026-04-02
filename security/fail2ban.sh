#!/bin/bash

# [核心校验] 工业级 IP 地址合法性检查
validate_ip() {
    local ip=$1
    [ -z "$ip" ] && return 1

    # --- IPv4 深度校验 ---
    if [[ "$ip" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]]; then
        # 拆分四个小节并检查是否都在 0-255 之间
        for i in 1 2 3 4; do
            if [ "${BASH_REMATCH[$i]}" -gt 255 ]; then return 1; fi
        done
        return 0
        
    # --- IPv6 深度校验 ---
    # 匹配标准 IPv6 结构 (包含十六进制、冒号、以及缩写双冒号)
    elif [[ "$ip" =~ ^(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))$ ]]; then
        return 0
    fi

    return 1
}

fail2ban_management() {
    # 局部作用域定义，确保模块独立运行不报错
    detect_ssh_port() {
        local port=$(sshd -T 2>/dev/null | grep -i '^port ' | awk '{print $2}' | head -n 1)
        echo "${port:-22}"
    }

    install_fail2ban() {
        local ssh_port=$(detect_ssh_port)
        echo -e "${gl_huang}=== Fail2ban 安装向导 ===${gl_bai}"
        echo -e "当前 SSH 端口: ${gl_lv}${ssh_port}${gl_bai}"
        
        echo -e "------------------------------------------------"
        echo -e "${gl_huang}请输入白名单 IP (防止误封自己/中转机)${gl_bai}"
        read -p "留空则跳过: " whitelist_ips
        
        local ignore_ip_conf="127.0.0.1/8 ::1"
        if [ -n "$whitelist_ips" ]; then ignore_ip_conf="$ignore_ip_conf $whitelist_ips"; fi

        echo -e "${gl_kjlan}正在安装并配置 Fail2ban...${gl_bai}"
        apt update && apt install fail2ban rsyslog -y
        systemctl enable --now rsyslog
        touch /var/log/auth.log /var/log/fail2ban.log

        # 完美适配 Nftables 框架
        cat > /etc/fail2ban/jail.d/00-default-nftables.conf << EOF
[DEFAULT]
banaction = nftables-multiport
banaction_allports = nftables-allports
chain = input
EOF
        cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
ignoreip = $ignore_ip_conf
findtime = 600
maxretry = 5
backend = polling

[sshd]
enabled = true
port = $ssh_port
filter = sshd
logpath = /var/log/auth.log
bantime = 10800

[recidive]
enabled = true
logpath = /var/log/fail2ban.log
filter = recidive
findtime = 172800
maxretry = 2
bantime = 259200
bantime.increment = true
bantime.factor = 121.6
bantime.maxsize = 31536000
EOF
        systemctl stop fail2ban >/dev/null 2>&1
        rm -f /var/run/fail2ban/fail2ban.sock
        systemctl daemon-reload
        systemctl restart fail2ban
        systemctl enable fail2ban

        echo -e "${gl_lv}Fail2ban 部署完成！${gl_bai}"
        echo -e "已启用保护: SSH端口 $ssh_port | 白名单: ${whitelist_ips:-无}"
        sleep 2
    }

    check_f2b_status() {
        if ! systemctl is-active --quiet fail2ban; then
            echo -e "${gl_hong}Fail2ban 未运行！${gl_bai}"; return
        fi
        echo -e "${gl_huang}=== 当前封禁统计 ===${gl_bai}"
        fail2ban-client status sshd
        echo -e "------------------------------------------------"
        fail2ban-client status recidive
    }

    unban_ip() {
        read -p "请输入要解封的 IP: " target_ip
        if [ -n "$target_ip" ]; then
            # 加入严格的 IP 格式校验防线
            if validate_ip "$target_ip"; then
                fail2ban-client set sshd unbanip "$target_ip" >/dev/null 2>&1
                fail2ban-client set recidive unbanip "$target_ip" >/dev/null 2>&1
                echo -e "${gl_lv}解封指令已发送！(如果 IP 曾被封禁，现已放行)${gl_bai}"
            else
                echo -e "${gl_hong}错误: 无效的 IP 地址格式！${gl_bai}"
            fi
        else
            echo -e "${gl_huang}未输入 IP，操作取消。${gl_bai}"
        fi
    }

    while true; do
        clear
        echo -e "${gl_kjlan}################################################"
        echo -e "#              Fail2ban 防暴力破解管理         #"
        echo -e "################################################${gl_bai}"
        
        if systemctl is-active --quiet fail2ban; then
            echo -e "当前状态: ${gl_lv}运行中 (Running)${gl_bai}"
        else
            echo -e "当前状态: ${gl_hong}未运行 / 未安装${gl_bai}"
        fi
        
        echo -e "------------------------------------------------"
        echo -e "${gl_lv} 1.${gl_bai} 安装/重置 Fail2ban (Install/Reset)"
        echo -e "${gl_lv} 2.${gl_bai} 查看封禁状态 (Status)"
        echo -e "${gl_lv} 3.${gl_bai} 手动解封 IP (Unban IP)"
        echo -e "${gl_lv} 4.${gl_bai} 查看攻击日志 (View Log)"
        echo -e "${gl_hong} 5.${gl_bai} 卸载 Fail2ban (Uninstall)"
        echo -e "------------------------------------------------"
        echo -e "${gl_hui} 0. 返回主菜单${gl_bai}"
        
        read -p "请输入选项: " f2b_choice

        case "$f2b_choice" in
            1) install_fail2ban; read -p "按回车继续..." ;;
            2) check_f2b_status; read -p "按回车继续..." ;;
            3) unban_ip; read -p "按回车继续..." ;;
            4) 
                echo -e "${gl_huang}正在实时显示日志...${gl_bai}"
                trap 'kill $tail_pid 2>/dev/null; echo -e "\n${gl_lv}已停止监控。${gl_bai}"; return' SIGINT
                tail -f -n 20 /var/log/fail2ban.log &
                local tail_pid=$!
                read -r -p ">>> 请按【回车键】或【Ctrl+C】停止查看 <<<"
                kill $tail_pid >/dev/null 2>&1
                trap - SIGINT
                ;;
            5)
                echo -e "${gl_huang}正在卸载...${gl_bai}"
                systemctl stop fail2ban
                systemctl disable fail2ban
                apt purge fail2ban -y
                rm -rf /etc/fail2ban /var/log/fail2ban.log
                # 清除 Fail2ban 在 Nftables 留下的表结构
                nft delete table inet fail2ban 2>/dev/null
                echo -e "${gl_lv}卸载完成。${gl_bai}"
                read -p "按回车继续..."
                ;;
            0) return ;;
            *) echo "无效选项"; sleep 1 ;;
        esac
    done
}
