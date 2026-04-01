#!/bin/bash

system_initialize() {
    clear
    echo -e "${gl_kjlan}################################################"
    echo -e "#            系统初始化配置 (System Init)      #"
    echo -e "################################################${gl_bai}"
    
    local os_ver=""
    if grep -q "bullseye" /etc/os-release; then 
        os_ver="11"
        echo -e "当前系统: ${gl_huang}Debian 11 (Bullseye)${gl_bai}"
    elif grep -q "bookworm" /etc/os-release; then 
        os_ver="12"
        echo -e "当前系统: ${gl_huang}Debian 12 (Bookworm)${gl_bai}"
    else 
        echo -e "${gl_hong}错误: 本脚本仅支持 Debian 11 或 12 系统！${gl_bai}"
        read -p "按回车返回..."
        return
    fi
    
    echo -e "${gl_hui}* 包含换源、BBR、时区及落地/中转环境配置${gl_bai}"
    echo -e "------------------------------------------------"
    echo -e "请设定当前 VPS 的业务角色："
    echo -e "${gl_lv} 1.${gl_bai} 落地机 (Landing)  -> [关闭转发 | 极简安全]"
    echo -e "${gl_lv} 2.${gl_bai} 中转机 (Transit)  -> [开启转发 | 路由优化]"
    echo -e "${gl_hui} 0. 返回主菜单${gl_bai}"
    echo -e "------------------------------------------------"
    read -p "请输入选项 [0-2]: " role_choice
    
    case "$role_choice" in
        1|2) ;;
        0) return ;;
        *) echo -e "${gl_hong}无效选项，操作已取消！${gl_bai}"; sleep 1; return ;;
    esac

    echo -e "${gl_kjlan}>>> 正在执行初始化...${gl_bai}"
    
    [ -f /etc/apt/sources.list ] && mv /etc/apt/sources.list /etc/apt/sources.list.bak_$(date +%F)
    
    if [ "$os_ver" == "11" ]; then
        echo -e "deb http://deb.debian.org/debian bullseye main contrib non-free\ndeb http://deb.debian.org/debian bullseye-updates main contrib non-free\ndeb http://security.debian.org/debian-security bullseye-security main contrib non-free\ndeb http://archive.debian.org/debian bullseye-backports main contrib non-free" > /etc/apt/sources.list
    else
        echo -e "deb http://deb.debian.org/debian/ bookworm main contrib non-free non-free-firmware\ndeb http://deb.debian.org/debian-security/ bookworm-security main contrib non-free non-free-firmware\ndeb http://deb.debian.org/debian/ bookworm-updates main contrib non-free non-free-firmware\ndeb http://deb.debian.org/debian/ bookworm-backports main contrib non-free non-free-firmware" > /etc/apt/sources.list
    fi

    export DEBIAN_FRONTEND=noninteractive
    apt update && apt upgrade -y -o Dpkg::Options::="--force-confold"
    apt install curl wget systemd-timesyncd socat cron rsync unzip -y

    rm -f /etc/sysctl.d/99-vps-optimize.conf
    cat > /etc/sysctl.d/99-vps-optimize.conf << EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.icmp_echo_ignore_all=0
net.netfilter.nf_conntrack_max=1000000
net.nf_conntrack_max=1000000
EOF
    
    if [ "$role_choice" == "1" ]; then
        echo "net.ipv4.ip_forward=0" >> /etc/sysctl.d/99-vps-optimize.conf
        echo "net.ipv6.conf.all.forwarding=0" >> /etc/sysctl.d/99-vps-optimize.conf
    else
        modprobe nft_nat 2>/dev/null; modprobe br_netfilter 2>/dev/null
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.d/99-vps-optimize.conf
        echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.d/99-vps-optimize.conf
        echo "net.ipv4.conf.all.rp_filter=0" >> /etc/sysctl.d/99-vps-optimize.conf
    fi
    sysctl --system
    
    timedatectl set-timezone Asia/Shanghai
    systemctl enable --now systemd-timesyncd
    
    echo -e ""
    echo -e "${gl_lv}====== 初始化配置报告 (Init Report) ======${gl_bai}"
    local bbr_status=$(sysctl -n net.ipv4.tcp_congestion_control)
    echo -e " 1. BBR 算法: \t${gl_kjlan}${bbr_status}${gl_bai}"
    local fw_status=$(sysctl -n net.ipv4.ip_forward)
    if [ "$fw_status" == "1" ]; then
        echo -e " 2. 内核转发: \t${gl_huang}已开启 (中转模式)${gl_bai}"
    else
        echo -e " 2. 内核转发: \t${gl_lv}已关闭 (落地模式)${gl_bai}"
    fi
    local current_time=$(date "+%Y-%m-%d %H:%M:%S")
    echo -e " 3. 当前时间: \t${gl_bai}${current_time} (CST)${gl_bai}"
    echo -e "------------------------------------------------"
    
    if [ -f /var/run/reboot-required ]; then
        echo -e "${gl_hong}!!! 检测到内核更新，必须重启 !!!${gl_bai}"
        read -p "是否立即重启? (y/n): " rb
        [[ "$rb" =~ ^[yY]$ ]] && reboot
    else
        read -p "按回车返回..."
    fi
}

