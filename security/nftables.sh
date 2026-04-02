#!/bin/bash

# ==========================================
#  通用防火墙模块 (Nftables 终极解耦与安全版)
# ==========================================

NFT_GLOBAL_LIST="/etc/nft_global_ports.list"  # 格式: proto port (例: tcp 80)
NFT_IP_LIST="/etc/nft_ip_ports.list"          # 格式: ip proto port (例: 1.1.1.1 tcp 3306)
NFT_HY2_CONF="/etc/nft_hy2_hop.conf"          # 格式: start end target (例: 10000 20000 443)

# [核心安全] 动态获取真实 SSH 端口
detect_ssh_port() {
    local port=$(sshd -T 2>/dev/null | grep -i '^port ' | awk '{print $2}' | head -n 1)
    echo "${port:-22}"
}

# [输入校验] 验证端口号合法性 (支持单端口 80 或 范围 5000-6000)
validate_port() {
    local p=$1
    # 如果是纯数字单端口
    if [[ "$p" =~ ^[0-9]+$ ]]; then
        if [ "$p" -ge 1 ] && [ "$p" -le 65535 ]; then return 0; else return 1; fi
    # 如果是端口范围 (如 5000-6000)
    elif [[ "$p" =~ ^[0-9]+-[0-9]+$ ]]; then
        local p1=$(echo "$p" | cut -d'-' -f1)
        local p2=$(echo "$p" | cut -d'-' -f2)
        if [ "$p1" -ge 1 ] && [ "$p1" -le 65535 ] && [ "$p2" -ge 1 ] && [ "$p2" -le 65535 ] && [ "$p1" -lt "$p2" ]; then
            return 0
        else
            return 1
        fi
    else
        return 1
    fi
}

# [输入校验] 验证 IP 地址合法性 (粗略但安全地拦截乱码)
validate_ip() {
    local ip=$1
    # IPv4 格式检查 (仅检查结构 x.x.x.x)
    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then return 0; fi
    # IPv6 格式检查 (检查是否包含冒号和合法的十六进制字符)
    if [[ "$ip" =~ ^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}$ ]]; then return 0; fi
    return 1
}

