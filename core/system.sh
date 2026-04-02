system_initialize() {
    clear
    echo -e "${gl_kjlan}################################################"
    echo -e "#     系统初始化、时钟同步与网络调优 (Debian)  #"
    echo -e "################################################${gl_bai}"
    
    # --- 1. 系统版本严格校验 ---
    local os_ver=""
    if grep -q "bullseye" /etc/os-release; then 
        os_ver="11"
        echo -e "当前系统: ${gl_huang}Debian 11 (Bullseye)${gl_bai}"
    elif grep -q "bookworm" /etc/os-release; then 
        os_ver="12"
        echo -e "当前系统: ${gl_huang}Debian 12 (Bookworm)${gl_bai}"
    else 
        echo -e "${gl_hong}错误: 本模块仅支持 Debian 11 或 12 系统！${gl_bai}"
        read -p "按回车返回..."
        return
    fi

    echo -e "${gl_kjlan}>>> 正在配置 Debian 官方源...${gl_bai}"
    [ -f /etc/apt/sources.list ] && mv /etc/apt/sources.list /etc/apt/sources.list.bak_$(date +%F)
    if [ "$os_ver" == "11" ]; then
        echo -e "deb http://deb.debian.org/debian bullseye main contrib non-free\ndeb http://deb.debian.org/debian bullseye-updates main contrib non-free\ndeb http://security.debian.org/debian-security bullseye-security main contrib non-free\ndeb http://archive.debian.org/debian bullseye-backports main contrib non-free" > /etc/apt/sources.list
    else
        echo -e "deb http://deb.debian.org/debian/ bookworm main contrib non-free non-free-firmware\ndeb http://deb.debian.org/debian-security/ bookworm-security main contrib non-free non-free-firmware\ndeb http://deb.debian.org/debian/ bookworm-updates main contrib non-free non-free-firmware\ndeb http://deb.debian.org/debian/ bookworm-backports main contrib non-free non-free-firmware" > /etc/apt/sources.list
    fi

    # --- 2. 系统升级与工具安装 ---
    echo -e "${gl_kjlan}>>> 正在更新系统并安装基础组件...${gl_bai}"
    export DEBIAN_FRONTEND=noninteractive
    apt update && apt upgrade -y -o Dpkg::Options::="--force-confold" --ignore-missing
    # 直接安装 chrony 等运维必备工具 (去掉 systemd-timesyncd)
    apt install wget rsync socat chrony unzip -y

# [系统优化] SSH 深度安全加固与稳定性优化
optimize_ssh() {
    echo -e "${gl_kjlan}>>> 正在执行 SSH 深度安全加固与稳定性优化...${gl_bai}"
    local ssh_conf="/etc/ssh/sshd_config"
    
    # 备份原始配置
    [ ! -f "${ssh_conf}.bak" ] && cp "$ssh_conf" "${ssh_conf}.bak"

    # 1. 稳定性与速度优化 (心跳包 + 禁用 DNS 反查)
    sed -i 's/^#\?ClientAliveInterval.*/ClientAliveInterval 60/' "$ssh_conf"
    sed -i 's/^#\?ClientAliveCountMax.*/ClientAliveCountMax 5/' "$ssh_conf"
    sed -i 's/^#\?UseDNS.*/UseDNS no/' "$ssh_conf"

    # 2. 安全认证加固 (缩短宽限时间 + 限制尝试次数)
    sed -i 's/^#\?LoginGraceTime.*/LoginGraceTime 1m/' "$ssh_conf"
    sed -i 's/^#\?MaxAuthTries.*/MaxAuthTries 3/' "$ssh_conf"
    sed -i 's/^#\?StrictModes.*/StrictModes yes/' "$ssh_conf"

    # 3. 禁用不必要的功能 (防止 X11 转发漏洞 + 禁用键盘交互认证)
    sed -i 's/^#\?X11Forwarding.*/X11Forwarding no/' "$ssh_conf"
    sed -i 's/^#\?KbdInteractiveAuthentication.*/KbdInteractiveAuthentication no/' "$ssh_conf"

    # 检查语法并重启
    if sshd -t &>/dev/null; then
        systemctl restart sshd
    else
        echo -e "${gl_hong}错误: SSH 配置语法检查失败，已回退配置！${gl_bai}"
        cp "${ssh_conf}.bak" "$ssh_conf"
        systemctl restart sshd
    fi
}
    
    # --- 3. 时间同步与时区配置 (Chrony 高精度方案) ---
    echo -e "${gl_kjlan}>>> 正在配置时区与 Chrony 高可用同步源...${gl_bai}"
    timedatectl set-timezone Asia/Shanghai

    # 停止并彻底屏蔽系统自带的 timesyncd，防止双服务冲突
    systemctl stop systemd-timesyncd 2>/dev/null
    systemctl mask systemd-timesyncd.service

    # 备份默认配置并清理自带 NTP 节点
    [ -f /etc/chrony/chrony.conf ] && cp /etc/chrony/chrony.conf /etc/chrony/chrony.conf.bak
    sed -i 's/^pool/#pool/g' /etc/chrony/chrony.conf
    sed -i 's/^server/#server/g' /etc/chrony/chrony.conf

    # 写入公共高可用 NTP 节点 (Cloudflare + Google 容灾)
    cat >> /etc/chrony/chrony.conf << EOF

# 自定义高可用 NTP 服务器 (Cloudflare + Google)
server time.cloudflare.com iburst
server time.google.com iburst
EOF

    systemctl enable --now chrony
    systemctl restart chrony

    # --- 4. 动态计算内存并分配 TCP 缓冲区 ---
    echo -e "${gl_kjlan}>>> 正在计算物理内存并分配 TCP 缓冲区...${gl_bai}"
    local total_mem=$(free -m | awk '/^Mem:/{print $2}')
    local buf_max="33554432" # 默认 32MB
    
    if [ "$total_mem" -le 600 ]; then
        buf_max="8388608"
        echo -e "检测到极小内存 (${total_mem}MB)，采用保守缓冲区策略 (8MB)"
    elif [ "$total_mem" -le 2048 ]; then
        buf_max="33554432"
        echo -e "检测到标准内存 (${total_mem}MB)，采用均衡缓冲区策略 (32MB)"
    else
        buf_max="67108864"
        echo -e "检测到大容量内存 (${total_mem}MB)，采用激进缓冲区策略 (64MB)"
    fi

    # --- 5. 写入 TCP 深度调优与 BBR 配置 ---
    echo -e "${gl_kjlan}>>> 正在写入 TCP 深度调优与 BBR 配置...${gl_bai}"
    rm -f /etc/sysctl.d/99-vps-optimize.conf
    
    cat > /etc/sysctl.d/99-vps-optimize.conf << EOF
# ── BBR 拥塞控制 ──
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# ── 动态缓冲区分配 (${buf_max} 字节) ──
net.core.rmem_default = 262144
net.core.wmem_default = 262144
net.core.rmem_max = ${buf_max}
net.core.wmem_max = ${buf_max}
net.ipv4.tcp_rmem = 4096 87380 ${buf_max}
net.ipv4.tcp_wmem = 4096 65536 ${buf_max}
net.ipv4.tcp_mem = 786432 1048576 26777216

# ── TIME_WAIT 连接回收与复用 ──
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_max_tw_buckets = 20000

# ── 连接保活 (keepalive) ──
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 6

# ── SYN 握手防洪 ──
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_syn_retries = 3
net.ipv4.tcp_synack_retries = 3
net.ipv4.tcp_max_syn_backlog = 8192
net.core.somaxconn = 8192

# ── 端口范围与 MTU 探测 ──
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_mtu_probing = 1

# ── 队列与 TCP 快速选项 ──
net.core.netdev_max_backlog = 10000
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_sack = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_no_metrics_save = 1

# ── 连接追踪表与防报错 ──
net.netfilter.nf_conntrack_max = 1000000
net.nf_conntrack_max = 1000000
net.netfilter.nf_conntrack_tcp_timeout_established = 7200

# ── 提升文件描述符 ──
fs.file-max = 1000000
EOF

    # 持久化提升系统文件描述符限制
    if ! grep -q "# tcp-tune" /etc/security/limits.conf 2>/dev/null; then
        cat >> /etc/security/limits.conf <<'EOF'

# tcp-tune: 提升文件描述符限制
* soft nofile 1000000
* hard nofile 1000000
root soft nofile 1000000
root hard nofile 1000000
EOF
    fi

    sysctl --system 2>/dev/null | grep -v "nf_conntrack" >/dev/null

    # --- 6. 垃圾清理 ---
    echo -e "${gl_kjlan}>>> 正在清理系统缓存垃圾...${gl_bai}"
    apt autoremove -y && apt clean

    # --- 7. 初始化报告 ---
    echo -e "\n${gl_lv}====== 基建、网络优化与时钟同步已就绪 ======${gl_bai}"
    local bbr_status=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    local cur_wmem=$(sysctl -n net.core.wmem_max 2>/dev/null)
    local wmem_mb=$((cur_wmem / 1024 / 1024))
    local fw_v4=$(sysctl -n net.ipv4.ip_forward 2>/dev/null)
    local fw_v6=$(sysctl -n net.ipv6.conf.all.forwarding 2>/dev/null)
    
    echo -e " 1. BBR 拥塞控制: \t${gl_kjlan}${bbr_status}${gl_bai}"
    echo -e " 2. TCP 缓冲上限: \t${gl_kjlan}${wmem_mb} MB${gl_bai}"
    echo -e " 3. 系统网络转发: \t${gl_bai}v4->${fw_v4} v6->${fw_v6}${gl_bai}"
    echo -e " 4. 当前系统时间: \t${gl_bai}$(date "+%Y-%m-%d %H:%M:%S") (CST)${gl_bai}"
    echo -e "------------------------------------------------"
    echo -e "${gl_huang} Chrony 同步源状态 (chronyc sources -v):${gl_bai}"
    chronyc sources -v
    echo -e "------------------------------------------------"
    
    if [ -f /var/run/reboot-required ]; then
        echo -e "${gl_hong}!!! 检测到内核/组件更新，必须重启 !!!${gl_bai}"
        read -p "是否立即重启? (y/n): " rb
        [[ "$rb" =~ ^[yY]$ ]] && reboot
    else
        read -p "按回车返回主菜单..."
    fi
}
