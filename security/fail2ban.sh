#!/bin/bash

# [核心校验] 工业级 IP 与 CIDR 地址合法性检查 (升级版)
validate_ip() {
    local full_ip=$1
    [ -z "$full_ip" ] && return 1

    local ip="$full_ip"
    local prefix=""

    # 提取 CIDR 后缀 (如果有)
    if [[ "$full_ip" =~ ^(.*)/([0-9]+)$ ]]; then
        ip="${BASH_REMATCH[1]}"
        prefix="${BASH_REMATCH[2]}"
        # 预先校验掩码范围
        if [[ "$ip" =~ ":" ]]; then
            [ "$prefix" -gt 128 ] && return 1  # IPv6 最大 128
        else
            [ "$prefix" -gt 32 ] && return 1   # IPv4 最大 32
        fi
    fi

    # --- IPv4 深度校验 ---
    if [[ "$ip" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]]; then
        for i in 1 2 3 4; do
            if [ "${BASH_REMATCH[$i]}" -gt 255 ]; then return 1; fi
        done
        return 0
        
    # --- IPv6 深度校验 ---
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
        echo -e "${gl_huang}请输入白名单 IP (防止误封自己/中转机，支持网段如 /24)${gl_bai}"
        read -p "留空则跳过: " whitelist_ips
        
        local ignore_ip_conf="127.0.0.1/8 ::1"
        if [ -n "$whitelist_ips" ] && validate_ip "$whitelist_ips"; then 
            ignore_ip_conf="$ignore_ip_conf $whitelist_ips"
        elif [ -n "$whitelist_ips" ]; then
            echo -e "${gl_hong}IP 格式有误，自动跳过自定义白名单。您可以在安装后使用白名单管理功能添加。${gl_bai}"
            sleep 2
        fi

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
        echo -e "已启用保护: SSH端口 $ssh_port | 白名单已初始化"
        sleep 2
    }

    # === [新增模块] 白名单独立管理 ===
    manage_whitelist() {
        while true; do
            clear
            echo -e "${gl_kjlan}################################################"
            echo -e "#           Fail2ban 白名单安全管理            #"
            echo -e "################################################${gl_bai}"
            
            if [ ! -f /etc/fail2ban/jail.local ]; then
                echo -e "${gl_hong}错误: Fail2ban 未安装或配置丢失！${gl_bai}"
                sleep 2; return
            fi

            # 动态抓取配置文件中的白名单内容
            local current_ignore=$(grep -E "^[ \t]*ignoreip[ \t]*=" /etc/fail2ban/jail.local | cut -d'=' -f2- | xargs)
            
            echo -e "当前系统白名单:"
            if [ -n "$current_ignore" ]; then
                local i=1
                for ip in $current_ignore; do
                    echo -e "  ${gl_huang}${i}.${gl_bai} $ip"
                    i=$((i+1))
                done
            else
                echo "  (空)"
            fi
            echo -e "------------------------------------------------"
            echo -e " 1. ➕ 添加白名单 (支持单 IP 或 CIDR 网段)"
            echo -e " 2. ➖ 删除白名单 (精准匹配移除)"
            echo -e " 0. 返回主管理菜单"
            echo -e "------------------------------------------------"
            read -p "请输入选项: " wl_choice

            case "$wl_choice" in
                1)
                    read -p "请输入要放行的 IP 或网段 (例: 1.1.1.1 或 10.0.0.0/8): " new_ip
                    if validate_ip "$new_ip"; then
                        if [[ " $current_ignore " == *" $new_ip "* ]]; then
                            echo -e "${gl_huang}提示: 该 IP/网段已存在于白名单中！${gl_bai}"
                        else
                            local new_list="$current_ignore $new_ip"
                            # 手术刀式替换，不破坏原文件结构
                            sed -i "s|^[ \t]*ignoreip[ \t]*=.*|ignoreip = $new_list|" /etc/fail2ban/jail.local
                            fail2ban-client reload >/dev/null 2>&1
                            echo -e "${gl_lv}添加成功！配置已热重载生效。${gl_bai}"
                        fi
                    else
                        echo -e "${gl_hong}错误: 无效的格式！${gl_bai}"
                    fi
                    sleep 2
                    ;;
                2)
                    read -p "请输入要删除的 IP 或网段: " del_ip
                    if validate_ip "$del_ip"; then
                        if [[ " $current_ignore " == *" $del_ip "* ]]; then
                            # 使用 sed 剔除特定的 IP，保持空格整洁
                            local new_list=$(echo " $current_ignore " | sed "s/ $del_ip / /g" | xargs)
                            sed -i "s|^[ \t]*ignoreip[ \t]*=.*|ignoreip = $new_list|" /etc/fail2ban/jail.local
                            fail2ban-client reload >/dev/null 2>&1
                            echo -e "${gl_lv}删除成功！配置已热重载生效。${gl_bai}"
                        else
                            echo -e "${gl_huang}提示: 列表中未找到该 IP/网段记录。${gl_bai}"
                        fi
                    else
                        echo -e "${gl_hong}错误: 无效的格式！${gl_bai}"
                    fi
                    sleep 2
                    ;;
                0) return ;;
                *) echo "无效选项"; sleep 1 ;;
            esac
        done
    }

    # === [重构模块] 封禁状态与解封中心 ===
    unban_ip_center() {
        while true; do
            clear
            echo -e "${gl_kjlan}################################################"
            echo -e "#           Fail2ban 封禁解除中心              #"
            echo -e "################################################${gl_bai}"
            
            if ! systemctl is-active --quiet fail2ban; then
                echo -e "${gl_hong}错误: Fail2ban 未运行！${gl_bai}"
                sleep 2; return
            fi

            # 自动提取所有被封的纯 IP 列表
            local sshd_banned=$(fail2ban-client status sshd 2>/dev/null | grep "Banned IP list:" | awk -F':' '{print $2}' | xargs)
            local recidive_banned=$(fail2ban-client status recidive 2>/dev/null | grep "Banned IP list:" | awk -F':' '{print $2}' | xargs)

            echo -e "[ 当前实时封禁黑名单 ]"
            echo -e "------------------------------------------------"
            echo -e "🔥 SSH 爆破 (sshd):"
            if [ -n "$sshd_banned" ]; then
                for ip in $sshd_banned; do echo -e "   - ${gl_hong}$ip${gl_bai}"; done
            else
                echo -e "   ${gl_lv}(环境纯净，无封禁)${gl_bai}"
            fi
            
            echo -e "\n💀 顽固惯犯 (recidive):"
            if [ -n "$recidive_banned" ]; then
                for ip in $recidive_banned; do echo -e "   - ${gl_hong}$ip${gl_bai}"; done
            else
                echo -e "   ${gl_lv}(环境纯净，无封禁)${gl_bai}"
            fi
            echo -e "------------------------------------------------"

            echo -e " 1. 🔓 手动解封特定 IP"
            echo -e " 2. 🕊️ 一键全体特赦 (解封所有 IP)"
            echo -e " 3. 🔄 刷新当前黑名单列表"
            echo -e " 0. 返回上级菜单"
            echo -e "------------------------------------------------"
            
            read -p "请输入选项: " ub_choice
            case "$ub_choice" in
                1)
                    read -p "请输入要解封的 IP: " target_ip
                    if validate_ip "$target_ip"; then
                        fail2ban-client set sshd unbanip "$target_ip" >/dev/null 2>&1
                        fail2ban-client set recidive unbanip "$target_ip" >/dev/null 2>&1
                        echo -e "${gl_lv}解封指令已发送！${gl_bai}"
                    else
                        echo -e "${gl_hong}错误: 无效的 IP 地址格式！${gl_bai}"
                    fi
                    sleep 2
                    ;;
                2)
                    echo -e "${gl_huang}正在打开城门，释放所有被封禁 IP...${gl_bai}"
                    # Fail2ban 0.11+ 原生支持一键解封
                    fail2ban-client unban --all >/dev/null 2>&1
                    echo -e "${gl_lv}全体特赦完成！黑屋已清空。${gl_bai}"
                    sleep 2
                    ;;
                3) continue ;;
                0) return ;;
                *) echo "无效选项"; sleep 1 ;;
            esac
        done
    }

    # === Fail2ban 主菜单路由 ===
    while true; do
        clear
        # 动态获取状态颜色
        local f2b_status_text=""
        if systemctl is-active --quiet fail2ban; then
            f2b_status_text="${gl_lv}● 运行中 (Active)${gl_bai}"
        else
            f2b_status_text="${gl_hong}○ 未运行 (Inactive)${gl_bai}"
        fi

        echo -e "${gl_kjlan}╭────────────────────────────────────────────────────────────────╮${gl_bai}"
        echo -e "${gl_kjlan}│${gl_bai}              ${gl_huang}Fail2ban 暴力破解防护中心${gl_bai}                  ${gl_kjlan}│${gl_bai}"
        echo -e "${gl_kjlan}╰────────────────────────────────────────────────────────────────╯${gl_bai}"
        echo -e " 核心服务状态: $f2b_status_text"
        echo -e "${gl_kjlan}------------------------------------------------------------------${gl_bai}"
        
        echo -e " ${gl_huang}[ 📥 部署与维护 ]${gl_bai}"
        echo -e "   ${gl_lv}1.${gl_bai} 安装 / 重置服务 (Install/Reset)"
        echo -e "   ${gl_hong}5.${gl_bai} 完全卸载组件 (Uninstall)"
        
        echo -e " ${gl_hui}┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈${gl_bai}"
        
        echo -e " ${gl_huang}[ 🛡️  安全与策略 ]${gl_bai}"
        echo -e "   ${gl_kjlan}2.${gl_bai} 白名单管理中心 (Whitelist)           ${gl_lv}[常用]${gl_bai}"
        echo -e "   ${gl_kjlan}3.${gl_bai} 封禁查看与解封 (Unban Center)         ${gl_lv}[常用]${gl_bai}"
        
        echo -e " ${gl_hui}┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈${gl_bai}"
        
        echo -e " ${gl_huang}[ 📊 监控与分析 ]${gl_bai}"
        echo -e "   ${gl_hui}4.${gl_bai} 实时查看攻击日志 (Monitor Log)"
        
        echo -e "\n   ${gl_hui}0. 返回主菜单 (Back)${gl_bai}"
        echo -e "${gl_kjlan}==================================================================${gl_bai}"
        
        read -p " 请输入选项: " f2b_choice
        # ... 后面原有的 case 逻辑不变 ...

        case "$f2b_choice" in
            1) install_fail2ban; read -p "按回车继续..." ;;
            2) manage_whitelist ;;
            3) unban_ip_center ;;
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
                nft delete table inet f2b-table 2>/dev/null
                echo -e "${gl_lv}卸载完成。${gl_bai}"
                read -p "按回车继续..."
                ;;
            0) return ;;
            *) echo "无效选项"; sleep 1 ;;
        esac
    done
}
