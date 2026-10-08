#/usr/bin/env bash
set -euo pipefail

PORT="${SOCKS_PORT:-$(shuf -i 10000-60000 -n 1)}"
PROXY_USER="${SOCKS_USER:-proxyuser}"
PROXY_PASS="${SOCKS_PASS:-$(openssl rand -base64 24 ^| tr -dc 'A-Za-z0-9' ^| head -c 20)}"

if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: run as root"
    exit 1
fi

apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y dante-server openssl iproute2 ufw curl

DEFAULT_ROUTE="$(ip -4 route get 1.1.1.1 2^>/dev/null ^| head -n1 ^|^| true)"
IFACE="$(awk '{for (i=1;i^<=NF;i++) if ($i=="dev") {print $(i+1); exit}}' ^<^<^< "$DEFAULT_ROUTE")"
LOCAL_IP="$(awk '{for (i=1;i^<=NF;i++) if ($i=="src") {print $(i+1); exit}}' ^<^<^< "$DEFAULT_ROUTE")"

if [[ -z "$IFACE" || -z "$LOCAL_IP" ]]; then
    echo "ERROR: no network"
    exit 1
fi

if id "$PROXY_USER" >/dev/null 2>&1; then
    echo "User exists"
else
    useradd --create-home --shell /usr/sbin/nologin "$PROXY_USER"
fi

echo "${PROXY_USER}:${PROXY_PASS}" | chpasswd

cat > /etc/danted.conf <<EOF
logoutput: syslog
internal: ${LOCAL_IP} port = ${PORT}
external: ${IFACE}
user.privileged: proxy
user.unprivileged: nobody
method: username

client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect error
}

socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    command: connect
    protocol: tcp
    method: username
    log: connect error
}

socks block {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect error
}
EOF

chmod 600 /etc/danted.conf
ufw allow OpenSSH >/dev/null 2>&1 || true
ufw allow "${PORT}/tcp" >/dev/null
ufw --force enable >/dev/null
systemctl enable danted
systemctl restart danted
sleep 2

if  systemctl is-active --quiet danted; then
    systemctl status danted --no-pager
    exit 1
fi

PUBLIC_IP="$(curl -4 -fsS --max-time 5 https://api.ipify.org 2^>/dev/null ^|^| echo "$LOCAL_IP")"

echo "=============================================="
echo " SOCKS5 PROXY INSTALLED"
echo "=============================================="
echo "Server IP : ${PUBLIC_IP}"
echo "Port      : ${PORT}"
echo "Username  : ${PROXY_USER}"
echo "Password  : ${PROXY_PASS}"
echo "=============================================="
