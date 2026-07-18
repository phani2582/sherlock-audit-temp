#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
REGISTRY_DIR="$(dirname "$DIR")"
GREEN='\033[0;32m'
DIM='\033[2m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo -e "${CYAN}──────────────────────────────────────────────${NC}"
echo -e "  Contract Registry — Install"
echo -e "${CYAN}──────────────────────────────────────────────${NC}"
echo ""

# 1. htpasswd
echo -e "  ${DIM}[1/4]${NC} htpasswd"
cp "$DIR/htpasswd_abi" /etc/nginx/.htpasswd_abi
chmod 640 /etc/nginx/.htpasswd_abi
chown root:www-data /etc/nginx/.htpasswd_abi
echo -e "        ${GREEN}ok${NC}  /etc/nginx/.htpasswd_abi"

# 2. nginx site
echo -e "  ${DIM}[2/4]${NC} nginx config"
rm -f /etc/nginx/sites-enabled/redeem.spiral.farm
cp "$DIR/contract-registry.nginx.conf" /etc/nginx/sites-available/contract-registry
ln -sf /etc/nginx/sites-available/contract-registry /etc/nginx/sites-enabled/contract-registry
nginx -t
systemctl reload nginx
echo -e "        ${GREEN}ok${NC}  nginx reloaded"

# 3. block SSH on 91.84.126.120
echo -e "  ${DIM}[3/4]${NC} block SSH on 91.84.126.120"
iptables -D INPUT -d 91.84.126.120 -p tcp --dport 22 -j DROP 2>/dev/null || true
iptables -I INPUT -d 91.84.126.120 -p tcp --dport 22 -j DROP
echo -e "        ${GREEN}ok${NC}  iptables: SSH dropped on 91.84.126.120"
if command -v netfilter-persistent &>/dev/null; then
    netfilter-persistent save
elif command -v iptables-save &>/dev/null; then
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4 2>/dev/null || iptables-save > /etc/iptables.rules
fi
echo -e "        ${GREEN}ok${NC}  iptables rules persisted"

# 4. pm2
echo -e "  ${DIM}[4/4]${NC} pm2"
sudo -u coder pm2 delete contract-registry 2>/dev/null || true
sudo -u coder pm2 start "$REGISTRY_DIR/ecosystem.config.cjs"
sudo -u coder pm2 save
echo -e "        ${GREEN}ok${NC}  pm2 started & saved"

echo ""
echo -e "${CYAN}──────────────────────────────────────────────${NC}"
echo -e "  ${GREEN}Done!${NC}"
echo ""
echo -e "  URL     http://91.84.126.120"
echo -e "  Auth    metric / ?_password2026"
echo -e "  SSH     blocked on 91.84.126.120"
echo -e "  PM2     pm2 status contract-registry"
echo ""
echo -e "${CYAN}──────────────────────────────────────────────${NC}"
echo ""
