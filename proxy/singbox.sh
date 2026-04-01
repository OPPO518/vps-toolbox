#!/bin/bash

singbox_management() {
    BIN_PATH="/usr/bin/sing-box"
    CONF_DIR="/etc/sing-box"
    INFO_FILE="${CONF_DIR}/info.txt"

    get_ver() {
        local tag=$(curl -sL --max-time 5 "https://api.github.com/repos/SagerNet/sing-box/releases/latest" | grep '"tag_name":' | head -n 1 | cut -d '"' -f 4)
        [ -z "$tag" ] && echo "v1.12.13" || echo "$tag"
    }

    install_sb() {
        echo -e "${gl_huang}检查架构...${gl_bai}"
        local arch=$(uname -m); local sb_arch=""
        case "$arch" in x86_64) sb_arch="amd64";; aarch64) sb_arch="arm64";; *) echo "不支持"; return;; esac

        local version=$(get_ver)
        echo -e "最新版本: ${gl_lv}${version}${gl_bai}"
        local ver_num=${version#v} 
        local url="https://github.com/SagerNet/sing-box/releases/download/${version}/sing-box_${ver_num}_linux_${sb_arch}.deb"

        echo -e "${gl_kjlan}下载 .deb...${gl_bai}"
        if curl -L -o /tmp/sb.deb "$url"; then
            echo -e "${gl_huang}安装/升级...${gl_bai}"
            if command -v sing-box &>/dev/null; then
                ar x /tmp/sb.deb data.tar.xz --output /tmp/
                tar -xf /tmp/data.tar.xz -C /tmp/ ./usr/bin/sing-box
                systemctl stop sing-box
                cp -f /tmp/usr/bin/sing-box /usr/bin/sing-box; chmod +x /usr/bin/sing-box
                systemctl restart sing-box
                rm -f /tmp/sb.deb /tmp/data.tar.xz /tmp/usr/bin/sing-box; rm -rf /tmp/usr
                echo -e "${gl_lv}升级完成${gl_bai}"
            else
                apt install /tmp/sb.deb -y; rm -f /tmp/sb.deb
                systemctl daemon-reload; systemctl enable sing-box; systemctl restart sing-box 2>/dev/null
                echo -e "${gl_lv}安装完成${gl_bai}"
            fi
            sing-box version | head -n 1
        else
            echo -e "${gl_hong}下载失败${gl_bai}"
        fi
        read -p "按回车继续..."
    }

    config_sb() {
        if ! command -v sing-box &>/dev/null; then echo -e "${gl_hong}请先安装!${gl_bai}"; sleep 1; return; fi

        local port=$(shuf -i 20000-65000 -n 1)
        ensure_port_open "$port"
        echo -e "${gl_huang}生成配置...${gl_bai}"
        
        local uuid=$(sing-box generate uuid)
        local kp=$(sing-box generate reality-keypair)
        local pri=$(echo "$kp" | grep "PrivateKey" | awk '{print $2}')
        local pub=$(echo "$kp" | grep "PublicKey" | awk '{print $2}')
        local sid=$(openssl rand -hex 8)
        
        cat > ${CONF_DIR}/config.json << EOF
{
  "log": { "level": "info", "timestamp": true },
  "inbounds": [
    {
      "type": "vless", "tag": "vless-in", "listen": "::", "listen_port": $port,
      "users": [ { "uuid": "$uuid", "flow": "xtls-rprx-vision" } ],
      "tls": {
        "enabled": true, "server_name": "www.microsoft.com",
        "reality": {
          "enabled": true,
          "handshake": { "server": "www.microsoft.com", "server_port": 443 },
          "private_key": "$pri", "short_id": [ "$sid" ]
        }
      }
    }
  ]
}
EOF
        if ! sing-box check -c ${CONF_DIR}/config.json >/dev/null; then echo -e "${gl_hong}配置生成错误${gl_bai}"; read -p "..."; return; fi

        echo -e "${gl_huang}保存连接信息...${gl_bai}"
        local ip=$(curl -s --max-time 3 https://ipinfo.io/ip)
        local code=$(curl -s --max-time 3 https://ipinfo.io/country | tr -d '\n')
        local flag=$(get_flag_local "$code")
        local link="vless://$uuid@$ip:$port?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&fp=chrome&pbk=$pub&sid=$sid&type=tcp&headerType=none#${flag}SingBox-Reality"

        echo -e "------------------------------------------------
${gl_kjlan}>>> 客户端连接信息 (Sing-box) <<<${gl_bai}
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
        systemctl restart sing-box
        view_sb
    }

    view_sb() {
        if [ -f "$INFO_FILE" ]; then clear; cat $INFO_FILE; else echo -e "${gl_hong}未找到配置，请先初始化${gl_bai}"; fi
        [ "${FUNCNAME[1]}" != "config_sb" ] && read -p "按回车返回..."
    }

    uninstall_sb() {
        echo -e "${gl_hong}警告: 将删除 Sing-box 程序及配置！${gl_bai}"
        read -p "确认? (y/n): " c
        if [[ "$c" == "y" ]]; then
            systemctl stop sing-box; apt purge sing-box -y; apt autoremove -y; rm -rf $CONF_DIR /usr/bin/sing-box
            echo -e "${gl_lv}已卸载${gl_bai}"
        fi
        read -p "按回车继续..."
    }

    while true; do
        clear
        echo -e "${gl_kjlan}################################################"
        echo -e "#            Sing-box 核心管理 (Reality)       #"
        echo -e "################################################${gl_bai}"
        if systemctl is-active --quiet sing-box; then 
            local v=$($BIN_PATH version | head -n 1 | awk '{print $3}')
            echo -e "状态: ${gl_lv}● 运行中${gl_bai} (Ver: $v)"
        else 
            echo -e "状态: ${gl_hong}● 已停止${gl_bai}"
        fi
        echo -e "------------------------------------------------"
        echo -e "${gl_lv} 1.${gl_bai} 安装/升级 (Install Latest)"
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
        read -p "选项: " c
        case "$c" in
            1) install_sb ;;
            2) config_sb ;;
            3) view_sb ;;
            4) 
                echo -e "${gl_huang}正在实时监控 Sing-box 日志...${gl_bai}"
                trap 'kill $log_pid 2>/dev/null; echo -e "\n${gl_lv}已停止监控。${gl_bai}"; return' SIGINT
                journalctl -u sing-box -n 50 -f &
                local log_pid=$!
                read -r -p ">>> 请按【回车键】或【Ctrl+C】停止查看 <<<"
                kill $log_pid >/dev/null 2>&1
                trap - SIGINT
                ;;
            5) systemctl restart sing-box; echo -e "${gl_lv}已重启${gl_bai}"; sleep 1 ;;
            6) systemctl stop sing-box; echo -e "${gl_hong}已停止${gl_bai}"; sleep 1 ;;
            9) uninstall_sb ;;
            0) return ;;
            *) echo "无效选项" ;;
        esac
    done
}
