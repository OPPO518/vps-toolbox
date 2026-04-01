#!/bin/bash

# ==========================================
#  内存管理模块 (ZRAM + Swapfile)
# ==========================================

swap_management() {
    while true; do
        clear
        echo -e "${gl_kjlan}################################################"
        echo -e "#     进阶内存管理 (ZRAM 压缩 + Swap 兜底)     #"
        echo -e "################################################${gl_bai}"
        
        # 状态采集
        local total_mem=$(free -m | awk '/^Mem:/{print $2}')
        local zram_status=$(lsmod | grep -q zram && echo -e "${gl_lv}已启用${gl_bai}" || echo -e "${gl_hong}未启用${gl_bai}")
        local swap_total=$(free -m | grep Swap | awk '{print $2}')
        
        echo -e " 物理内存: ${gl_kjlan}${total_mem} MB${gl_bai}"
        echo -e " ZRAM 状态: ${zram_status}"
        echo -e " 总交换量: ${gl_kjlan}${swap_total} MB${gl_bai}"
        echo -e "------------------------------------------------"
        echo -e "${gl_lv} 1.${gl_bai} 一键部署/更新 进阶内存优化 (推荐)"
        echo -e "${gl_hong} 2.${gl_bai} 彻底卸载 ZRAM 与 Swapfile"
        echo -e "------------------------------------------------"
        echo -e " 3. 实时查看交换详情 (zramctl/swapon)"
        echo -e " 4. 尝试执行 SSD Trim 优化"
        echo -e "------------------------------------------------"
        echo -e "${gl_hui} 0. 返回上级菜单${gl_bai}"
        echo -e "------------------------------------------------"
        
        read -p "请输入选项 [0-4]: " choice
        case "$choice" in
            1)
                echo -e "${gl_huang}>>> 正在部署进阶内存优化方案...${gl_bai}"
                
                # 安装组件并清理旧配置
                apt update && apt install -y zram-tools
                swapoff -a 2>/dev/null
                sed -i '/swapfile/d' /etc/fstab

                # 动态计算参数
                local z_percent=60
                local swappiness=60
                local cache_pressure=100
                
                if [ "$total_mem" -le 1024 ]; then
                    z_percent=100; swappiness=100; cache_pressure=50
                elif [ "$total_mem" -ge 8192 ]; then
                    z_percent=25; swappiness=10; cache_pressure=100
                fi

                # 配置 ZRAM
                cat > /etc/default/zramswap << EOF
ALGO=zstd
PERCENT=$z_percent
PRIORITY=100
EOF
                systemctl restart zramswap

                # 配置 Swapfile (统一 2GB 兜底)
                local swap_size=2048
                if [ ! -f /swapfile ]; then
                    echo -e "${gl_huang}创建 2GB 物理交换文件...${gl_bai}"
                    dd if=/dev/zero of=/swapfile bs=1M count=$swap_size status=progress
                    chmod 600 /swapfile
                    mkswap /swapfile
                fi
                swapon --priority -2 /swapfile
                [ -z "$(grep '/swapfile' /etc/fstab)" ] && echo '/swapfile none swap sw,pri=-2 0 0' >> /etc/fstab

                # 系统内核调优
                cat > /etc/sysctl.d/90-memory-tune.conf << EOF
vm.swappiness=$swappiness
vm.vfs_cache_pressure=$cache_pressure
EOF
                sysctl -p /etc/sysctl.d/90-memory-tune.conf >/dev/null

                # 开启 SSD Trim
                systemctl enable --now fstrim.timer >/dev/null 2>&1
                
                echo -e "${gl_lv}部署完成！ZRAM ($z_percent%) + Swapfile (2GB) 已生效。${gl_bai}"
                read -p "按回车继续..."
                ;;
            2)
                echo -e "${gl_huang}正在回滚配置...${gl_bai}"
                swapoff -a 2>/dev/null
                systemctl stop zramswap 2>/dev/null
                apt purge -y zram-tools
                rm -f /swapfile /etc/sysctl.d/90-memory-tune.conf
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
