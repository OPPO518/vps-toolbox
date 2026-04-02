#!/bin/bash

# ==========================================
#  独立中转模块 (Nftables my_transit 专用表)
# ==========================================

# 转发规则保存路径
TRANSIT_LIST="/etc/nft_transit_rules.list"

transit_management() {
    # 开启内核转发开关 (底层支撑)
    sysctl -w net.ipv4.ip_forward=1 >/dev/null

    while true; do
        clear
        echo -e "${gl_kjlan}################################################"
        echo -e "#         独立中转物流中心 (Independent Hub)   #"
        echo -e "################################################${gl_bai}"
        
        # 自动检测 my_transit 表是否存在
        if nft list tables | grep -q "my_transit"; then
            echo -e " 当前模式: ${gl_lv}中转逻辑已激活 (独立表模式)${gl_bai}"
            echo -e "------------------------------------------------"
            echo -e " 1. 查看当前转发规则 (Forwarding List)"
            echo -e " 2. 添加 [基础] 端口转发 (1对1)"
            echo -e " 3. 添加 [高级] 负载均衡转发 (1对多)"
            echo -e " 4. 添加 [智能] SNI 分流转发 (基于域名)"
            echo -e " 5. 删除转发规则"
            echo -e "------------------------------------------------"
            echo -e "${gl_hong} 8. 彻底停用中转模块 (卸载 my_transit 表)${gl_bai}"
        else
            echo -e " 当前状态: ${gl_hong}未初始化${gl_bai}"
            echo -e "------------------------------------------------"
            echo -e "${gl_lv} 1. 一键初始化中转引擎 (创建独立表与 NAT 链)${gl_bai}"
        fi
        
        echo -e " 0. 返回主菜单"
        echo -e "------------------------------------------------"
        
        read -p "请输入选项: " tr_choice
        # ... 逻辑分支 ...
    done
}