swap_management() {
    while true; do
        clear
        echo -e "${gl_kjlan}################################################"
        echo -e "#            Swap 虚拟内存管理                     #"
        echo -e "################################################${gl_bai}"
        
        local swap_total=$(free -m | grep Swap | awk '{print $2}')
        local swap_used=$(free -m | grep Swap | awk '{print $3}')
        
        if [ "$swap_total" -eq 0 ]; then
             echo -e "当前状态: ${gl_hong}未启用 Swap${gl_bai}"
        else
             echo -e "当前状态: ${gl_lv}已启用${gl_bai} | 总计: ${gl_kjlan}${swap_total}MB${gl_bai} | 已用: ${gl_huang}${swap_used}MB${gl_bai}"
        fi
        
        echo -e "------------------------------------------------"
        echo -e "${gl_lv} 1.${gl_bai} 设置/扩容 Swap (建议内存的 1-2 倍)"
        echo -e "${gl_hong} 2.${gl_bai} 卸载/关闭 Swap"
        echo -e "${gl_hui} 0. 返回上级菜单${gl_bai}"
        echo -e "------------------------------------------------"
        
        read -p "请输入选项 [0-2]: " choice
        case "$choice" in
            1)
                echo -e "------------------------------------------------"
                read -p "请输入需要添加的 Swap 大小 (单位: MB，例如 1024): " swap_size
                if [[ ! "$swap_size" =~ ^[0-9]+$ ]]; then
                    echo -e "${gl_hong}错误: 请输入纯数字！${gl_bai}"; sleep 1; continue
                fi
                echo -e "${gl_huang}正在处理 (清理旧文件 -> 创建新文件)...${gl_bai}"
                swapoff -a 2>/dev/null
                rm -f /swapfile 2>/dev/null
                sed -i '/swapfile/d' /etc/fstab

                if dd if=/dev/zero of=/swapfile bs=1M count=$swap_size status=progress; then
                    chmod 600 /swapfile
                    mkswap /swapfile
                    swapon /swapfile
                    echo '/swapfile none swap sw 0 0' >> /etc/fstab
                    echo -e "${gl_lv}成功！Swap 已设定为 ${swap_size}MB。${gl_bai}"
                else
                    echo -e "${gl_hong}创建失败，请检查磁盘空间。${gl_bai}"
                fi
                read -p "按回车键继续..."
                ;;
            2)
                echo -e "${gl_huang}正在卸载 Swap...${gl_bai}"
                swapoff -a
                rm -f /swapfile
                sed -i '/swapfile/d' /etc/fstab
                echo -e "${gl_lv}Swap 已移除。${gl_bai}"
                read -p "按回车键继续..."
                ;;
            0) return ;;
            *) echo -e "${gl_hong}无效选项${gl_bai}"; sleep 1 ;;
        esac
    done
}

