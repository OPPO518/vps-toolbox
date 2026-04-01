#!/bin/bash

# =========================================================
#  Debian VPS 极简运维工具箱 (Modular Git Edition)
# =========================================================

# 权限检查
if [ "$(id -u)" != "0" ]; then
    echo -e "\033[31m错误: 请使用 root 用户运行此脚本！\033[0m"
    exit 1
fi

# 获取当前脚本所在绝对路径 (无论在哪里执行都能精准定位)
BASE_DIR=$(dirname $(readlink -f "$0"))

# ===== 核心引擎：加载所有功能模块 =====
# 注意：utils.sh 必须最先加载，因为包含全局颜色和通用函数
source "${BASE_DIR}/core/utils.sh"
source "${BASE_DIR}/core/system.sh"
source "${BASE_DIR}/core/memory.sh"
source "${BASE_DIR}/core/tools.sh"
source "${BASE_DIR}/security/nftables.sh"
source "${BASE_DIR}/security/fail2ban.sh"
source "${BASE_DIR}/proxy/xray.sh"
source "${BASE_DIR}/proxy/singbox.sh"

# ===== 代理选择菜单 (整合入口) =====
proxy_menu() {
    while true; do
        clear
        echo -e "${gl_kjlan}################################################"
        echo -e "#            代理服务选择 (Proxy Selection)    #"
        echo -e "################################################${gl_bai}"
        echo -e "${gl_hui}请选择您要管理的核心内核：${gl_bai}"
        echo -e "------------------------------------------------"
        
        # 动态检测状态
        if systemctl is-active --quiet xray; then 
            echo -e "${gl_lv} 1.${gl_bai} Xray-core     ${gl_lv}[运行中]${gl_bai}"
        else 
            echo -e "${gl_lv} 1.${gl_bai} Xray-core     ${gl_hui}[未运行]${gl_bai}"
        fi
        
        if systemctl is-active --quiet sing-box; then 
            echo -e "${gl_kjlan} 2.${gl_bai} Sing-box      ${gl_lv}[运行中]${gl_bai}"
        else 
            echo -e "${gl_kjlan} 2.${gl_bai} Sing-box      ${gl_hui}[未运行]${gl_bai}"
        fi
        
        echo -e "------------------------------------------------"
        echo -e "${gl_hui} 0. 返回主菜单${gl_bai}"
        echo -e "------------------------------------------------"
        
        read -p "选项: " c
        case "$c" in
            1) xray_management ;;
            2) singbox_management ;;
            0) return ;;
            *) echo -e "${gl_hong}无效选项${gl_bai}"; sleep 1 ;;
        esac
    done
}

# ===== 极速更新机制 (利用 Git 从 GitHub 同步) =====
update_script() {
    echo -e "${gl_huang}正在从 GitHub 同步最新代码...${gl_bai}"
    
    cd "$BASE_DIR" || exit
    # 丢弃本地所有更改，强制与远程主分支同步
    git reset --hard origin/main >/dev/null 2>&1
    if git pull origin main; then
        echo -e "${gl_lv}更新成功！正在重启工具箱...${gl_bai}"
        sleep 1
        # 重新执行自身，加载最新的模块
        exec /usr/local/bin/x
    else
        echo -e "${gl_hong}更新失败，请检查网络或 GitHub 链接！${gl_bai}"
        sleep 2
    fi
}

# ===== 核心大门：主菜单 =====
main_menu() {
    while true; do
        clear
        echo -e "${gl_kjlan}################################################"
        echo -e "#                                              #"
        echo -e "#            Debian VPS 极简运维工具箱         #"
        echo -e "#                                              #"
        echo -e "################################################${gl_bai}"
        echo -e "${gl_huang}当前架构: 纯净模块化 (Git 同步版)${gl_bai}"
        echo -e "------------------------------------------------"
        echo -e "${gl_lv} 1.${gl_bai} 系统初始化 (Debian 基建与调优)   ${gl_hui}[system.sh]${gl_bai}"
        echo -e "${gl_lv} 2.${gl_bai} 进阶内存管理 (ZRAM + Swapfile)   ${gl_hui}[memory.sh]${gl_bai}"
        echo -e "------------------------------------------------"
        echo -e "${gl_kjlan} 3.${gl_bai} 防火墙/中转管理 (Nftables)       ${gl_hong}[核心]${gl_bai}"
        echo -e "${gl_kjlan} 4.${gl_bai} 防暴力破解管理 (Fail2ban)        ${gl_hong}[安全]${gl_bai}"
        echo -e "${gl_kjlan} 5.${gl_bai} 核心代理服务 (Xray/Sing-box)     ${gl_hong}[Proxy]${gl_bai}"
        echo -e "------------------------------------------------"
        echo -e "${gl_lv} 6.${gl_bai} 系统信息查询 (System Info)       ${gl_hui}[tools.sh]${gl_bai}"
        echo -e "${gl_lv} 7.${gl_bai} 系统更新 (Update Only)           ${gl_hui}[tools.sh]${gl_bai}"
        echo -e "${gl_lv} 8.${gl_bai} 系统清理 (Clean Junk)            ${gl_hui}[tools.sh]${gl_bai}"
        echo -e "------------------------------------------------"
        echo -e "${gl_kjlan} 9.${gl_bai} 从 GitHub 同步更新脚本           ${gl_huang}[秒级热更]${gl_bai}"
        echo -e "${gl_hong} 0.${gl_bai} 退出 (Exit)"
        echo -e "------------------------------------------------"
        
        read -p " 请输入选项 [0-9]: " choice

        case "$choice" in
            1) system_initialize ;;
            2) swap_management ;;
            3) nftables_management ;;
            4) fail2ban_management ;;
            5) proxy_menu ;;
            6) linux_info ;;
            7) linux_update ;;
            8) linux_clean ;;
            9) update_script ;;
            0) echo -e "${gl_lv}再见！祝节点纵享丝滑！${gl_bai}"; exit 0 ;;
            *) echo -e "${gl_hong}无效的选项！${gl_bai}"; sleep 1 ;;
        esac
    done
}

# 启动主菜单
main_menu
