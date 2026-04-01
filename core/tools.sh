#!/bin/bash

linux_info() {
    clear
    echo -e "${gl_huang}正在深度采集系统数据...${gl_bai}"
    
    # 基础数据采集 (依赖 utils.sh 里的函数)
    ip_address
    output_status
    
    # 1. 实时负载计算
    local cpu_perc=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}' | cut -d. -f1)
    
    local mem_total=$(free -m | awk '/^Mem:/{print $2}')
    local mem_used=$(free -m | awk '/^Mem:/{print $3}')
    local mem_perc=$(( mem_used * 100 / mem_total ))
    
    local swap_total=$(free -m | awk '/^Swap:/{print $2}')
    local swap_used=$(free -m | awk '/^Swap:/{print $3}')
    local swap_perc=0
    [ "$swap_total" -gt 0 ] && swap_perc=$(( swap_used * 100 / swap_total ))
    
    local disk_info_raw=$(df -h / | awk 'NR==2 {print $3,$2,$5}')
    local disk_used_text=$(echo $disk_info_raw | awk '{print $1}')
    local disk_total_text=$(echo $disk_info_raw | awk '{print $2}')
    local disk_perc=$(echo $disk_info_raw | awk '{print $3}' | tr -d '%')

    # 2. 其他静态信息
    local cpu_info=$(lscpu | awk -F': +' '/Model name:/ {print $2; exit}')
    local cpu_cores=$(nproc)
    local cpu_freq=$(cat /proc/cpuinfo | grep "MHz" | head -n 1 | awk '{printf "%.1f GHz", $4/1000}')
    local load=$(uptime | awk -F'load average:' '{print $2}' | sed 's/ //')
    local dns_addresses=$(awk '/^nameserver/{printf "%s ", $2} END {print ""}' /etc/resolv.conf)
    local tcp_count=$(ss -t | wc -l)
    local udp_count=$(ss -u | wc -l)
    local runtime=$(uptime -p | sed 's/up //')
    local os_info=$(grep PRETTY_NAME /etc/os-release | cut -d '=' -f2 | tr -d '"')
    local congestion_algorithm=$(sysctl -n net.ipv4.tcp_congestion_control)
    local queue_algorithm=$(sysctl -n net.core.default_qdisc)

    # 3. 渲染界面
    echo -e "\n${gl_lv}========== 实时资源负载 (Resource Load) ==========${gl_bai}"
    printf "${gl_kjlan}%-10s${gl_bai} " "CPU 占用:" && draw_bar $cpu_perc 25 && echo -e " (负载: $load)"
    printf "${gl_kjlan}%-10s${gl_bai} " "物理内存:" && draw_bar $mem_perc 25 && echo -e " ($mem_used/$mem_total MB)"
    printf "${gl_kjlan}%-10s${gl_bai} " "虚拟内存:" && draw_bar $swap_perc 25 && echo -e " ($swap_used/$swap_total MB)"
    printf "${gl_kjlan}%-10s${gl_bai} " "硬盘空间:" && draw_bar $disk_perc 25 && echo -e " ($disk_used_text/$disk_total_text)"

    echo -e "\n${gl_lv}========== 硬件与系统信息 (Hardware) ==========${gl_bai}"
    printf "${gl_kjlan}%-12s${gl_bai}: %s\n" "主机名称" "$(hostname) ($country_code $flag)"
    printf "${gl_kjlan}%-12s${gl_bai}: %s\n" "操作系统" "$os_info"
    printf "${gl_kjlan}%-12s${gl_bai}: %s\n" "内核版本" "$(uname -r)"
    echo -e "${gl_hui}------------------------------------------------${gl_bai}"
    printf "${gl_kjlan}%-12s${gl_bai}: %s\n" "CPU 架构" "$(uname -m)"
    printf "${gl_kjlan}%-12s${gl_bai}: %s\n" "CPU 型号" "$cpu_info"
    printf "${gl_kjlan}%-12s${gl_bai}: %s\n" "核心/频率" "$cpu_cores 核 / $cpu_freq"
    printf "${gl_kjlan}%-12s${gl_bai}: %s / %s\n" "总流量" "RX: $rx" "TX: $tx"
    printf "${gl_kjlan}%-12s${gl_bai}: %s\n" "连接统计" "$tcp_count (TCP) | $udp_count (UDP)"
    printf "${gl_kjlan}%-12s${gl_bai}: %s %s\n" "网络算法" "$congestion_algorithm" "$queue_algorithm"

    echo -e "\n${gl_lv}========== 网络与地理信息 (Network) ==========${gl_bai}"
    printf "${gl_kjlan}%-12s${gl_bai}: %s\n" "运营商" "$isp_info"
    [ -n "$ipv4_address" ] && printf "${gl_kjlan}%-12s${gl_bai}: %s\n" "IPv4地址" "$ipv4_address"
    [ -n "$ipv6_address" ] && printf "${gl_kjlan}%-12s${gl_bai}: %s\n" "IPv6地址" "$ipv6_address"
    printf "${gl_kjlan}%-12s${gl_bai}: %s\n" "DNS 地址" "$dns_addresses"
    printf "${gl_kjlan}%-12s${gl_bai}: %s %s\n" "地理位置" "$country" "$city"
    echo -e "${gl_hui}------------------------------------------------${gl_bai}"
    printf "${gl_kjlan}%-12s${gl_bai}: %s\n" "系统时间" "$(date "+%Y-%m-%d %H:%M:%S") ($(current_timezone))"
    printf "${gl_kjlan}%-12s${gl_bai}: %s\n" "运行时长" "$runtime"
    
    echo ""
    read -r -p "按回车键返回主菜单..."
}

linux_update() {
    echo -e "${gl_huang}正在进行系统更新...${gl_bai}"
    if command -v apt &>/dev/null; then
        apt update -y && apt full-upgrade -y
        if [ -f /var/run/reboot-required ]; then
            echo -e "${gl_hong}注意：检测到内核或核心组件更新，需要重启才能生效！${gl_bai}"
            read -p "是否立即重启系统？(y/n): " reboot_choice
            [[ "$reboot_choice" =~ ^[yY]$ ]] && reboot || echo -e "${gl_huang}已取消重启，请稍后手动重启。${gl_bai}"
        else
            echo -e "${gl_lv}系统更新完成！${gl_bai}"
        fi
    else
        echo -e "${gl_hong}错误：未检测到 apt！${gl_bai}"
    fi
    read -p "按回车键返回..."
}

linux_clean() {
    echo -e "${gl_huang}正在进行系统清理...${gl_bai}"
    if command -v apt &>/dev/null; then
        apt autoremove --purge -y && apt clean -y && apt autoclean -y
    fi
    if command -v journalctl &>/dev/null; then
        journalctl --rotate && journalctl --vacuum-time=1s && journalctl --vacuum-size=50M
    fi
    find /tmp -type f -atime +10 -delete 2>/dev/null
    echo -e "${gl_lv}清理完成！${gl_bai}"
    read -p "按回车键返回..."
}
