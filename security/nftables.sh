#!/bin/bash

# ==========================================
#  通用防火墙模块 (Nftables 融合进化版)
# ==========================================

NFT_TCP_LIST="/etc/nft_tcp_ports.list"
NFT_UDP_LIST="/etc/nft_udp_ports.list"

# [核心安全] 获取真实 SSH 端口
detect_ssh_port() {
    local port=$(sshd -T 2>/dev/null | grep -i '^port ' | awk '{print $2}' | head -n 1)
    echo "${port:-22}"
}

# [核心引擎] 声明式重建 (绝不产生重复规则，绝不误杀 Docker/Fail2ban)
rebuild_nftables() {
    local ssh_p=$(detect_ssh_port)
    
    # 动态组装端口集合
    local tcp_ports=""
    local udp_ports=""
    [ -s "$NFT_TCP_LIST" ] && tcp_ports=$(paste -sd "," "$NFT_TCP_LIST")
    [ -s "$NFT_UDP_LIST" ] && udp_ports=$(paste -sd "," "$NFT_UDP_LIST")

    cat > /etc/nftables.conf << EOF
#!/usr/sbin/nft -f

# 仅清理并重建我们自己的表，绝对安全
table inet my_firewall {}
delete table inet my_firewall

table inet my_firewall {
    chain input {
        type filter hook input priority 0; policy drop;

        iif "lo" accept
        ct state established,related accept
        ct state invalid drop
        
        # 放行 Ping (ICMP)
        icmp type echo-request accept
        icmpv6 type { echo-request, nd-neighbor-solicit, nd-neighbor-advert, nd-router-solicit, nd-router-advert } accept
        
        # 强制放行当前 SSH 端口防失联
        tcp dport $ssh_p accept
EOF

    # 动态注入自定义 TCP/UDP 端口
    [ -n "$tcp_ports" ] && echo "        tcp dport { $tcp_ports } accept" >> /etc/nftables.conf
    [ -n "$udp_ports" ] && echo "        udp dport { $udp_ports } accept" >> /etc/nftables.conf

    # 封尾并彻底开放转发
    cat >> /etc/nftables.conf << 'EOF'
    }

    chain forward {
        # 开放底层转发，为后续独立中转模块铺路
        type filter hook forward priority 0; policy accept;
    }

    chain output {
        type filter hook output priority 0; policy accept;
    }
}
EOF
    # 直接加载，不中断现有网络
    nft -f /etc/nftables.conf
    systemctl enable nftables >/dev/null 2>&1
}

# [视觉 UI] 规则展示
list_rules_ui() {
    echo -e "${gl_huang}=== 通用防火墙规则概览 ===${gl_bai}"
    echo -e "系统防自锁: ${gl_lv}SSH Port $(detect_ssh_port) [✔ 已强制放行]${gl_bai}"
    echo -e "底层转发流: ${gl_lv}Forward Chain [✔ 已全量开放]${gl_bai}"
    echo "------------------------------------------------"
    echo -e "${gl_kjlan}=== 自定义端口放行 ===${gl_bai}"
    
    local t_list="无"; local u_list="无"
    [ -s "$NFT_TCP_LIST" ] && t_list=$(paste -sd ", " "$NFT_TCP_LIST")
    [ -s "$NFT_UDP_LIST" ] && u_list=$(paste -sd ", " "$NFT_UDP_LIST")
    
    echo -e "[TCP] ${gl_lv}${t_list}${gl_bai}"
    echo -e "[UDP] ${gl_lv}${u_list}${gl_bai}"
    echo "------------------------------------------------"
}

