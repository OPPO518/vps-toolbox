#!/bin/bash

nftables_management() {
    # [核心安全] 保存函数
    save_config() {
        echo "#!/usr/sbin/nft -f" > /etc/nftables.conf
        if nft list tables | grep -q "my_landing"; then
            echo "table inet my_landing {}" >> /etc/nftables.conf
            echo "delete table inet my_landing" >> /etc/nftables.conf
            nft list table inet my_landing >> /etc/nftables.conf
        elif nft list tables | grep -q "my_transit"; then
            echo "table inet my_transit {}" >> /etc/nftables.conf
            echo "delete table inet my_transit" >> /etc/nftables.conf
            nft list table inet my_transit >> /etc/nftables.conf
        fi
    }

    init_landing_firewall() {
        local ssh_port=$(detect_ssh_port)
        echo -e "${gl_huang}检测到 SSH 端口: ${ssh_port} (将强制放行)${gl_bai}"
        echo -e "${gl_kjlan}正在部署 落地机(Landing) 策略...${gl_bai}"
        
        echo -e "清理环境..."
        ufw disable 2>/dev/null || true
        apt purge ufw -y 2>/dev/null
        sysctl -w net.ipv4.ip_forward=0 >/dev/null 2>&1
        
        apt update -y && apt install nftables -y
        systemctl enable nftables

        echo "#!/usr/sbin/nft -f" > /etc/nftables.conf
        cat >> /etc/nftables.conf << EOF
table inet my_landing {}
delete table inet my_landing
table inet my_landing {
    set allowed_tcp { type inet_service; flags interval; }
    set allowed_udp { type inet_service; flags interval; }
    chain input {
        type filter hook input priority 0; policy drop;
        iif "lo" accept
        ct state established,related accept
        icmp type echo-request accept
        icmpv6 type { echo-request, nd-neighbor-solicit, nd-neighbor-advert, nd-router-solicit, nd-router-advert } accept
        tcp dport $ssh_port accept
        tcp dport @allowed_tcp accept
        udp dport @allowed_udp accept
    }
    chain forward { type filter hook forward priority 0; policy drop; }
    chain output { type filter hook output priority 0; policy accept; }
}
EOF
        nft -f /etc/nftables.conf
        systemctl restart nftables
        echo -e "${gl_lv}落地机防火墙部署完成！${gl_bai}"
    }

    init_transit_firewall() {
        local ssh_port=$(detect_ssh_port)
        echo -e "${gl_huang}检测到 SSH 端口: ${ssh_port} (将强制放行)${gl_bai}"
        echo -e "${gl_kjlan}正在部署 中转机(Transit) 策略...${gl_bai}"

        echo -e "清理环境..."
        ufw disable 2>/dev/null || true
        apt purge ufw -y 2>/dev/null
        apt update -y && apt install nftables -y
        systemctl enable nftables

        modprobe nft_nat 2>/dev/null
        modprobe br_netfilter 2>/dev/null
        sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1
        
        echo "#!/usr/sbin/nft -f" > /etc/nftables.conf
        cat >> /etc/nftables.conf << EOF
table inet my_transit {}
delete table inet my_transit
table inet my_transit {
    set local_tcp { type inet_service; flags interval; }
    set local_udp { type inet_service; flags interval; }
    map fwd_tcp { type inet_service : ipv4_addr . inet_service; }
    map fwd_udp { type inet_service : ipv4_addr . inet_service; }
    chain input {
        type filter hook input priority 0; policy drop;
        iif "lo" accept
        ct state established,related accept
        icmp type echo-request accept
        icmpv6 type { echo-request, nd-neighbor-solicit, nd-neighbor-advert, nd-router-solicit, nd-router-advert } accept
        tcp dport $ssh_port accept
        tcp dport @local_tcp accept
        udp dport @local_udp accept
    }
    chain forward {
        type filter hook forward priority 0; policy accept;
        ct state established,related accept
        tcp flags syn tcp option maxseg size set 1360
    }
    chain prerouting {
        type nat hook prerouting priority -100; policy accept;
        dnat ip to tcp dport map @fwd_tcp
        dnat ip to udp dport map @fwd_udp
    }
    chain postrouting {
        type nat hook postrouting priority 100; policy accept;
        oifname != "lo" masquerade
    }
}
EOF
        nft -f /etc/nftables.conf
        systemctl restart nftables
        echo -e "${gl_lv}中转机防火墙部署完成！${gl_bai}"
    }

    list_rules_ui() {
        echo -e "${gl_huang}=== 防火墙规则概览 (Firewall Status) ===${gl_bai}"
        echo -e "基础防自锁: ${gl_lv}SSH Port $(detect_ssh_port) [✔ Accepted]${gl_bai}"
        
        local table_name="" set_tcp_name="" set_udp_name=""
        if nft list tables | grep -q "my_transit"; then 
            table_name="my_transit"; set_tcp_name="local_tcp"; set_udp_name="local_udp"
        elif nft list tables | grep -q "my_landing"; then
            table_name="my_landing"; set_tcp_name="allowed_tcp"; set_udp_name="allowed_udp"
        else 
            echo -e "${gl_hong}防火墙未初始化${gl_bai}"; return
        fi

        echo "------------------------------------------------"
        echo -e "${gl_huang}=== 自定义端口放行 ===${gl_bai}"
        local tcp_list=$(nft list set inet $table_name $set_tcp_name 2>/dev/null | grep 'elements =' | awk -F '{' '{print $2}' | awk -F '}' '{print $1}' | tr -d ' ')
        local udp_list=$(nft list set inet $table_name $set_udp_name 2>/dev/null | grep 'elements =' | awk -F '{' '{print $2}' | awk -F '}' '{print $1}' | tr -d ' ')

        echo -e "[TCP] ${gl_kjlan}${tcp_list:-无}${gl_bai}"
        echo -e "[UDP] ${gl_kjlan}${udp_list:-无}${gl_bai}"
        echo "------------------------------------------------"
        
        if [ "$table_name" == "my_transit" ]; then
            echo -e "${gl_kjlan}=== 端口转发规则 ===${gl_bai}"
            echo "--- TCP 转发 ---"
            nft list map inet my_transit fwd_tcp 2>/dev/null | tr -d '{},=;' | awk '{for(i=1;i<=NF;i++) if($i==":") printf "TCP %-6s -> %s : %s\n", $(i-1), $(i+1), $(i+3)}'
            echo "--- UDP 转发 ---"
            nft list map inet my_transit fwd_udp 2>/dev/null | tr -d '{},=;' | awk '{for(i=1;i<=NF;i++) if($i==":") printf "UDP %-6s -> %s : %s\n", $(i-1), $(i+1), $(i+3)}'
            echo "------------------------------------------------"
        fi
    }

    while true; do
        clear
        echo -e "${gl_kjlan}################################################"
        echo -e "#          Nftables 防火墙与中转管理           #"
        echo -e "################################################${gl_bai}"
        
        local ssh_p=$(detect_ssh_port)
        echo -e "当前 SSH 端口: ${gl_lv}${ssh_p}${gl_bai} (自动保护中)"
        
        local mode="None" table="" set_tcp="" set_udp=""
        
        if nft list tables | grep -q "my_transit"; then
            echo -e "当前模式: ${gl_kjlan}中转机 (Transit NAT)${gl_bai}"
            mode="Transit"; set_tcp="local_tcp"; set_udp="local_udp"; table="my_transit"
        elif nft list tables | grep -q "my_landing"; then
            echo -e "当前模式: ${gl_huang}落地机 (Landing FW)${gl_bai}"
            mode="Landing"; set_tcp="allowed_tcp"; set_udp="allowed_udp"; table="my_landing"
        else
            echo -e "当前模式: ${gl_hong}未初始化 / 未知${gl_bai}"
            mode="None"
        fi
        echo -e "------------------------------------------------"
        
        if [ "$mode" == "None" ]; then
            echo -e "${gl_lv} 1.${gl_bai} 初始化为：落地机防火墙 (仅放行)"
            echo -e "${gl_lv} 2.${gl_bai} 初始化为：中转机防火墙 (含转发面板)"
        else
            echo -e "${gl_lv} 1.${gl_bai} 查看所有规则 (List Rules)"
            echo -e "------------------------------------------------"
            echo -e "${gl_lv} 2.${gl_bai} 添加放行端口 (Allow Port)"
            echo -e "${gl_lv} 3.${gl_bai} 删除放行端口 (Delete Port)"
            if [ "$mode" == "Transit" ]; then
                echo -e "------------------------------------------------"
                echo -e "${gl_kjlan} 4.${gl_bai} 添加转发规则 (Add Forward)"
                echo -e "${gl_kjlan} 5.${gl_bai} 删除转发规则 (Del Forward)"
            fi
            echo -e "------------------------------------------------"
            echo -e "${gl_hong} 8.${gl_bai} 重置/切换模式 (Re-Init)"
        fi
        echo -e "${gl_hui} 0. 返回主菜单${gl_bai}"
        echo -e "------------------------------------------------"
        
        read -p "请输入选项: " nf_choice

        case "$nf_choice" in
            1) 
                if [ "$mode" == "None" ]; then init_landing_firewall; read -p "按回车继续..."
                else list_rules_ui; read -p "按回车继续..."; fi ;;
            2) 
                if [ "$mode" == "None" ]; then init_transit_firewall; read -p "按回车继续..."
                else 
                    list_rules_ui
                    echo -e "${gl_hui}提示: 支持单端口(8080) 或 范围(50000:60000)${gl_bai}"
                    read -p "请输入要放行的端口: " p_port
                    if [[ "$p_port" =~ ^([0-9]+|[0-9]+[-:][0-9]+)$ ]]; then
                        p_port=$(echo "$p_port" | tr ':' '-')
                        nft add element inet $table $set_tcp { $p_port }
                        nft add element inet $table $set_udp { $p_port }
                        save_config
                        echo -e "${gl_lv}端口 $p_port 已放行。${gl_bai}"
                    else
                        echo -e "${gl_hong}格式错误！${gl_bai}"
                    fi
                    sleep 1
                fi ;;
            3) 
                if [ "$mode" != "None" ]; then
                    list_rules_ui
                    read -p "请输入要删除的端口: " p_port
                    if [[ "$p_port" =~ ^([0-9]+|[0-9]+[-:][0-9]+)$ ]]; then
                        p_port=$(echo "$p_port" | tr ':' '-')
                        nft delete element inet $table $set_tcp { $p_port } 2>/dev/null
                        nft delete element inet $table $set_udp { $p_port } 2>/dev/null
                        save_config
                        echo -e "${gl_hong}端口 $p_port 已移除。${gl_bai}"
                    fi
                    sleep 1
                fi ;;
            4) 
                if [ "$mode" == "Transit" ]; then
                    list_rules_ui
                    echo -e "请输入转发规则:"
                    read -p "1. 本机监听端口 (如 8080): " lp
                    read -p "2. 目标 IP 地址 (如 1.1.1.1): " dip
                    read -p "3. 目标端口     (如 80): " dp
                    if [[ -n "$lp" && -n "$dip" && -n "$dp" ]]; then
                        nft add element inet my_transit fwd_tcp { $lp : $dip . $dp }
                        nft add element inet my_transit fwd_udp { $lp : $dip . $dp }
                        save_config
                        echo -e "${gl_lv}转发规则已添加。${gl_bai}"
                    fi
                    sleep 1
                fi ;;
            5)
                if [ "$mode" == "Transit" ]; then
                    list_rules_ui
                    read -p "请输入要删除转发的本机端口: " lp
                    if [[ -n "$lp" ]]; then
                         nft delete element inet my_transit fwd_tcp { $lp } 2>/dev/null
                         nft delete element inet my_transit fwd_udp { $lp } 2>/dev/null
                         save_config
                         echo -e "${gl_hong}转发规则已移除。${gl_bai}"
                    fi
                    sleep 1
                fi ;;
            8) 
                echo -e "${gl_hong}注意: 这将清空所有规则！${gl_bai}"
                read -p "确定重置吗？(y/n): " confirm
                if [[ "$confirm" == "y" ]]; then
                    echo -e "${gl_huang}正在清除...${gl_bai}"
                    nft delete table inet my_landing 2>/dev/null
                    nft delete table inet my_transit 2>/dev/null
                    echo "#!/usr/sbin/nft -f" > /etc/nftables.conf
                    if systemctl is-active --quiet fail2ban; then 
                        echo -e "${gl_huang}Fail2ban 运行正常，无需重启。${gl_bai}"
                    fi
                    mode="None"
                    echo -e "${gl_lv}已重置(Docker/Fail2ban 不受影响)。${gl_bai}"
                    sleep 1
                fi ;;
            0) return ;;
            *) echo "无效选项" ;;
        esac
    done
}
