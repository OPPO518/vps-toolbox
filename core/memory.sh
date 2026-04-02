# ==========================================
#  内存管理模块 (ZRAM + 智能 Swapfile)
# ==========================================

swap_management() {
    while true; do
        clear
        # --- [状态采集逻辑] ---
        local total_mem=$(free -m | awk '/^Mem:/{print $2}')
        local swap_total=$(free -m | grep Swap | awk '{print $2}')
        local zram_status=$(lsmod | grep -q zram && echo -e "${gl_lv}● 已启用${gl_bai}" || echo -e "${gl_hong}○ 未启用${gl_bai}")
        local trim_timer=$(systemctl is-active fstrim.timer 2>/dev/null | grep -q "active" && echo -e "${gl_lv}已开启(每周)${gl_bai}" || echo -e "${gl_huang}未开启${gl_bai}")
        local trim_check=$(lsblk -nd -o DISC-MAX 2>/dev/null | awk '$1 != "0B" {print $1}' | head -n 1)
        local trim_support=$( [ -n "$trim_check" ] && echo -e "${gl_lv}支持${gl_bai}" || echo -e "${gl_huang}未知/不支持${gl_bai}" )

        # --- 渲染新版 UI ---
        echo -e "${gl_kjlan}╭────────────────────────────────────────────────────────────────╮${gl_bai}"
        echo -e "${gl_kjlan}│${gl_bai}              ${gl_huang}VPS 进阶内存调度与 ZRAM 优化中心${gl_bai}                ${gl_kjlan}│${gl_bai}"
        echo -e "${gl_kjlan}╰────────────────────────────────────────────────────────────────╯${gl_bai}"
        echo -e " 内存调度状态: ${zram_status}"
        echo -e " 物理内存总量: ${gl_bai}${total_mem} MB${gl_bai}  |  当前交换总量: ${gl_bai}${swap_total} MB${gl_bai}"
        echo -e " 自动 Trim:    ${trim_timer}  |  硬件 Trim 支持: ${trim_support}"
        echo -e "${gl_kjlan}------------------------------------------------------------------${gl_bai}"
        
        echo -e " ${gl_huang}[ ⚡ 自动化优化策略 ]${gl_bai}"
        echo -e "   ${gl_lv}1.${gl_bai} 一键部署/更新 智能内存优化 (推荐)      ${gl_lv}[脚本执行]${gl_bai}"
        echo -e "   ${gl_hong}2.${gl_bai} 彻底卸载 ZRAM 与 Swapfile 逻辑"
        
        echo -e " ${gl_hui}┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈${gl_bai}"
        
        echo -e " ${gl_huang}[ 🔍 实时状态感知 ]${gl_bai}"
        echo -e "   ${gl_kjlan}3.${gl_bai} 深度查看交换详情 (zramctl/swapon)"
        echo -e "   ${gl_kjlan}4.${gl_bai} 尝试执行手动 SSD Trim 优化"
        
        echo -e " ${gl_hui}┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈${gl_bai}"
        
        echo -e "   ${gl_hui}0. 返回上级菜单 (Back)${gl_bai}"
        echo -e "${gl_kjlan}==================================================================${gl_bai}"
        
        read -p " 请输入选项 [0-4]: " choice
        
        case "$choice" in
            1)
                echo -e "${gl_huang}>>> 正在部署进阶内存优化方案...${gl_bai}"
                
                # --- 1. 清理旧环境 ---
                apt update && apt install -y zram-tools
                swapoff -a 2>/dev/null
                sed -i '/swapfile/d' /etc/fstab

                # --- 2. 动态计算 ZRAM 参数 ---
                local z_percent=60
                local swappiness=60
                local cache_pressure=100
                
                if [ "$total_mem" -le 1024 ]; then
                    z_percent=100; swappiness=100; cache_pressure=50
                elif [ "$total_mem" -ge 8192 ]; then
                    z_percent=25; swappiness=10; cache_pressure=100
                fi

                # --- 3. 配置 ZRAM (第一道防线 - 高优先级) ---
                cat > /etc/default/zramswap << EOF
