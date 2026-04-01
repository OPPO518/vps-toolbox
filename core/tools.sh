#!/bin/bash

linux_info() {
    # 隐藏光标，增加沉浸感
    tput civis
    
    # 捕获 Ctrl+C，恢复光标并退出
    trap 'tput cnorm; echo -e "\n${gl_lv}已安全退出监控模式。${gl_bai}"; sleep 1; return' SIGINT

    while true; do
        # --- 1. 数据实时采集 ---
        ip_address >/dev/null 2>&1
        output_status >/dev/null 2>&1
        
        # 负载与 CPU
        local cpu_perc=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}' | cut -d. -f1)
        local load=$(uptime | awk -F'load average:' '{print $2}' | sed 's/ //')
        
        # 内存与 Swap
        local mem_total=$(free -m | awk '/^Mem:/{print $2}')
        local mem_used=$(free -m | awk '/^Mem:/{print $3}')
        local mem_perc=$(( mem_used * 100 / mem_total ))
        
        local swap_total=$(free -m | awk '/^Swap:/{print $2}')
        local swap_used=$(free -m | awk '/^Swap:/{print $3}')
        local swap_perc=0; [ "$swap_total" -gt 0 ] && swap_perc=$(( swap_used * 100 / swap_total ))
        
        # 磁盘
        local disk_info_raw=$(df -h / | awk 'NR==2 {print $3,$2,$5}')
        local disk_used_text=$(echo $disk_info_raw | awk '{print $1}')
        local disk_total_text=$(echo $disk_info_raw | awk '{print $2}')
        local disk_perc=$(echo $disk_info_raw | awk '{print $3}' | tr -d '%')

        # 连接与时长
        local tcp_count=$(ss -t | wc -l)
        local udp_count=$(ss -u | wc -l)
        local runtime=$(uptime -p | sed 's/up //')

        # --- 2. 仪表盘渲染 ---
        echo -ne "\033[H\033[2J" # 彻底清屏并复位
        echo -e "${gl_bai}┌──────────────────────────────────────────────────────────┐"
        echo -e "│  ${gl_kjlan}VPS 实时运维仪表盘${gl_bai} (按 ${gl_hong}Ctrl+C${gl_bai} 退出)             │"
        echo -e "└──────────────────────────────────────────────────────────┘"

        # 资源监控区
        echo -e "${gl_lv}[ 资源负载监控 ]${gl_bai}"
        printf "  CPU 占用:  " && draw_bar $cpu_perc 30 && echo -e " ${gl_hui}Load: $load${gl_bai}"
        printf "  物理内存:  " && draw_bar $mem_perc 30 && echo -e " ${gl_hui}$mem_used/$mem_total MB${gl_bai}"
        printf "  虚拟内存:  " && draw_bar $swap_perc 30 && echo -e " ${gl_hui}$swap_used/$swap_total MB${gl_bai}"
        printf "  磁盘空间:  " && draw_bar $disk_perc 30 && echo -e " ${gl_hui}$disk_used_text/$disk_total_text${gl_bai}"
        echo -e "${gl_hui}------------------------------------------------------------${gl_bai}"

        # 网络与流量区
        echo -e "${gl_kjlan}[ 网络传输统计 ]${gl_bai}"
        echo -e "  下载总计 (RX): ${gl_lv}%-15s${gl_bai} 上传总计 (TX): ${gl_lv}%-15s${gl_bai}" "$rx" "$tx"
        echo -e "  TCP 连接数  : ${gl_lan}%-15s${gl_bai} UDP 连接数  : ${gl_lan}%-15s${gl_bai}" "$tcp_count" "$udp_count"
        echo -e "  网卡算法    : ${gl_bai}%-15s${gl_bai} 调度器      : ${gl_bai}%-15s${gl_bai}" "$(sysctl -n net.ipv4.tcp_congestion_control)" "$(sysctl -n net.core.default_qdisc)"
        echo -e "${gl_hui}------------------------------------------------------------${gl_bai}"

        # 身份与地理区
        echo -e "${gl_huang}[ 节点身份信息 ]${gl_bai}"
        echo -e "  主机/系统: $(hostname) | $(grep PRETTY_NAME /etc/os-release | cut -d '=' -f2 | tr -d '"')"
        echo -e "  IPv4/v6  : ${gl_lan}${ipv4_address:-N/A}${gl_bai} / ${gl_lan}${ipv6_address:-N/A}${gl_bai}"
        echo -e "  运营商   : $isp_info"
        echo -e "  地理位置 : $flag $country $city"
        echo -e "  运行时长 : $runtime"
        
        echo -e "${gl_hui}------------------------------------------------------------${gl_bai}"
        echo -ne "  ${gl_hui}最后刷新时间: $(date "+%Y-%m-%d %H:%M:%S")${gl_bai}"

        sleep 1
    done
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
