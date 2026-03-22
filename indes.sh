#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# Dual Stack Installer
# VLESS Reality + Hysteria2
# Tested idea for Debian / Ubuntu
# =========================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'
BOLD='\033[1m'

info()  { echo -e "${BLUE}${BOLD}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}${BOLD}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}${BOLD}[WARN]${NC} $*"; }
err()   { echo -e "${RED}${BOLD}[ERR]${NC} $*"; }

trap 'err "出错行: $LINENO, 命令: $BASH_COMMAND"' ERR

# -----------------------------
# 基础检查
# -----------------------------
if [[ $EUID -ne 0 ]]; then
  err "请用 root 运行"
  exit 1
fi

if command -v apt >/dev/null 2>&1; then
  PKG_UPDATE="apt update -y"
  PKG_INSTALL="apt install -y"
elif command -v dnf >/dev/null 2>&1; then
  PKG_UPDATE="dnf makecache"
  PKG_INSTALL="dnf install -y"
elif command -v yum >/dev/null 2>&1; then
  PKG_UPDATE="yum makecache"
  PKG_INSTALL="yum install -y"
else
  err "不支持的系统包管理器"
  exit 1
fi

# -----------------------------
# 变量
# -----------------------------
XRAY_VERSION="v25.8.3"
XRAY_ZIP_URL="https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-64.zip"
XRAY_BIN="/usr/local/bin/xray"

DOMAIN="www.nvidia.com"
HY2_SNI="www.nvidia.com"
HY2_MASQ_URL="https://www.nvidia.com"
HY2_OBFS_PASSWORD="cry_me_a_r1ver"

UUID="$(cat /proc/sys/kernel/random/uuid)"
VLESS_EMAIL="$(openssl rand -hex 4)"
REALITY_SHORT_ID="$(openssl rand -hex 4)"
HY2_AUTH_PASSWORD="$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)"

VLESS_PORT=$((RANDOM % 7001 + 2000))
HY2_PORT=$((RANDOM % 7001 + 2000))

while [[ "$HY2_PORT" == "$VLESS_PORT" ]]; do
  HY2_PORT=$((RANDOM % 7001 + 2000))
done

HY2_HOP_START=$((RANDOM % 6901 + 2100))
HY2_HOP_END=$((HY2_HOP_START + 99))
if [[ $HY2_HOP_END -gt 9000 ]]; then
  HY2_HOP_END=9000
  HY2_HOP_START=8901
fi
HY2_HOP_RANGE="${HY2_HOP_START}-${HY2_HOP_END}"

SERVER_IP=""
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64) XRAY_ARCH="64" ;;
  aarch64|arm64) XRAY_ARCH="arm64-v8a" ;;
  *) XRAY_ARCH="64" ;;
esac

# -----------------------------
# 横幅
# -----------------------------
clear
echo -e "${CYAN}${BOLD}"
echo "=============================================================="
echo "   Dual Installer: VLESS Reality + Hysteria2"
echo "=============================================================="
echo -e "${NC}"

# -----------------------------
# 安装依赖
# -----------------------------
info "安装依赖..."
export DEBIAN_FRONTEND=noninteractive || true
$PKG_UPDATE >/dev/null 2>&1
$PKG_INSTALL curl wget unzip openssl jq qrencode ca-certificates ufw >/dev/null 2>&1 || true
ok "依赖安装完成"

# -----------------------------
# 获取公网IP
# -----------------------------
info "获取公网 IP..."
SERVER_IP="$(curl -4 -s --max-time 10 https://api.ipify.org || true)"
[[ -z "$SERVER_IP" ]] && SERVER_IP="$(curl -4 -s --max-time 10 https://ipv4.icanhazip.com || true)"
[[ -z "$SERVER_IP" ]] && SERVER_IP="$(curl -4 -s --max-time 10 https://ifconfig.me || true)"

if [[ -z "$SERVER_IP" ]]; then
  err "无法获取公网 IPv4"
  exit 1
fi
ok "公网 IP: ${SERVER_IP}"

# -----------------------------
# 开启BBR（仅对TCP有利，不再和HY2冲突）
# -----------------------------
info "配置 BBR（给 VLESS/TCP 用）..."
cat >/etc/sysctl.d/99-dual-proxy.conf <<'EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_fastopen = 3
net.core.netdev_max_backlog = 5000
fs.file-max = 1000000
EOF

sysctl --system >/dev/null 2>&1 || true
modprobe tcp_bbr >/dev/null 2>&1 || true
modprobe sch_fq >/dev/null 2>&1 || true
ok "BBR 配置完成"