# [核心引擎] 声明式重建 (优先级 -10，双栈兼容，附带顶级防线)
rebuild_nftables() {
    local ssh_p=$(detect_ssh_port)
    
    # 确保文件存在
    touch "$NFT_GLOBAL_LIST" "$NFT_IP_LIST"

    # 生成配置头部与 Input 基础链
    cat > /etc/nftables.conf << EOF
#!/usr/sbin/nft -f

# 1. 创建独立沙盒表
table inet my_firewall {}
delete table inet my_firewall

table inet my_firewall {
    # [门卫] 纯粹的入站管控
    chain input {
        # 优先级 -10: 抢在 1Panel 和 Docker 之前做第一道安检
        type filter hook input priority -10; policy drop;

        # 基础通行证
        iif "lo" accept
        ct state established,related accept
        ct state invalid drop
        
        # [新增防线 1：畸形扫描拦截] 丢弃非法的 TCP 新连接 (只允许干净的 SYN 包建立连接)
        ct state new tcp flags & (fin|syn|rst|ack) != syn drop

        # 强制放行当前 SSH 端口防失联
        tcp dport $ssh_p accept

        # [IPv6 生命线] 适配 Oracle 等云环境
        udp dport 546 accept
        # NDP(邻居发现)必须无限制放行，否则 IPv6 会立刻断网
        icmpv6 type { nd-neighbor-solicit, nd-neighbor-advert, nd-router-solicit, nd-router-advert } accept

        # [新增防线 2：原生防 CC] 限制 Ping 频率 (每秒 5 个，峰值 10 个包，多余丢弃)
        icmp type echo-request limit rate 5/second burst 10 packets accept
        icmpv6 type echo-request limit rate 5/second burst 10 packets accept
EOF

    # 如果启用了 Hy2 跳跃，自动放行其目标端口，防止被 input 挡住
    if [ -f "$NFT_HY2_CONF" ]; then
        local target_port=$(awk '{print $3}' "$NFT_HY2_CONF")
        echo "        udp dport $target_port accept comment \"Hy2 Target Auto-Allow\"" >> /etc/nftables.conf
    fi

    echo "        # === 以下为动态自定义放行区 ===" >> /etc/nftables.conf

    # 注入：全局放行端口
    while read proto port; do
        [ -z "$port" ] && continue
        if [ "$proto" == "tcp" ] || [ "$proto" == "both" ]; then
            echo "        tcp dport $port accept" >> /etc/nftables.conf
        fi
        if [ "$proto" == "udp" ] || [ "$proto" == "both" ]; then
            echo "        udp dport $port accept" >> /etc/nftables.conf
        fi
    done < "$NFT_GLOBAL_LIST"

    # 注入：定向 IP 放行
    while read ip proto port; do
        [ -z "$port" ] && continue
        local ip_type="ip"
        [[ "$ip" =~ ":" ]] && ip_type="ip6" # 智能识别 IPv6
        
        if [ "$proto" == "tcp" ] || [ "$proto" == "both" ]; then
            echo "        $ip_type saddr $ip tcp dport $port accept" >> /etc/nftables.conf
        fi
        if [ "$proto" == "udp" ] || [ "$proto" == "both" ]; then
            echo "        $ip_type saddr $ip udp dport $port accept" >> /etc/nftables.conf
        fi
    done < "$NFT_IP_LIST"

    # [新增防线 3：幽灵日志] 在撞墙(Policy Drop)前的一瞬间，记录被拦截的非法包
    cat >> /etc/nftables.conf << 'EOF'
        
        # 记录被 Drop 的日志 (默认隐藏在 dmesg 或 /var/log/kern.log 中)
        log prefix "[Nftables-Block] " level info
    }
EOF

    # [扩展] 注入 Hy2 端口跳跃 (动态 Prerouting 链)
    if [ -f "$NFT_HY2_CONF" ]; then
        read start end target < "$NFT_HY2_CONF"
        cat >> /etc/nftables.conf << EOF

    # [万箭归一] Hy2 端口重定向
    chain prerouting {
        type nat hook prerouting priority dstnat; policy accept;
        udp dport $start-$end redirect to :$target
    }
EOF
    fi

    echo "}" >> /etc/nftables.conf
    
    # 无感应用规则
    nft -f /etc/nftables.conf
    systemctl enable nftables >/dev/null 2>&1
}

# [UI 模块] 规则展示
list_rules_ui() {
    echo -e "${gl_huang}=== 通用防火墙防护面板 ===${gl_bai}"
    echo -e "底层拦截: ${gl_lv}Priority -10 | Policy Drop [✔ 抢占成功]${gl_bai}"
    echo -e "防自锁层: ${gl_lv}SSH Port $(detect_ssh_port) [✔ 已强制放行]${gl_bai}"
    echo -e "V6生命线: ${gl_lv}ICMPv6 & UDP 546 [✔ 适配 Oracle]${gl_bai}"
    echo "------------------------------------------------"
    
    echo -e "${gl_kjlan}[1] 全网放行端口 (Global):${gl_bai}"
    [ -s "$NFT_GLOBAL_LIST" ] && cat -n "$NFT_GLOBAL_LIST" | awk '{print "  " $1 ". [" $2 "] 端口: " $3}' || echo "  (空)"
    
    echo -e "\n${gl_kjlan}[2] 定向 IP 放行 (IP-Bound):${gl_bai}"
    [ -s "$NFT_IP_LIST" ] && cat -n "$NFT_IP_LIST" | awk '{print "  " $1 ". IP: " $2 " | [" $3 "] 端口: " $4}' || echo "  (空)"
    
    echo -e "\n${gl_huang}[3] 端口跳跃引擎 (Hy2 Hopping):${gl_bai}"
    if [ -f "$NFT_HY2_CONF" ]; then
        read start end target < "$NFT_HY2_CONF"
        echo -e "  状态: ${gl_lv}运行中${gl_bai} | 范围: ${start}-${end} -> 目标: ${target} (UDP)"
    else
        echo "  状态: 未启用"
    fi
    echo "------------------------------------------------"
}

nftables_management() {
    # 进门自动检查并静默安装
    if ! command -v nft &> /dev/null; then
        echo -e "${gl_huang}>>> 正在为您静默安装 Nftables 核心组件...${gl_bai}"
        apt update -y >/dev/null 2>&1 && apt install -y nftables >/dev/null 2>&1
    fi

    while true; do
        clear
        echo -e "${gl_kjlan}################################################"
        echo -e "#           高阶防火墙与流量调度中心           #"
        echo -e "################################################${gl_bai}"
        
        if nft list tables | grep -q "my_firewall"; then
            list_rules_ui
            echo -e "${gl_lv} 1.${gl_bai} 添加 [全网放行] 端口"
            echo -e "${gl_lv} 2.${gl_bai} 添加 [定向 IP] 放行端口"
            echo -e "${gl_huang} 3.${gl_bai} 删除自定义放行规则"
            echo -e "------------------------------------------------"
            echo -e "${gl_kjlan} 4.${gl_bai} 配置 Hy2 端口跳跃 (动态 Prerouting)"
            echo -e "${gl_hong} 8.${gl_bai} 彻底卸载防火墙"
        else
            echo -e " 当前状态: ${gl_hong}未初始化 (裸奔状态)${gl_bai}"
            echo -e " 核心逻辑: 仅保护 SSH 与 IPv6 生命线，不干涉转发"
            echo -e "------------------------------------------------"
            echo -e "${gl_lv} 1.${gl_bai} 一键初始化并开启护盾"
        fi
        
        echo -e "${gl_hui} 0. 返回主菜单${gl_bai}"
        echo -e "------------------------------------------------"
        
        read -p "请输入选项: " nf_choice

        case "$nf_choice" in
            1) 
                if ! nft list tables | grep -q "my_firewall"; then
                    echo -e "${gl_huang}>>> 正在初始化沙盒防火墙...${gl_bai}"
                    touch "$NFT_GLOBAL_LIST" "$NFT_IP_LIST"
                    rebuild_nftables
                    echo -e "${gl_lv}初始化完成！${gl_bai}"
                    sleep 1
                else
                    read -p "请输入要全网放行的端口 (如 80 或 5000-6000): " port
                    if ! validate_port "$port"; then
                        echo -e "${gl_hong}错误: 端口必须在 1-65535 之间，范围格式须前小后大 (例: 5000-6000)！${gl_bai}"
                        sleep 2
                        continue
                    fi
                    read -p "请输入协议 (tcp/udp/both，回车默认 both): " proto
                    [ -z "$proto" ] && proto="both"
                    if [[ "$port" =~ ^[0-9-]+$ ]] && [[ "$proto" =~ ^(tcp|udp|both)$ ]]; then
                        echo "$proto $port" >> "$NFT_GLOBAL_LIST"
                        rebuild_nftables
                        echo -e "${gl_lv}规则已添加并生效！${gl_bai}"
                    else
                        echo -e "${gl_hong}格式错误！${gl_bai}"
                    fi
                    sleep 1
                fi
                ;;
            2)
                if nft list tables | grep -q "my_firewall"; then
                    read -p "请输入白名单 IP 地址 (IPv4 或 IPv6): " ip
                    if ! validate_ip "$ip"; then
                        echo -e "${gl_hong}错误: 无效的 IP 地址格式！${gl_bai}"
                        sleep 2
                        continue
                    fi
                    read -p "请输入要对其放行的端口: " port
                    if ! validate_port "$port"; then
                        echo -e "${gl_hong}错误: 端口不合法！${gl_bai}"
                        sleep 2
                        continue
                    fi
                    read -p "请输入协议 (tcp/udp/both，回车默认 both): " proto
                    [ -z "$proto" ] && proto="both"
                    if [ -n "$ip" ] && [ -n "$port" ]; then
                        echo "$ip $proto $port" >> "$NFT_IP_LIST"
                        rebuild_nftables
                        echo -e "${gl_lv}定向放行已添加并生效！${gl_bai}"
                    else
                        echo -e "${gl_hong}输入无效！${gl_bai}"
                    fi
                    sleep 1
                fi
                ;;
            3)
                if nft list tables | grep -q "my_firewall"; then
                    echo -e "${gl_huang}请选择要删除的规则类型:${gl_bai}"
                    echo "1. 删除全网放行规则"
                    echo "2. 删除定向 IP 规则"
                    read -p "请选择 (1/2): " del_type
                    if [ "$del_type" == "1" ]; then
                        read -p "请输入要删除的 [端口号] 以移除对应的全局规则: " port
                        sed -i "/ ${port}$/d" "$NFT_GLOBAL_LIST" 2>/dev/null
                        rebuild_nftables
                        echo -e "${gl_lv}包含端口 ${port} 的全局规则已移除。${gl_bai}"
                    elif [ "$del_type" == "2" ]; then
                        read -p "请输入要删除的 [IP 地址] 以移除对应的定向规则: " ip
                        sed -i "/^${ip} /d" "$NFT_IP_LIST" 2>/dev/null
                        rebuild_nftables
                        echo -e "${gl_lv}包含 IP ${ip} 的定向规则已移除。${gl_bai}"
                    fi
                    sleep 1
                fi
                ;;
            4)
                if nft list tables | grep -q "my_firewall"; then
                    if [ -f "$NFT_HY2_CONF" ]; then
                        echo -e "${gl_huang}检测到已配置端口跳跃！${gl_bai}"
                        read -p "是否关闭当前跳跃功能？(y/n): " close_hop
                        if [[ "$close_hop" == "y" ]]; then
                            rm -f "$NFT_HY2_CONF"
                            rebuild_nftables
                            echo -e "${gl_lv}已销毁跳跃引擎。${gl_bai}"
                        fi
                    else
                        echo -e "配置 Hy2 UDP 端口跳跃 (万箭归一)"
                        read -p "请输入起始跳跃端口 (例: 10000): " start
                        read -p "请输入结束跳跃端口 (例: 20000): " end
                        read -p "请输入真实目标端口 (例: 443): " target                  
                        # 使用我们新写的 validate_port 函数，并确保 start 小于 end
                        if validate_port "$start" && validate_port "$end" && validate_port "$target" && [ "$start" -lt "$end" ]; then
                            # 预警检查：防止跳跃范围误伤 546 端口
                            if [ "$start" -le 546 ] && [ "$end" -ge 546 ]; then
                                echo -e "${gl_hong}警告: 范围包含了 IPv6 生命线 (UDP 546)，系统已拒绝该范围！${gl_bai}"
                            else
                                echo "$start $end $target" > "$NFT_HY2_CONF"
                                rebuild_nftables
                                echo -e "${gl_lv}端口跳跃引擎已启动！流量已被重定向至 $target。${gl_bai}"
                            fi
                        else
                            echo -e "${gl_hong}端口格式错误！(请确保输入的是合法数字，且起始端口小于结束端口)${gl_bai}"
                        fi
                    fi
                    sleep 2
                fi
                ;;
            8) 
                if nft list tables | grep -q "my_firewall"; then
                    echo -e "${gl_hong}警告: 这将完全关闭防火墙 (裸奔模式)！${gl_bai}"
                    read -p "确定卸载吗？(y/n): " confirm
                    if [[ "$confirm" == "y" ]]; then
                        nft delete table inet my_firewall 2>/dev/null
                        rm -f "$NFT_GLOBAL_LIST" "$NFT_IP_LIST" "$NFT_HY2_CONF" /etc/nftables.conf
                        systemctl disable nftables 2>/dev/null
                        echo -e "${gl_lv}门卫已撤离，系统回归开放状态。${gl_bai}"
                        sleep 1
                    fi
                fi
                ;;
            0) return ;;
            *) echo -e "${gl_hong}无效选项${gl_bai}"; sleep 1 ;;
        esac
    done
}
