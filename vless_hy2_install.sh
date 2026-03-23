#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

msg() { echo -e "$1"; }
die() { msg "${RED}❌ $1${NC}"; exit 1; }

[[ ${EUID:-$(id -u)} -eq 0 ]] || die "请用 root 运行此脚本"

if command -v apt >/dev/null 2>&1; then
  PKG_UPDATE='apt update -y'
  PKG_INSTALL='apt install -y'
  OS_FAMILY='debian'
elif command -v dnf >/dev/null 2>&1; then
  PKG_UPDATE='dnf makecache'
  PKG_INSTALL='dnf install -y'
  OS_FAMILY='redhat'
elif command -v yum >/dev/null 2>&1; then
  PKG_UPDATE='yum makecache'
  PKG_INSTALL='yum install -y'
  OS_FAMILY='redhat'
else
  die '不支持的系统，未找到 apt/dnf/yum'
fi

msg "${CYAN}==> 安装依赖${NC}"
eval "$PKG_UPDATE"
eval "$PKG_INSTALL curl wget unzip openssl tar jq ufw qrencode socat"

mkdir -p /etc/xray /etc/hysteria /etc/hysteria/certs /var/log/xray /usr/local/bin /root

get_public_ip() {
  curl -4 -fsSL --max-time 8 https://api.ipify.org || \
  curl -4 -fsSL --max-time 8 https://ipv4.icanhazip.com || \
  curl -4 -fsSL --max-time 8 https://ifconfig.me || true
}

PUBLIC_IP="$(get_public_ip | tr -d '[:space:]')"
[[ -n "$PUBLIC_IP" ]] || die '获取公网 IPv4 失败'

rand_port() {
  shuf -i 20000-45000 -n 1
}

HY2_PORT="$(rand_port)"
while :; do
  VLESS_PORT="$(rand_port)"
  [[ "$VLESS_PORT" != "$HY2_PORT" ]] && break
done
HOP_START=$((HY2_PORT + 1000))
HOP_END=$((HOP_START + 99))
[[ $HOP_END -le 65535 ]] || { HOP_START=50000; HOP_END=50099; }

DOMAIN="www.nvidia.com"
HY2_SNI="$DOMAIN"
HY2_OBFS_PASSWORD='cry_me_a_r1ver'
HY2_AUTH_PASSWORD="$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)"
VLESS_UUID="$(cat /proc/sys/kernel/random/uuid)"
VLESS_EMAIL="user$(openssl rand -hex 3)"
VLESS_SHORT_ID="$(openssl rand -hex 4)"

msg "${CYAN}==> 安装 Xray${NC}"
XRAY_VERSION='v25.8.3'
XRAY_ZIP="/tmp/xray.zip"
curl -fsSL -o "$XRAY_ZIP" "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-64.zip"
unzip -o "$XRAY_ZIP" -d /tmp/xray-bin >/dev/null
install -m 755 /tmp/xray-bin/xray /usr/local/bin/xray
rm -rf /tmp/xray-bin "$XRAY_ZIP"

msg "${CYAN}==> 安装 Hysteria2${NC}"
bash <(curl -fsSL https://get.hy2.sh/)

msg "${CYAN}==> 生成 VLESS Reality 密钥${NC}"
REALITY_KEYS="$(/usr/local/bin/xray x25519)"
REALITY_PRIVATE_KEY="$(echo "$REALITY_KEYS" | awk '/Private key/ {print $3}')"
REALITY_PUBLIC_KEY="$(echo "$REALITY_KEYS" | awk '/Public key/ {print $3}')"
[[ -n "$REALITY_PRIVATE_KEY" && -n "$REALITY_PUBLIC_KEY" ]] || die 'Reality 密钥生成失败'

msg "${CYAN}==> 生成 Hysteria2 证书${NC}"
openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
  -keyout /etc/hysteria/certs/key.pem \
  -out /etc/hysteria/certs/cert.pem \
  -subj "/CN=${DOMAIN}" -days 3650 >/dev/null 2>&1
chmod 600 /etc/hysteria/certs/key.pem
chmod 644 /etc/hysteria/certs/cert.pem

msg "${CYAN}==> 写入 Xray 配置${NC}"
cat > /etc/xray/config.json <<EOF_JSON
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
            "id": "${VLESS_UUID}",
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
          "shortIds": ["${VLESS_SHORT_ID}"]
        },
        "tcpSettings": {
          "acceptProxyProtocol": false,
          "header": {"type": "none"}
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    }
  ],
  "outbounds": [
    {"protocol": "freedom", "tag": "direct"},
    {"protocol": "blackhole", "tag": "blocked"}
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "blocked"
      }
    ]
  }
}
EOF_JSON

msg "${CYAN}==> 写入 Hysteria2 配置${NC}"
cat > /etc/hysteria/config.yaml <<EOF_YAML
listen: :${HY2_PORT}
tls:
  cert: /etc/hysteria/certs/cert.pem
  key: /etc/hysteria/certs/key.pem
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
  up: 100 mbps
  down: 100 mbps
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
    url: https://${DOMAIN}
    rewriteHost: true
transport:
  type: udp
  udp:
    hopInterval: 30s
    hopPortRange: ${HOP_START}-${HOP_END}
EOF_YAML

msg "${CYAN}==> 网络优化（统一为兼容双协议的方案）${NC}"
cat > /etc/sysctl.d/99-dual-proxy.conf <<'EOF_SYSCTL'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = cubic
net.core.rmem_max = 268435456
net.core.wmem_max = 268435456
net.core.rmem_default = 262144
net.core.wmem_default = 262144
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384
net.core.netdev_max_backlog = 250000
net.core.netdev_budget = 6000
net.ipv4.tcp_fastopen = 3
fs.file-max = 1000000
vm.swappiness = 10
EOF_SYSCTL
sysctl --system >/dev/null 2>&1 || true
modprobe -r tcp_bbr >/dev/null 2>&1 || true