nftables_management() {
    # 进门自动检查并安装，保持极简体验
    if ! command -v nft &> /dev/null; then
        echo -e "${gl_huang}>>> 正在为您静默安装 Nftables 核心组件...${gl_bai}"
        apt update -y >/dev/null 2>&1 && apt install -y nftables >/dev/null 2>&1
    fi

    while true; do
        clear
        echo -e "${gl_kjlan}################################################"
        echo -e "#           通用防火墙管理 (Nftables)          #"
        echo -e "################################################${gl_bai}"
        
        if nft list tables | grep -q "my_firewall"; then
            list_rules_ui
            echo -e "${gl_lv} 1.${gl_bai} 添加放行端口 (支持范围如 5000-6000)"
            echo -e "${gl_huang} 2.${gl_bai} 删除放行端口"
            echo -e "------------------------------------------------"
            echo -e "${gl_hong} 8.${gl_bai} 彻底卸载防火墙"
        else
            echo -e " 当前状态: ${gl_hong}未初始化${gl_bai}"
            echo -e " 核心逻辑: 仅保护 SSH 端口，开放 Forward 转发"
            echo -e "------------------------------------------------"
            echo -e "${gl_lv} 1.${gl_bai} 一键初始化并启用通用防火墙"
        fi
        
        echo -e "${gl_hui} 0. 返回主菜单${gl_bai}"
        echo -e "------------------------------------------------"
        
        read -p "请输入选项: " nf_choice

        case "$nf_choice" in
            1) 
                if ! nft list tables | grep -q "my_firewall"; then
                    echo -e "${gl_huang}>>> 正在初始化防火墙...${gl_bai}"
                    touch "$NFT_TCP_LIST" "$NFT_UDP_LIST"
                    rebuild_nftables
                    echo -e "${gl_lv}初始化完成！${gl_bai}"
                    read -p "按回车继续..."
                else
                    echo -e "${gl_hui}提示: 支持单端口(80) 或 范围(50000-60000)${gl_bai}"
                    read -p "请输入要放行的端口: " p_port
                    if [[ "$p_port" =~ ^([0-9]+|[0-9]+[-:][0-9]+)$ ]]; then
                        p_port=$(echo "$p_port" | tr ':' '-')
                        read -p "请输入协议 (tcp/udp/both，回车默认 both): " proto
                        [ -z "$proto" ] && proto="both"
                        
                        if [[ "$proto" == "tcp" || "$proto" == "both" ]] && ! grep -q "^${p_port}$" "$NFT_TCP_LIST" 2>/dev/null; then
                            echo "$p_port" >> "$NFT_TCP_LIST"
                        fi
                        if [[ "$proto" == "udp" || "$proto" == "both" ]] && ! grep -q "^${p_port}$" "$NFT_UDP_LIST" 2>/dev/null; then
                            echo "$p_port" >> "$NFT_UDP_LIST"
                        fi
                        rebuild_nftables
                        echo -e "${gl_lv}规则已更新并实时生效！${gl_bai}"
                    else
                        echo -e "${gl_hong}格式错误！${gl_bai}"
                    fi
                    sleep 1
                fi
                ;;
            2) 
                if nft list tables | grep -q "my_firewall"; then
                    read -p "请输入要删除的端口 (精确匹配): " p_port
                    sed -i "/^${p_port}$/d" "$NFT_TCP_LIST" 2>/dev/null
                    sed -i "/^${p_port}$/d" "$NFT_UDP_LIST" 2>/dev/null
                    rebuild_nftables
                    echo -e "${gl_huang}端口 $p_port 已移除。${gl_bai}"
                    sleep 1
                fi
                ;;
            8) 
                if nft list tables | grep -q "my_firewall"; then
                    echo -e "${gl_hong}警告: 这将完全关闭防火墙！${gl_bai}"
                    read -p "确定卸载吗？(y/n): " confirm
                    if [[ "$confirm" == "y" ]]; then
                        nft delete table inet my_firewall 2>/dev/null
                        rm -f "$NFT_TCP_LIST" "$NFT_UDP_LIST" /etc/nftables.conf
                        systemctl disable nftables 2>/dev/null
                        echo -e "${gl_lv}防火墙已卸载 (Docker/Fail2ban 不受影响)。${gl_bai}"
                        sleep 1
                    fi
                fi
                ;;
            0) return ;;
            *) echo -e "${gl_hong}无效选项${gl_bai}"; sleep 1 ;;
        esac
    done
}
