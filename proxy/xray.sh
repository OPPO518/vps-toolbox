#!/bin/bash

xray_management() {
    BIN_PATH="/usr/local/bin/xray"
    CONF_DIR="/usr/local/etc/xray"
    INFO_FILE="${CONF_DIR}/info.txt"

    install_xray() {
        echo -e "${gl_huang}正在调用官方脚本安装 (User=root)...${gl_bai}"
        bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root
        if [ $? -eq 0 ]; then
            echo -e "${gl_lv}安装/升级成功！${gl_bai}"
            $BIN_PATH version | head -n 1
            echo -e "------------------------------------------------"
            echo -e "请继续执行 [2. 初始化配置] 以启用服务。"
        else
            echo -e "${gl_hong}安装失败！${gl_bai}"
        fi
        read -p "按回车继续..."
    }

    configure_reality() {
        if [ ! -f "$BIN_PATH" ]; then echo -e "${gl_hong}请先安装 Xray!${gl_bai}"; sleep 1; return; fi
        
        local port=$(shuf -i 20000-65000 -n 1)
        ensure_port_open "$port"
        echo -e "${gl_huang}正在生成配置...${gl_bai}"
        
        local uuid=$($BIN_PATH uuid)
        local kp=$($BIN_PATH x25519)
        local pri=$(echo "$kp" | grep -i "Private" | cut -d: -f2 | tr -d '[:space:]')
        local pub=$(echo "$kp" | grep -i "Public" | cut -d: -f2 | tr -d '[:space:]')
        [ -z "$pub" ] && pub=$(echo "$kp" | grep -i "Password" | cut -d: -f2 | tr -d '[:space:]')
        local sid=$(openssl rand -hex 8)

        if [ -z "$pub" ]; then echo -e "${gl_hong}密钥生成失败: $kp${gl_bai}"; read -p "..."; return; fi
        
        mkdir -p $CONF_DIR
        cat > ${CONF_DIR}/config.json << EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "port": $port, "protocol": "vless",
      "settings": { "clients": [ { "id": "$uuid", "flow": "xtls-rprx-vision" } ], "decryption": "none" },
      "streamSettings": {
        "network": "tcp", "security": "reality",
        "realitySettings": {
          "dest": "www.microsoft.com:443", "serverNames": [ "www.microsoft.com", "microsoft.com" ],
          "privateKey": "$pri", "shortIds": [ "$sid" ]
        }
      },
      "sniffing": { "enabled": true, "destOverride": [ "http", "tls", "quic" ] }
    }
  ],
  "outbounds": [ { "protocol": "freedom", "tag": "direct" }, { "protocol": "blackhole", "tag": "block" } ],
  "routing": { "domainStrategy": "IPIfNonMatch", "rules": [ { "type": "field", "ip": [ "geoip:private" ], "outboundTag": "block" } ] }
}
EOF
        echo -e "${gl_huang}保存配置收据...${gl_bai}"
        local ip=$(curl -s --max-time 3 https://ipinfo.io/ip)
        local code=$(curl -s --max-time 3 https://ipinfo.io/country | tr -d '\n')
        local flag=$(get_flag_local "$code")
        local link="vless://$uuid@$ip:$port?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&fp=chrome&pbk=$pub&sid=$sid&type=tcp&headerType=none#${flag}Xray-Reality"

        echo -e "------------------------------------------------
${gl_kjlan}>>> 客户端连接信息 (Xray-core) <<<${gl_bai}
地区 (Region):  ${gl_bai}$flag $code${gl_bai}
地址 (Address): ${gl_bai}$ip${gl_bai}
端口 (Port):    ${gl_bai}$port${gl_bai}
用户ID (UUID):  ${gl_bai}$uuid${gl_bai}
公钥 (Public):  ${gl_bai}$pub${gl_bai}
Short ID:       ${gl_bai}$sid${gl_bai}
------------------------------------------------
${gl_kjlan}快速导入链接:${gl_bai}
${gl_lv}$link${gl_bai}
------------------------------------------------" > $INFO_FILE
        
        systemctl restart xray
        view_config
    }

    view_config() {
        if [ -f "$INFO_FILE" ]; then
            clear; cat $INFO_FILE
        else
            echo -e "${gl_hong}未找到配置信息，请先初始化！${gl_bai}"
        fi
        if [ "${FUNCNAME[1]}" != "configure_reality" ]; then 
            read -p "按回车返回..."
        fi
    }

    uninstall_xray() {
        echo -e "${gl_hong}警告: 这将删除 Xray 程序、配置及日志！${gl_bai}"
        read -p "确认卸载? (y/n): " confirm
        if [[ "$confirm" == "y" ]]; then
            bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove --purge
            rm -rf $CONF_DIR
            echo -e "${gl_lv}Xray 已彻底卸载。${gl_bai}"
        fi
        read -p "按回车继续..."
    }

    while true; do
        clear
        echo -e "${gl_kjlan}################################################"
        echo -e "#         Xray 核心管理 (Official Standard)    #"
        echo -e "################################################${gl_bai}"
        if systemctl is-active --quiet xray; then
            local ver=$($BIN_PATH version 2>/dev/null | head -n 1 | awk '{print $2}')
            echo -e "状态: ${gl_lv}● 运行中${gl_bai} (Ver: ${ver:-未知})"
        else
            echo -e "状态: ${gl_hong}● 已停止 / 未安装${gl_bai}"
        fi
        
        echo -e "------------------------------------------------"
        echo -e "${gl_lv} 1.${gl_bai} 安装/更新 (Install Latest)"
        echo -e "${gl_lv} 2.${gl_bai} 初始化配置 (Reset Config)"
        echo -e "${gl_huang} 3.${gl_bai} 查看当前配置 (View Info)"
        echo -e "------------------------------------------------"
        echo -e " 4. 查看日志 (Snapshot)"
        echo -e " 5. 重启服务 (Restart)"
        echo -e " 6. 停止服务 (Stop)"
        echo -e "------------------------------------------------"
        echo -e "${gl_hong} 9.${gl_bai} 彻底卸载 (Uninstall)"
        echo -e "${gl_hui} 0.${gl_bai} 返回上级菜单"
        echo -e "------------------------------------------------"
        read -p "请输入选项: " c
        case "$c" in
            1) install_xray ;;
            2) configure_reality ;;
            3) view_config ;;
            4) 
                echo -e "${gl_huang}正在实时监控 Xray 日志...${gl_bai}"
                trap 'kill $log_pid 2>/dev/null; echo -e "\n${gl_lv}已停止监控。${gl_bai}"; return' SIGINT
                journalctl -u xray -n 50 -f &
                local log_pid=$!
                read -r -p ">>> 请按【回车键】或【Ctrl+C】停止查看 <<<"
                kill $log_pid >/dev/null 2>&1
                trap - SIGINT
                ;;
            5) systemctl restart xray; echo -e "${gl_lv}服务已重启${gl_bai}"; sleep 1 ;;
            6) systemctl stop xray; echo -e "${gl_hong}服务已停止${gl_bai}"; sleep 1 ;;
            9) uninstall_xray ;;
            0) return ;;
            *) echo "无效选项" ;;
        esac
    done
}
