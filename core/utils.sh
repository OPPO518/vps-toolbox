#!/bin/bash

# ===== 全局颜色变量 =====
gl_hong='\033[31m'
gl_lv='\033[32m'
gl_huang='\033[33m'
gl_lan='\033[34m'
gl_bai='\033[0m'
gl_zi='\033[35m'
gl_kjlan='\033[96m'
gl_hui='\033[37m'

# ===== 辅助函数: 获取国旗 Emoji =====
get_flag_local() {
    case "$1" in
        CN) echo "🇨🇳" ;; HK) echo "🇭🇰" ;; MO) echo "🇲🇴" ;; TW) echo "🇹🇼" ;;
        US) echo "🇺🇸" ;; JP) echo "🇯🇵" ;; KR) echo "🇰🇷" ;; SG) echo "🇸🇬" ;;
        RU) echo "🇷🇺" ;; DE) echo "🇩🇪" ;; GB) echo "🇬🇧" ;; FR) echo "🇫🇷" ;;
        NL) echo "🇳🇱" ;; CA) echo "🇨🇦" ;; AU) echo "🇦🇺" ;; IN) echo "🇮🇳" ;;
        TH) echo "🇹🇭" ;; VN) echo "🇻🇳" ;; MY) echo "🇲🇾" ;; ID) echo "🇮🇩" ;;
        BR) echo "🇧🇷" ;; ZA) echo "🇿🇦" ;; IT) echo "🇮🇹" ;; ES) echo "🇪🇸" ;;
        *) echo "🌐" ;; 
    esac
}

# ===== 辅助函数: IP信息获取 =====
ip_address() {
    get_public_ip() { curl -s https://ipinfo.io/ip && echo; }
    get_local_ip() { ip route get 8.8.8.8 2>/dev/null | grep -oP 'src \K[^ ]+' || hostname -I 2>/dev/null | awk '{print $1}'; }
    
    public_ip=$(get_public_ip)
    isp_info=$(curl -s --max-time 3 http://ipinfo.io/org)
    
    if echo "$isp_info" | grep -Eiq 'mobile|unicom|telecom'; then 
        ipv4_address=$(get_local_ip)
    else 
        ipv4_address="$public_ip"
    fi
    ipv6_address=$(curl -s --max-time 1 https://v6.ipinfo.io/ip && echo)
    country_code=$(curl -s --max-time 3 https://ipinfo.io/country | tr -d '\n')
    flag=$(get_flag_local "$country_code")
}

# ===== 辅助函数: 网络流量统计 =====
output_status() {
    output=$(awk 'BEGIN { rx_total = 0; tx_total = 0 }
        $1 ~ /^(eth|ens|enp|eno)[0-9]+/ { rx_total += $2; tx_total += $10 }
        END {
            rx_units = "B"; tx_units = "B";
            if (rx_total > 1024) { rx_total /= 1024; rx_units = "K"; }
            if (rx_total > 1024) { rx_total /= 1024; rx_units = "M"; }
            if (rx_total > 1024) { rx_total /= 1024; rx_units = "G"; }
            if (tx_total > 1024) { tx_total /= 1024; tx_units = "K"; }
            if (tx_total > 1024) { tx_total /= 1024; tx_units = "M"; }
            if (tx_total > 1024) { tx_total /= 1024; tx_units = "G"; }
            printf("%.2f%s %.2f%s\n", rx_total, rx_units, tx_total, tx_units);
        }' /proc/net/dev)
    rx=$(echo "$output" | awk '{print $1}')
    tx=$(echo "$output" | awk '{print $2}')
}

# ===== 辅助函数: 时区检测 =====
current_timezone() {
    if grep -q 'Alpine' /etc/issue; then 
        date +"%Z %z"
    else 
        timedatectl | grep "Time zone" | awk '{print $3}'
    fi
}

# ===== 辅助函数: 提取 SSH 端口 (去重优化) =====
detect_ssh_port() {
    local port=$(ss -tlnp | grep 'sshd' | awk '{print $4}' | awk -F: '{print $NF}' | head -n 1)
    if [ -z "$port" ]; then port="22"; fi
    echo "$port"
}

# ===== 辅助函数: 自动放行端口 (去重优化) =====
ensure_port_open() {
    local port="$1"
    if command -v nft &>/dev/null; then
        local t="" s="" su=""
        if nft list tables | grep -q "my_landing"; then t="my_landing"; s="allowed_tcp"; su="allowed_udp";
        elif nft list tables | grep -q "my_transit"; then t="my_transit"; s="local_tcp"; su="local_udp"; else return; fi
        
        if ! nft list set inet $t $s 2>/dev/null | grep -q "$port"; then
            echo -e "${gl_huang}检测到防火墙，自动放行端口 $port...${gl_bai}"
            nft add element inet $t $s { $port }; nft add element inet $t $su { $port }
            # 安全保存
            echo "#!/usr/sbin/nft -f" > /etc/nftables.conf
            nft list ruleset >> /etc/nftables.conf
        fi
    fi
}
