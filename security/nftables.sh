#!/bin/bash

# ==========================================
#  通用防火墙模块 (Nftables 终极解耦与集合版)
# ==========================================

NFT_GLOBAL_LIST="/etc/nft_global_ports.list"  # 格式: proto port (例: tcp 80,443,5000-6000)
NFT_IP_LIST="/etc/nft_ip_ports.list"          # 格式: ip proto port (例: 1.1.1.1 tcp 3306)
NFT_HY2_CONF="/etc/nft_hy2_hop.conf"          # 格式: start end target (例: 10000 20000 443)

# [核心安全] 动态获取真实 SSH 端口
detect_ssh_port() {
    local port=$(sshd -T 2>/dev/null | grep -i '^port ' | awk '{print $2}' | head -n 1)
    echo "${port:-22}"
}

# [输入校验 升级版] 验证端口合法性 (支持混合输入: 80, 443, 55000:60000)
validate_port() {
    local raw_input="$1"
    
    # [清洗] 1. 去除所有空格 2. 把中文逗号换成英文逗号 3. 把冒号换成短横线
    local cleaned=$(echo "$raw_input" | tr -d ' ' | sed 's/，/,/g' | tr ':' '-')
    [ -z "$cleaned" ] && return 1
    
    # 按照逗号分割，逐个校验
    IFS=',' read -r -a port_array <<< "$cleaned"
    for p in "${port_array[@]}"; do
        # 如果是单端口
        if [[ "$p" =~ ^[0-9]+$ ]]; then
            if [ "$p" -lt 1 ] || [ "$p" -gt 65535 ]; then return 1; fi
        # 如果是端口范围
        elif [[ "$p" =~ ^[0-9]+-[0-9]+$ ]]; then
            local p1=$(echo "$p" | cut -d'-' -f1)
            local p2=$(echo "$p" | cut -d'-' -f2)
            if [ "$p1" -lt 1 ] || [ "$p1" -gt 65535 ] || [ "$p2" -lt 1 ] || [ "$p2" -gt 65535 ] || [ "$p1" -ge "$p2" ]; then
                return 1
            fi
        else
            return 1 # 格式既不是单端口也不是规范范围
        fi
    done
    
    # 校验全部通过，导出清洗后的标准格式，供外部使用
    VALIDATED_PORT="$cleaned"
    return 0
}

# [输入校验] 验证 IP 地址合法性 (粗略但安全地拦截乱码)
validate_ip() {
    local ip=$1
    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then return 0; fi
    if [[ "$ip" =~ ^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}$ ]]; then return 0; fi
    return 1
}