# -----------------------------
# 防火墙
# -----------------------------
info "配置防火墙..."
if command -v ufw >/dev/null 2>&1; then
  ufw --force reset >/dev/null 2>&1 || true
  ufw default deny incoming >/dev/null 2>&1 || true
  ufw default allow outgoing >/dev/null 2>&1 || true

  ufw allow 22/tcp >/dev/null 2>&1 || true
  ufw allow ${VLESS_PORT}/tcp >/dev/null 2>&1 || true
  ufw allow ${HY2_PORT}/udp >/dev/null 2>&1 || true
  ufw allow ${HY2_HOP_START}:${HY2_HOP_END}/udp >/dev/null 2>&1 || true

  ufw --force enable >/dev/null 2>&1 || true
  ok "UFW 已放行: 22/tcp, ${VLESS_PORT}/tcp, ${HY2_PORT}/udp, ${HY2_HOP_RANGE}/udp"
else
  warn "未检测到 ufw，请自行开放端口"
fi

# -----------------------------
# 安装 Xray
# -----------------------------
info "安装 Xray ${XRAY_VERSION}..."
mkdir -p /usr/local/bin
cd /usr/local/bin

curl -L "${XRAY_ZIP_URL}" -o xray.zip >/dev/null 2>&1
unzip -o xray.zip >/dev/null 2>&1
chmod +x xray
rm -f xray.zip
ok "Xray 安装完成"

# -----------------------------
# 生成 Reality 密钥
# -----------------------------
info "生成 Reality 密钥..."
REALITY_KEYS="$(${XRAY_BIN} x25519)"
REALITY_PRIVATE_KEY="$(echo "${REALITY_KEYS}" | awk '/Private key/ {print $3}')"
REALITY_PUBLIC_KEY="$(echo "${REALITY_KEYS}" | awk '/Public key/ {print $3}')"
ok "Reality 密钥生成完成"

# -----------------------------
# 配置 Xray
# -----------------------------
info "生成 Xray 配置..."
mkdir -p /etc/xray /var/log/xray