ALGO=zstd
PERCENT=$z_percent
PRIORITY=100
EOF
                systemctl restart zramswap

                # --- 4. 磁盘 I/O 智能测速与 Swapfile 部署 ---
                echo -e "${gl_kjlan}>>> 正在进行磁盘 I/O 真实底线测速 (绕过系统缓存)...${gl_bai}"
                
                # 强行绕过内存缓存(Direct I/O)，测试真实物理写入速度 (100MB)
                local start_time=$(date +%s%N)
                dd if=/dev/zero of=/root/test_io_temp bs=1M count=100 oflag=direct >/dev/null 2>&1
                local end_time=$(date +%s%N)
                rm -f /root/test_io_temp
                
                # 计算耗时(毫秒)并求出 MB/s (100MB * 1000ms = 100000)
                local time_diff=$(( (end_time - start_time) / 1000000 ))
                [ "$time_diff" -eq 0 ] && time_diff=1
                local speed_mbps=$(( 100000 / time_diff ))
                
                echo -e "磁盘[物理直写]速度检测值: ${gl_kjlan}${speed_mbps} MB/s${gl_bai}"

                if [ "$speed_mbps" -lt 50 ]; then
                    # 石头盘防死机机制
                    echo -e "${gl_hong}警告: 检测到磁盘底层真实 I/O 极差 (石头盘)，已自动跳过 Swapfile 创建！仅保留 ZRAM。${gl_bai}"
                else
                    # 融合方案 B: 根据内存大小智能划拨 Swapfile
                    local swap_size=2048
                    if [ "$total_mem" -le 1024 ]; then
                        swap_size=$total_mem
                        echo -e "${gl_lv}磁盘 I/O 良好。小内存机器，智能分配等量 Swapfile: ${swap_size}MB${gl_bai}"
                    else
                        echo -e "${gl_lv}磁盘 I/O 良好。大内存机器，分配标准兜底 Swapfile: 2048MB${gl_bai}"
                    fi

                    if [ ! -f /swapfile ]; then
                        echo -e "${gl_huang}正在创建物理交换文件...${gl_bai}"
                        dd if=/dev/zero of=/swapfile bs=1M count=$swap_size status=progress
                        chmod 600 /swapfile
                        mkswap /swapfile
                    fi
                    swapon --priority -2 /swapfile
                    [ -z "$(grep '/swapfile' /etc/fstab)" ] && echo '/swapfile none swap sw,pri=-2 0 0' >> /etc/fstab
                fi

                # --- 5. 系统内核调优 ---
                cat > /etc/sysctl.d/90-memory-tune.conf << EOF
vm.swappiness=$swappiness
vm.vfs_cache_pressure=$cache_pressure
EOF
                sysctl -p /etc/sysctl.d/90-memory-tune.conf >/dev/null

                # --- 6. 开启 SSD Trim ---
                systemctl enable --now fstrim.timer >/dev/null 2>&1
                
                echo -e "\n${gl_lv}部署完成！当前可用虚拟内存策略已全局生效。${gl_bai}"
                read -p "按回车继续..."
                ;;
            2)
                echo -e "${gl_huang}正在回滚配置...${gl_bai}"
                swapoff -a 2>/dev/null
                systemctl stop zramswap 2>/dev/null
                apt purge -y zram-tools
                rm -f /swapfile /etc/sysctl.d/90-memory-tune.conf /root/test_io_temp
                sed -i '/swapfile/d' /etc/fstab
                echo -e "${gl_lv}卸载完成，内存配置已恢复原生状态。${gl_bai}"
                read -p "按回车继续..."
                ;;
            3)
                clear
                echo -e "${gl_huang}=== ZRAM 详情 ===${gl_bai}"
                zramctl 2>/dev/null || echo "ZRAM 未启用"
                echo -e "\n${gl_huang}=== 交换层优先级 (Priority 越大越优先) ===${gl_bai}"
                swapon --show
                read -p "按回车继续..."
                ;;
            4)
                echo -e "${gl_huang}正在手动尝试 Trim 优化...${gl_bai}"
                if fstrim -v /; then
                    echo -e "${gl_lv}Trim 执行成功。${gl_bai}"
                else
                    echo -e "${gl_hong}当前环境不支持 Trim。${gl_bai}"
                fi
                read -p "按回车继续..."
                ;;
            0) return ;;
            *) echo -e "${gl_hong}无效选项${gl_bai}"; sleep 1 ;;
        esac
    done
}