# [核心引擎 绝对安全稳定版] 声明式重建
rebuild_nftables() {
    local ssh_p=$(detect_ssh_port)
    touch "$NFT_GLOBAL_LIST" "$NFT_IP_LIST"

    # --- 1. 动态提取并拼接全局端口列表 ---
    local tcp_ports=""
    local udp_ports=""
    while read proto port; do
        [ -z "$port" ] && continue
        if [ "$proto" == "tcp" ] || [ "$proto" == "both" ]; then
            if [ -z "$tcp_ports" ]; then tcp_ports="$port"; else tcp_ports="$tcp_ports, $port"; fi
        fi
        if [ "$proto" == "udp" ] || [ "$proto" == "both" ]; then
            if [ -z "$udp_ports" ]; then udp_ports="$port"; else udp_ports="$udp_ports, $port"; fi
        fi
    done < "$NFT_GLOBAL_LIST"

    local tcp_elements_str=""
    [ -n "$tcp_ports" ] && tcp_elements_str="elements = { $tcp_ports }"
    
    local udp_elements_str=""
    [ -n "$udp_ports" ] && udp_elements_str="elements = { $udp_ports }"

    # --- 2. 注入核心配置与集合 ---
    cat > /etc/nftables.conf << EOF
#!/usr/sbin/nft -f

# 优雅销毁旧表
table inet my_firewall {}
delete table inet my_firewall
table ip my_nat {}
delete table ip my_nat

# ==========================================
# 核心过滤表 (Filter)
# ==========================================
table inet my_firewall {
    # [优雅声明] 全局端口池
    set global_tcp { 
        type inet_service; flags interval; $tcp_elements_str 
    }
    set global_udp { 
        type inet_service; flags interval; $udp_elements_str 
    }

    chain input {
        type filter hook input priority 0; policy drop;

        # --- [完美修复 1] 通用虚拟网卡与回环放行 ---
        # 支持前缀匹配，即使没装 Docker/Tailscale 也不会报错
        iifname { "lo", "docker*", "br-*", "tailscale*", "wg*" } accept

        # 状态跟踪 (放行内部主动发起连接的回程流量)
        ct state established,related accept
        ct state invalid drop
        ct state new tcp flags & (fin|syn|rst|ack) != syn drop

        # [防失联与生命线]
        tcp dport $ssh_p accept
        udp dport 546 accept
        icmpv6 type { nd-neighbor-solicit, nd-neighbor-advert, nd-router-solicit, nd-router-advert } accept
        icmp type echo-request limit rate 5/second burst 10 packets accept
        icmpv6 type echo-request limit rate 5/second burst 10 packets accept

        # === [集合放行区] ===
        tcp dport @global_tcp accept
        udp dport @global_udp accept
EOF

    # === 3. 追加特殊规则 (Hy2 & 定向IP) ===
    if [ -f "$NFT_HY2_CONF" ]; then
        local target_port=$(awk '{print $3}' "$NFT_HY2_CONF")
        echo "        udp dport $target_port accept comment \"Hy2 Target Auto-Allow\"" >> /etc/nftables.conf
    fi

    echo "        # === 定向 IP 放行区 ===" >> /etc/nftables.conf
    while read ip proto port; do
        [ -z "$port" ] && continue
        local ip_type="ip"
        [[ "$ip" =~ ":" ]] && ip_type="ip6"
        
        local nft_port="$port"
        [[ "$port" =~ "," ]] && nft_port="{ $port }"
        
        if [ "$proto" == "tcp" ] || [ "$proto" == "both" ]; then
            echo "        $ip_type saddr $ip tcp dport $nft_port accept" >> /etc/nftables.conf
        fi
        if [ "$proto" == "udp" ] || [ "$proto" == "both" ]; then
            echo "        $ip_type saddr $ip udp dport $nft_port accept" >> /etc/nftables.conf
        fi
    done < "$NFT_IP_LIST"

    # === 4. 防洪日志与 FORWARD 转发链 ===
    cat >> /etc/nftables.conf << 'EOF'
        
        # --- [完美修复 3] 防洪日志 ---
        # 限制每分钟最多记录 3 条，防恶意扫描导致硬盘爆满
        limit rate 3/minute burst 5 packets log prefix "[Nftables-Block] " level warn
    }

    # --- [完美修复 2] 容器转发链 (FORWARD) ---
    # 没有这条链，Docker 和虚拟网卡能和宿主机通信，但出不了公网
    chain forward {
        type filter hook forward priority 0; policy drop;
        ct state established,related accept
        iifname { "docker*", "br-*", "tailscale*", "wg*" } accept
    }
EOF

    # [扩展] 注入 Hy2 端口跳跃
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

    # ==========================================
    # 独立 NAT 伪装表 (通用内网出海)
    # ==========================================
    cat >> /etc/nftables.conf << 'EOF'
table ip my_nat {
    chain postrouting {
        type nat hook postrouting priority 100; policy accept;
        
        # --- [完美修复 4] 自动化 NAT 伪装 ---
        # 只针对局域网 IP 出站进行 MASQUERADE
        # 覆盖范围: Docker(172.16.x.x), Tailscale(100.x.x.x), 常用内网(192.168/10.x.x.x)
        ip saddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 100.64.0.0/10 } masquerade
    }
}
EOF
    
    # 强制重载并唤醒防火墙
    nft -f /etc/nftables.conf
    systemctl restart nftables
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
    if ! command -v nft &> /dev/null; then
        echo -e "${gl_huang}>>> 正在为您静默安装 Nftables 核心组件...${gl_bai}"
        apt update -y >/dev/null 2>&1 && apt install -y nftables >/dev/null 2>&1
    fi

    while true; do
        clear
        echo -e "${gl_kjlan}################################################"
        echo -e "#            高阶防火墙与流量调度中心          #"
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
                    read -p "请输入放行端口 (支持多端口/范围，例: 80,443,50000:60000): " port
                    if ! validate_port "$port"; then
                        echo -e "${gl_hong}错误: 端口格式不合法！${gl_bai}"
                        sleep 2
                        continue
                    fi
                    port="$VALIDATED_PORT" # 使用清洗后的标准格式
                    
                    read -p "请选择协议 [ 1=tcp | 2=udp | 回车默认 both ]: " proto_input
                    case "$proto_input" in
                        1|tcp) proto="tcp" ;;
                        2|udp) proto="udp" ;;
                        *) proto="both" ;;
                    esac
                    
                    echo "$proto $port" >> "$NFT_GLOBAL_LIST"
                    rebuild_nftables
                    echo -e "${gl_lv}规则已添加并生效！${gl_bai}"
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
                    
                    read -p "请输入放行端口 (支持多端口/范围，例: 80,443,50000:60000): " port
                    if ! validate_port "$port"; then
                        echo -e "${gl_hong}错误: 端口不合法！${gl_bai}"
                        sleep 2
                        continue
                    fi
                    port="$VALIDATED_PORT" # 使用清洗后的标准格式
                    
                    read -p "请选择协议 [ 1=tcp | 2=udp | 回车默认 both ]: " proto_input
                    case "$proto_input" in
                        1|tcp) proto="tcp" ;;
                        2|udp) proto="udp" ;;
                        *) proto="both" ;;
                    esac
                    
                    echo "$ip $proto $port" >> "$NFT_IP_LIST"
                    rebuild_nftables
                    echo -e "${gl_lv}定向放行已添加并生效！${gl_bai}"
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
                        read -p "请输入要删除的 [端口串] 以移除对应的全局规则: " port
                        if ! validate_port "$port"; then
                            echo -e "${gl_hong}错误: 端口格式不合法！${gl_bai}"
                        elif grep -q " ${VALIDATED_PORT}$" "$NFT_GLOBAL_LIST" 2>/dev/null; then
                            sed -i "/ ${VALIDATED_PORT}$/d" "$NFT_GLOBAL_LIST"
                            rebuild_nftables
                            echo -e "${gl_lv}包含端口 ${VALIDATED_PORT} 的全局规则已成功移除。${gl_bai}"
                        else
                            echo -e "${gl_huang}提示: 规则列表中未找到关于端口 ${VALIDATED_PORT} 的记录。${gl_bai}"
                        fi
                        
                    elif [ "$del_type" == "2" ]; then
                        read -p "请输入要删除的 [IP 地址] 以移除对应的定向规则: " ip
                        if ! validate_ip "$ip"; then
                            echo -e "${gl_hong}错误: IP 地址格式不合法！${gl_bai}"
                        elif grep -q "^${ip} " "$NFT_IP_LIST" 2>/dev/null; then
                            sed -i "/^${ip} /d" "$NFT_IP_LIST"
                            rebuild_nftables
                            echo -e "${gl_lv}包含 IP ${ip} 的定向规则已成功移除。${gl_bai}"
                        else
                            echo -e "${gl_huang}提示: 规则列表中未找到关于 IP ${ip} 的记录。${gl_bai}"
                        fi
                    else
                        echo -e "${gl_hong}无效的选择！${gl_bai}"
                    fi
                    sleep 2
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
                        read -p "请输入起始跳跃端口 (纯数字，例: 10000): " start
                        read -p "请输入结束跳跃端口 (纯数字，例: 20000): " end
                        read -p "请输入真实目标端口 (纯数字，例: 443): " target                  
                        
                        if validate_port "$start" && validate_port "$end" && validate_port "$target" && [ "$start" -lt "$end" ] 2>/dev/null; then
                            if [ "$start" -le 546 ] && [ "$end" -ge 546 ]; then
                                echo -e "${gl_hong}警告: 范围包含了 IPv6 生命线 (UDP 546)，系统已拒绝该范围！${gl_bai}"
                            else
                                echo "$start $end $target" > "$NFT_HY2_CONF"
                                rebuild_nftables
                                echo -e "${gl_lv}端口跳跃引擎已启动！流量已被重定向至 $target。${gl_bai}"
                            fi
                        else
                            echo -e "${gl_hong}端口格式错误！(请确保输入的是单端口纯数字，且起始小于结束)${gl_bai}"
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