msg "${CYAN}==> 创建 systemd 服务${NC}"
cat > /etc/systemd/system/xray.service <<'EOF_XSVC'
[Unit]
Description=Xray Service
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF_XSVC

mkdir -p /etc/systemd/system/hysteria-server.service.d
cat > /etc/systemd/system/hysteria-server.service.d/override.conf <<'EOF_HSVC'
[Service]
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576
EOF_HSVC

systemctl daemon-reload
systemctl enable xray >/dev/null 2>&1
systemctl enable hysteria-server.service >/dev/null 2>&1

msg "${CYAN}==> 配置防火墙（不重置现有规则）${NC}"
ufw allow 22/tcp >/dev/null 2>&1 || true
ufw allow ${VLESS_PORT}/tcp >/dev/null 2>&1 || true
ufw allow ${HY2_PORT}/udp >/dev/null 2>&1 || true
ufw allow ${HOP_START}:${HOP_END}/udp >/dev/null 2>&1 || true
ufw --force enable >/dev/null 2>&1 || true

msg "${CYAN}==> 启动服务${NC}"
systemctl restart xray
systemctl restart hysteria-server.service
sleep 2
systemctl is-active --quiet xray || die 'Xray 启动失败，请执行: journalctl -u xray -n 100 --no-pager'
systemctl is-active --quiet hysteria-server.service || die 'Hysteria2 启动失败，请执行: journalctl -u hysteria-server.service -n 100 --no-pager'

VLESS_LINK="vless://${VLESS_UUID}@${PUBLIC_IP}:${VLESS_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${DOMAIN}&fp=chrome&pbk=${REALITY_PUBLIC_KEY}&sid=${VLESS_SHORT_ID}&type=tcp&headerType=none#VLESS-Reality-${PUBLIC_IP}"
HY2_LINK="hysteria2://${HY2_AUTH_PASSWORD}@${PUBLIC_IP}:${HY2_PORT}/?sni=${HY2_SNI}&obfs=salamander&obfs-password=${HY2_OBFS_PASSWORD}&insecure=1#HY2-${PUBLIC_IP}"

cat > /root/dual-proxy-info.txt <<EOF_INFO
===============================
Dual Proxy Install Success
===============================
Public IP: ${PUBLIC_IP}

[VLESS Reality]
Port: ${VLESS_PORT}
UUID: ${VLESS_UUID}
SNI: ${DOMAIN}
Public Key: ${REALITY_PUBLIC_KEY}
Short ID: ${VLESS_SHORT_ID}
Link:
${VLESS_LINK}

[Hysteria2]
Port: ${HY2_PORT}
Auth Password: ${HY2_AUTH_PASSWORD}
SNI: ${HY2_SNI}
Obfs: salamander
Obfs Password: ${HY2_OBFS_PASSWORD}
Hop Range: ${HOP_START}-${HOP_END}
Link:
${HY2_LINK}

[Files]
/etc/xray/config.json
/etc/hysteria/config.yaml
/root/dual-proxy-info.txt
EOF_INFO

jq -n \
  --arg public_ip "$PUBLIC_IP" \
  --arg vless_port "$VLESS_PORT" \
  --arg uuid "$VLESS_UUID" \
  --arg domain "$DOMAIN" \
  --arg pbk "$REALITY_PUBLIC_KEY" \
  --arg sid "$VLESS_SHORT_ID" \
  --arg vless_link "$VLESS_LINK" \
  --arg hy2_port "$HY2_PORT" \
  --arg hy2_auth "$HY2_AUTH_PASSWORD" \
  --arg hy2_sni "$HY2_SNI" \
  --arg hy2_obfs "$HY2_OBFS_PASSWORD" \
  --arg hop_range "${HOP_START}-${HOP_END}" \
  --arg hy2_link "$HY2_LINK" \
  '{
    public_ip: $public_ip,
    vless: {
      port: $vless_port,
      uuid: $uuid,
      sni: $domain,
      public_key: $pbk,
      short_id: $sid,
      link: $vless_link
    },
    hysteria2: {
      port: $hy2_port,
      auth_password: $hy2_auth,
      sni: $hy2_sni,
      obfs: "salamander",
      obfs_password: $hy2_obfs,
      hop_range: $hop_range,
      link: $hy2_link
    },
    files: [
      "/etc/xray/config.json",
      "/etc/hysteria/config.yaml",
      "/root/dual-proxy-info.txt"
    ]
  }' > /root/dual-proxy-config.json

msg "${GREEN}========================================${NC}"
msg "${GREEN}✅ 双协议安装完成${NC}"
msg "${GREEN}公网 IP: ${PUBLIC_IP}${NC}"
msg "${GREEN}VLESS 端口: ${VLESS_PORT}/tcp${NC}"
msg "${GREEN}HY2 端口: ${HY2_PORT}/udp${NC}"
msg "${GREEN}跳跃端口: ${HOP_START}-${HOP_END}/udp${NC}"
msg "${GREEN}配置汇总: /root/dual-proxy-info.txt${NC}"
msg "${GREEN}JSON 导出: /root/dual-proxy-config.json${NC}"
msg "${GREEN}========================================${NC}"
msg "${WHITE}VLESS 链接:${NC}"
echo "$VLESS_LINK"
msg "${WHITE}HY2 链接:${NC}"
echo "$HY2_LINK"
