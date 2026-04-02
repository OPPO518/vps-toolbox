#!/bin/bash

# ==========================================
#  系统辅助工具模块 (信息/更新/清理)
# ==========================================

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

# ==========================================
#  系统维护模块: 智能更新与深度清理
# ==========================================

# [底层防线] 检查是否有其他包管理器在运行，防止 dpkg 锁死报错
check_apt_lock() {
    if ps -C apt,apt-get,dpkg >/dev/null 2>&1; then
        echo -e "${gl_hong}错误: 系统当前正有其他更新任务运行中 (apt/dpkg 锁定)！${gl_bai}"
        echo -e "${gl_huang}请等待后台自动任务（如 unattended-upgrades）完成，或稍后再试。${gl_bai}"
        return 1
    fi
    return 0
}

# === [ 模块 1: 智能系统更新 ] ===
linux_update() {
    check_apt_lock || { read -p "按回车键返回..."; return; }
    
    clear
    echo -e "${gl_kjlan}################################################"
    echo -e "#           系统智能更新与安全管理             #"
    echo -e "################################################${gl_bai}"
    echo -e "${gl_huang}>>> 正在后台拉取最新软件源状态，请稍候...${gl_bai}"
    
    # 静默拉取更新列表，获取准确的待更新包数量
    apt-get update -qq
    local pending_updates=$(apt list --upgradable 2>/dev/null | grep -v "Listing" | grep -v "^$" | wc -l)
    
    if [ "$pending_updates" -eq 0 ]; then
        echo -e "当前状态: ${gl_lv}系统已是最新，无待处理更新。${gl_bai}"
    else
        echo -e "当前状态: ${gl_huang}发现 $pending_updates 个可用更新包。${gl_bai}"
    fi

    echo -e "------------------------------------------------"
    echo -e "${gl_lv} 1.${gl_bai} 执行完整系统升级 (Full Upgrade)"
    echo -e "${gl_lv} 2.${gl_bai} 仅下载更新包备用 (静默缓存，不立即安装)"
    echo -e "${gl_hui} 0.${gl_bai} 返回上级菜单"
    echo -e "------------------------------------------------"
    read -p "请输入选项: " up_choice

    case "$up_choice" in
        1)
            echo -e "${gl_kjlan}>>> 正在执行深度升级...${gl_bai}"
            export DEBIAN_FRONTEND=noninteractive
            # 强制保留旧配置文件，防止覆写用户的个性化设置
            apt-get full-upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
            
            # --- 深度感知：检查是否需要重启 ---
            local need_reboot=0
            if [ -f /var/run/reboot-required ]; then
                echo -e "${gl_hong}注意：检测到核心组件更新，已触发重启标记！${gl_bai}"
                need_reboot=1
            fi
            
            # 交叉比对内核：当前运行内核 vs 最新已安装内核
            local current_kernel=$(uname -r)
            local installed_kernel=$(dpkg --list | grep -E '^ii  linux-image-[0-9]+' | awk '{print $2}' | sed 's/linux-image-//g' | sort -V | tail -n 1)
            if [[ "$current_kernel" != "$installed_kernel"* ]] && [ -n "$installed_kernel" ]; then
                echo -e "${gl_huang}提示：新内核 ($installed_kernel) 已部署，当前仍在运行旧内核 ($current_kernel)。${gl_bai}"
                need_reboot=1
            fi

            if [ "$need_reboot" -eq 1 ]; then
                read -p "是否立即重启系统以应用底层更新？(y/n): " reboot_choice
                [[ "$reboot_choice" =~ ^[yY]$ ]] && reboot || echo -e "${gl_huang}已挂起重启操作，请记得稍后手动重启。${gl_bai}"
            else
                echo -e "${gl_lv}升级完成，当前系统运行完美！${gl_bai}"
                read -p "按回车键返回..."
            fi
            ;;
        2)
            echo -e "${gl_kjlan}>>> 正在后台静默下载更新包...${gl_bai}"
            apt-get full-upgrade -d -y >/dev/null 2>&1
            echo -e "${gl_lv}下载完成！缓存已保存在系统内，下次执行升级将实现秒级安装。${gl_bai}"
            read -p "按回车键返回..."
            ;;
        0) return ;;
        *) echo -e "${gl_hong}无效选项${gl_bai}"; sleep 1 ;;
    esac
}