cat >/etc/xray/config.json <<EOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [
    {
      "port": ${VLESS_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "flow": "xtls-rprx-vision",
            "email": "${VLESS_EMAIL}"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${DOMAIN}:443",
          "xver": 0,
          "serverNames": ["${DOMAIN}"],
          "privateKey": "${REALITY_PRIVATE_KEY}",
          "shortIds": ["${REALITY_SHORT_ID}"]
        },
        "tcpSettings": {
          "acceptProxyProtocol": false
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {},
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ]
}
EOF

cat >/etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service (VLESS Reality Vision)
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
ExecStart=${XRAY_BIN} run -config /etc/xray/config.json
Restart=on-failure
RestartSec=5s
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable xray >/dev/null 2>&1
systemctl restart xray
sleep 2

if systemctl is-active --quiet xray; then
  ok "Xray 已启动"
else
  err "Xray 启动失败"
  journalctl -u xray --no-pager -n 50
  exit 1
fi

# -----------------------------
# 安装 Hysteria2
# -----------------------------
info "安装 Hysteria2..."
bash <(curl -fsSL https://get.hy2.sh/) >/dev/null 2>&1
ok "Hysteria2 安装完成"

# -----------------------------
# 生成 HY2 证书
# -----------------------------
info "生成 Hysteria2 自签证书..."
mkdir -p /etc/hysteria/certs
openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
  -keyout /etc/hysteria/certs/key.pem \
  -out /etc/hysteria/certs/cert.pem \
  -subj "/CN=${HY2_SNI}" -days 3650 >/dev/null 2>&1

chmod 600 /etc/hysteria/certs/key.pem
chmod 644 /etc/hysteria/certs/cert.pem
ok "证书生成完成"

# -----------------------------
# HY2 带宽参数（保守值，避免ATAS卡顿/乱填）
# -----------------------------
HY2_UP="50"
HY2_DOWN="100"

# -----------------------------
# 配置 Hysteria2
# -----------------------------
info "生成 Hysteria2 配置..."
cat >/etc/hysteria/config.yaml <<EOF
listen: :${HY2_PORT}

tls:
  cert: /etc/hysteria/certs/cert.pem
  key: /etc/hysteria/certs/key.pem
  sni: ${HY2_SNI}

obfs:
  type: salamander
  salamander:
    password: ${HY2_OBFS_PASSWORD}

quic:
  initStreamReceiveWindow: 26843545
  maxStreamReceiveWindow: 26843545
  initConnReceiveWindow: 67108864
  maxConnReceiveWindow: 67108864
  maxIdleTimeout: 30s
  maxIncomingStreams: 1024
  disablePathMTUDiscovery: false

bandwidth:
  up: ${HY2_UP} mbps
  down: ${HY2_DOWN} mbps

ignoreClientBandwidth: false
speedTest: true
disableUDP: false
udpIdleTimeout: 60s

auth:
  type: password
  password: ${HY2_AUTH_PASSWORD}

masquerade:
  type: proxy
  proxy:
    url: ${HY2_MASQ_URL}
    rewriteHost: true

transport:
  type: udp
  udp:
    hopInterval: 30s
    hopPortRange: ${HY2_HOP_RANGE}
EOF

systemctl enable hysteria-server.service >/dev/null 2>&1 || true
systemctl restart hysteria-server.service
sleep 2

if systemctl is-active --quiet hysteria-server.service; then
  ok "Hysteria2 已启动"
else
  err "Hysteria2 启动失败"
  journalctl -u hysteria-server.service --no-pager -n 50
  exit 1
fi

# -----------------------------
# 生成链接
# -----------------------------
VLESS_LINK="vless://${UUID}@${SERVER_IP}:${VLESS_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${DOMAIN}&fp=chrome&pbk=${REALITY_PUBLIC_KEY}&sid=${REALITY_SHORT_ID}&type=tcp&headerType=none#VLESS-Reality-${SERVER_IP}"

HY2_LINK="hysteria2://${HY2_AUTH_PASSWORD}@${SERVER_IP}:${HY2_PORT}/?sni=${HY2_SNI}&obfs=salamander&obfs-password=${HY2_OBFS_PASSWORD}&insecure=1&upmbps=${HY2_UP}&downmbps=${HY2_DOWN}#HY2-${SERVER_IP}"

# -----------------------------
# 导出客户端文件
# -----------------------------
mkdir -p /root/proxy-configs

cat >/root/proxy-configs/hysteria2_client.yaml <<EOF
server: ${SERVER_IP}:${HY2_PORT}
auth: ${HY2_AUTH_PASSWORD}
tls:
  sni: ${HY2_SNI}
  insecure: true
obfs:
  type: salamander
  salamander:
    password: ${HY2_OBFS_PASSWORD}
transport:
  type: udp
  udp:
    hopInterval: 30s
    hopPortRange: ${HY2_HOP_RANGE}
bandwidth:
  up: ${HY2_UP} mbps
  down: ${HY2_DOWN} mbps
fastOpen: true
lazy: true
socks5:
  listen: 127.0.0.1:1080
http:
  listen: 127.0.0.1:1080
EOF

cat >/root/proxy-configs/vless_reality.json <<EOF
{
  "server": "${SERVER_IP}",
  "port": ${VLESS_PORT},
  "uuid": "${UUID}",
  "flow": "xtls-rprx-vision",
  "security": "reality",
  "sni": "${DOMAIN}",
  "fp": "chrome",
  "publicKey": "${REALITY_PUBLIC_KEY}",
  "shortId": "${REALITY_SHORT_ID}",
  "link": "${VLESS_LINK}"
}
EOF

# -----------------------------
# 输出结果
# -----------------------------
clear
echo -e "${GREEN}${BOLD}==============================================================${NC}"
echo -e "${GREEN}${BOLD}                 双协议部署完成${NC}"
echo -e "${GREEN}${BOLD}==============================================================${NC}"
echo

echo -e "${WHITE}${BOLD}服务器信息${NC}"
echo -e "IP:              ${YELLOW}${SERVER_IP}${NC}"
echo -e "VLESS端口:       ${YELLOW}${VLESS_PORT}/tcp${NC}"
echo -e "HY2端口:         ${YELLOW}${HY2_PORT}/udp${NC}"
echo -e "HY2跳跃端口:     ${YELLOW}${HY2_HOP_RANGE}/udp${NC}"
echo

echo -e "${WHITE}${BOLD}VLESS Reality 链接${NC}"
echo -e "${CYAN}${VLESS_LINK}${NC}"
echo

echo -e "${WHITE}${BOLD}Hysteria2 链接${NC}"
echo -e "${CYAN}${HY2_LINK}${NC}"
echo

echo -e "${WHITE}${BOLD}本地配置文件${NC}"
echo -e "/root/proxy-configs/vless_reality.json"
echo -e "/root/proxy-configs/hysteria2_client.yaml"
echo

echo -e "${WHITE}${BOLD}服务状态命令${NC}"
echo -e "systemctl status xray"
echo -e "systemctl status hysteria-server.service"
echo -e "journalctl -u xray -f"
echo -e "journalctl -u hysteria-server.service -f"
echo

echo -e "${WHITE}${BOLD}二维码（VLESS）${NC}"
qrencode -o - -t ANSIUTF8 "${VLESS_LINK}" || true
echo

echo -e "${WHITE}${BOLD}二维码（HY2）${NC}"
qrencode -o - -t ANSIUTF8 "${HY2_LINK}" || true
echo

ok "部署完成"
