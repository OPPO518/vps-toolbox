#!/bin/bash

linux_info() {
    tput civis # 隐藏光标
    trap 'tput cnorm; echo -e "\n${gl_lv}已安全退出。${gl_bai}"; return' SIGINT

    # 记录初始流量用于计算实时速率
    local old_rx=$(cat /proc/net/dev | grep -E 'eth0|ens|eno' | awk '{print $2}')
    local old_tx=$(cat /proc/net/dev | grep -E 'eth0|ens|eno' | awk '{print $10}')
    local last_time=$(date +%s)

    while true; do
        # --- 1. 数据实时采集 ---
        # 实时速率计算
        local now_time=$(date +%s)
        local time_diff=$((now_time - last_time))
        [ $time_diff -eq 0 ] && time_diff=1
        
        local new_rx=$(cat /proc/net/dev | grep -E 'eth0|ens|eno' | awk '{print $2}')
        local new_tx=$(cat /proc/net/dev | grep -E 'eth0|ens|eno' | awk '{print $10}')
        
        local rx_rate=$(( (new_rx - old_rx) / 1024 / time_diff )) # KB/s
        local tx_rate=$(( (new_tx - old_tx) / 1024 / time_diff )) # KB/s
        
        old_rx=$new_rx; old_tx=$new_tx; last_time=$now_time

        # CPU/内存/磁盘数据 (逻辑同前)
        local cpu_perc=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}' | cut -d. -f1)
        local mem_total=$(free -m | awk '/^Mem:/{print $2}')
        local mem_used=$(free -m | awk '/^Mem:/{print $3}')
        local mem_perc=$(( mem_used * 100 / mem_total ))
        local disk_perc=$(df / | awk 'NR==2 {print $5}' | tr -d '%')

        # --- 2. 界面模拟 Web UI 卡片布局 ---
        echo -ne "\033[H\033[2J"
        echo -e "${gl_hui}══════════════════════════════════════════════════════════════════${gl_bai}"
        echo -e "  ${gl_kjlan}S Y S T E M   M O N I T O R${gl_bai}  (Press ${gl_hong}Ctrl+C${gl_bai} to Exit)"
        echo -e "${gl_hui}══════════════════════════════════════════════════════════════════${gl_bai}"

        # 第一行：CPU 与 内存 (卡片 1 & 2)
        printf "  %-32s %-32s\n" "${gl_lv}● CPU 信息${gl_bai}" "${gl_kjlan}● 内存使用${gl_bai}"
        printf "  %-32s %-32s\n" "核心: $(nproc)C | 使用率: ${cpu_perc}%" "总计: ${mem_total}MB | 已用: ${mem_used}MB"
        printf "  " && draw_bar $cpu_perc 20 && printf "   " && draw_bar $mem_perc 20 && echo ""
        echo -e "${gl_hui}  ────────────────────────────────  ────────────────────────────────${gl_bai}"

        # 第二行：流量监控 (卡片 3 - 仿折线图数据)
        echo -e "  ${gl_huang}● 网络流量实时监控 (Real-time)${gl_bai}"
        printf "  上传速度: ${gl_lv}%-10s${gl_bai} | 下载速度: ${gl_lv}%-10s${gl_bai}\n" "${tx_rate} KB/s" "${rx_rate} KB/s"
        printf "  累计发送: ${gl_hui}%-10s${gl_bai} | 累计接收: ${gl_hui}%-10s${gl_bai}\n" "$tx" "$rx"
        echo -e "${gl_hui}  ──────────────────────────────────────────────────────────────────${gl_bai}"

        # 第三行：系统状态与磁盘 (卡片 4 & 5)
        printf "  %-32s %-32s\n" "${gl_lan}● 磁盘监控${gl_bai}" "${gl_bai}● 节点运行${gl_bai}"
        printf "  使用率: ${disk_perc}%%" "  时长: $(uptime -p | sed 's/up //')" && echo ""
        printf "  " && draw_bar $disk_perc 20 && printf "   " && echo -e "  Load: $(uptime | awk -F'load average:' '{print $2}' | sed 's/ //')"
        echo -e "${gl_hui}══════════════════════════════════════════════════════════════════${gl_bai}"
        
        echo -ne "  ${gl_hui}Updated: $(date "+%H:%M:%S")${gl_bai}"
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