linux_info() {
    clear
    echo -e "${gl_huang}正在采集系统信息...${gl_bai}"
    ip_address

    local cpu_info=$(lscpu | awk -F': +' '/Model name:/ {print $2; exit}')
    local cpu_usage_percent=$(awk '{u=$2+$4; t=$2+$4+$5; if (NR==1){u1=u; t1=t;} else printf "%.0f\n", (($2+$4-u1) * 100 / (t-t1))}' \
        <(grep 'cpu ' /proc/stat) <(sleep 1; grep 'cpu ' /proc/stat))
    local cpu_cores=$(nproc)
    local cpu_freq=$(cat /proc/cpuinfo | grep "MHz" | head -n 1 | awk '{printf "%.1f GHz\n", $4/1000}')
    local mem_info=$(free -b | awk 'NR==2{printf "%.2f/%.2fM (%.2f%%)", $3/1024/1024, $2/1024/1024, $3*100/$2}')
    local disk_info=$(df -h | awk '$NF=="/"{printf "%s/%s (%s)", $3, $2, $5}')
    
    local ipinfo=$(curl -s ipinfo.io)
    local country=$(echo "$ipinfo" | grep 'country' | awk -F': ' '{print $2}' | tr -d '",')
    local city=$(echo "$ipinfo" | grep 'city' | awk -F': ' '{print $2}' | tr -d '",')
    local isp_info=$(echo "$ipinfo" | grep 'org' | awk -F': ' '{print $2}' | tr -d '",')
    
    local load=$(uptime | awk '{print $(NF-2), $(NF-1), $NF}')
    local dns_addresses=$(awk '/^nameserver/{printf "%s ", $2} END {print ""}' /etc/resolv.conf)
    local cpu_arch=$(uname -m)
    local hostname=$(uname -n)
    local kernel_version=$(uname -r)
    local congestion_algorithm=$(sysctl -n net.ipv4.tcp_congestion_control)
    local queue_algorithm=$(sysctl -n net.core.default_qdisc)
    local os_info=$(grep PRETTY_NAME /etc/os-release | cut -d '=' -f2 | tr -d '"')
    
    output_status
    
    local current_time=$(date "+%Y-%m-%d %I:%M %p")
    local swap_info=$(free -m | awk 'NR==3{used=$3; total=$2; if (total == 0) {percentage=0} else {percentage=used*100/total}; printf "%dM/%dM (%d%%)", used, total, percentage}')
    local runtime=$(cat /proc/uptime | awk -F. '{run_days=int($1 / 86400);run_hours=int(($1 % 86400) / 3600);run_minutes=int(($1 % 3600) / 60); if (run_days > 0) printf("%d天 ", run_days); if (run_hours > 0) printf("%d时 ", run_hours); printf("%d分\n", run_minutes)}')
    local timezone=$(current_timezone)
    local tcp_count=$(ss -t | wc -l)
    local udp_count=$(ss -u | wc -l)

    echo ""
    echo -e "${gl_lv}系统信息概览${gl_bai}"
    echo -e "${gl_kjlan}-------------"
    echo -e "${gl_kjlan}主机名:         ${gl_bai}$hostname ($country_code $flag)"
    echo -e "${gl_kjlan}系统版本:       ${gl_bai}$os_info"
    echo -e "${gl_kjlan}Linux版本:      ${gl_bai}$kernel_version"
    echo -e "${gl_kjlan}-------------"
    echo -e "${gl_kjlan}CPU架构:        ${gl_bai}$cpu_arch"
    echo -e "${gl_kjlan}CPU型号:        ${gl_bai}$cpu_info"
    echo -e "${gl_kjlan}CPU核心数:      ${gl_bai}$cpu_cores"
    echo -e "${gl_kjlan}CPU频率:        ${gl_bai}$cpu_freq"
    echo -e "${gl_kjlan}-------------"
    echo -e "${gl_kjlan}CPU占用:        ${gl_bai}$cpu_usage_percent%"
    echo -e "${gl_kjlan}系统负载:       ${gl_bai}$load"
    echo -e "${gl_kjlan}TCP|UDP连接数:  ${gl_bai}$tcp_count|$udp_count"
    echo -e "${gl_kjlan}物理内存:       ${gl_bai}$mem_info"
    echo -e "${gl_kjlan}虚拟内存:       ${gl_bai}$swap_info"
    echo -e "${gl_kjlan}硬盘占用:       ${gl_bai}$disk_info"
    echo -e "${gl_kjlan}-------------"
    echo -e "${gl_kjlan}总接收:         ${gl_bai}$rx"
    echo -e "${gl_kjlan}总发送:         ${gl_bai}$tx"
    echo -e "${gl_kjlan}-------------"
    echo -e "${gl_kjlan}网络算法:       ${gl_bai}$congestion_algorithm $queue_algorithm"
    echo -e "${gl_kjlan}-------------"
    echo -e "${gl_kjlan}运营商:         ${gl_bai}$isp_info"
    if [ -n "$ipv4_address" ]; then echo -e "${gl_kjlan}IPv4地址:       ${gl_bai}$ipv4_address"; fi
    if [ -n "$ipv6_address" ]; then echo -e "${gl_kjlan}IPv6地址:       ${gl_bai}$ipv6_address"; fi
    echo -e "${gl_kjlan}DNS地址:        ${gl_bai}$dns_addresses"
    echo -e "${gl_kjlan}地理位置:       ${gl_bai}$country $city"
    echo -e "${gl_kjlan}系统时间:       ${gl_bai}$timezone $current_time"
    echo -e "${gl_kjlan}-------------"
    echo -e "${gl_kjlan}运行时长:       ${gl_bai}$runtime"
    echo
    read -r -p "按回车键返回..."
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