# === [ 模块 2: 深度系统清理 ] ===
linux_clean() {
    check_apt_lock || { read -p "按回车键返回..."; return; }
    
    clear
    echo -e "${gl_kjlan}################################################"
    echo -e "#           系统空间深度扫描与治理             #"
    echo -e "################################################${gl_bai}"
    
    # 抓取磁盘与日志状态
    local root_usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    local root_avail=$(df -h / | awk 'NR==2 {print $4}')
    local journal_size=$(journalctl --disk-usage 2>/dev/null | awk '{print $6$7}')
    local apt_cache=$(du -sh /var/cache/apt/archives 2>/dev/null | awk '{print $1}')
    
    echo -e "系统盘使用率: \c"
    if [ "$root_usage" -gt 80 ]; then echo -e "${gl_hong}${root_usage}% (告警: 空间不足, 仅剩 ${root_avail})${gl_bai}"
    elif [ "$root_usage" -gt 50 ]; then echo -e "${gl_huang}${root_usage}% (良好: 剩余 ${root_avail})${gl_bai}"
    else echo -e "${gl_lv}${root_usage}% (健康: 剩余 ${root_avail})${gl_bai}"; fi
    
    echo -e "日志缓存占用: ${gl_huang}${journal_size:-未知}${gl_bai}"
    echo -e "APT 包缓存区: ${gl_huang}${apt_cache:-0B}${gl_bai}"
    echo -e "------------------------------------------------"
    echo -e "${gl_lv} 1.${gl_bai} 智能安全清理 (推荐: 清理缓存、废弃依赖、过期归档日志)"
    echo -e "${gl_hong} 2.${gl_bai} 极限深度清理 (危险: 强制清空所有活动日志与 Docker 碎屑)"
    echo -e "${gl_hui} 0.${gl_bai} 返回上级菜单"
    echo -e "------------------------------------------------"
    read -p "请输入选项: " cl_choice

    case "$cl_choice" in
        1)
            echo -e "${gl_kjlan}>>> 正在执行智能安全清理...${gl_bai}"
            export DEBIAN_FRONTEND=noninteractive
            
            echo "1. 卸载无用依赖与旧版内核..."
            apt-get autoremove --purge -y >/dev/null 2>&1
            apt-get clean -y
            
            echo "2. 清理 10 天以上的陈旧临时文件..."
            find /tmp -type f -atime +10 -delete 2>/dev/null
            
            echo "3. 移除系统产生的历史压缩日志..."
            find /var/log -type f -name "*.gz" -delete 2>/dev/null
            find /var/log -type f -name "*.[0-9]" -delete 2>/dev/null
            
            if command -v journalctl &>/dev/null; then
                echo "4. 瘦身守护进程日志 (保留近 3 天日志)..."
                journalctl --rotate >/dev/null 2>&1
                journalctl --vacuum-time=3d >/dev/null 2>&1
                journalctl --vacuum-size=50M >/dev/null 2>&1
            fi
            
            echo -e "${gl_lv}智能清理完成！系统负担已有效减轻。${gl_bai}"
            read -p "按回车键返回..."
            ;;
        2)
            echo -e "${gl_hong}警告: 这将清空所有正在记录的审计日志，通常仅在重置环境或磁盘彻底爆满时使用！${gl_bai}"
            read -p "确认执行极限清理吗？(y/n): " confirm_extreme
            if [[ "$confirm_extreme" =~ ^[yY]$ ]]; then
                export DEBIAN_FRONTEND=noninteractive
                
                # 基础深度清理
                apt-get autoremove --purge -y >/dev/null 2>&1
                apt-get clean -y
                find /tmp -type f -delete 2>/dev/null
                
                # [核心技巧] 清空普通活动日志 (保持句柄不失效，直接截断文件大小到 0)
                echo "正在截断并清空核心系统日志..."
                for log in /var/log/syslog /var/log/messages /var/log/auth.log /var/log/kern.log /var/log/daemon.log /var/log/dpkg.log; do
                    [ -f "$log" ] && truncate -s 0 "$log"
                done
                rm -f /var/log/*.gz /var/log/*.[0-9] 2>/dev/null
                
                # 极其暴力的 Journal 瘦身 (仅保留 1 秒日志)
                if command -v journalctl &>/dev/null; then
                    journalctl --rotate >/dev/null 2>&1
                    journalctl --vacuum-time=1s >/dev/null 2>&1
                fi
                
                # 针对 Docker 的额外扫描清理
                if command -v docker &>/dev/null; then
                    echo "正在清理 Docker 虚悬镜像与无用缓存层..."
                    docker image prune -a -f >/dev/null 2>&1
                    docker builder prune -f >/dev/null 2>&1
                fi
                
                echo -e "${gl_lv}极限清理执行完毕！已榨干每一兆可支配的磁盘空间。${gl_bai}"
            else
                echo -e "${gl_huang}已取消极限清理。${gl_bai}"
            fi
            read -p "按回车键返回..."
            ;;
        0) return ;;
        *) echo -e "${gl_hong}无效选项${gl_bai}"; sleep 1 ;;
    esac
}
