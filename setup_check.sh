#!/usr/bin/env bash
# ============================================================
#  Operation Phantom Cart — Setup & Verification Script
#  Run this ONCE before the workshop to verify everything works
#  Usage: bash setup_check.sh
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
GOLD='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

PASS=0
FAIL=0

ok()   { echo -e "  ${GREEN}✓${NC}  $1"; ((PASS++)); }
fail() { echo -e "  ${RED}✗${NC}  $1"; ((FAIL++)); }
info() { echo -e "  ${BLUE}→${NC}  $1"; }
warn() { echo -e "  ${GOLD}!${NC}  $1"; }
section() { echo -e "\n${BOLD}$1${NC}"; echo "  $(printf '─%.0s' {1..50})"; }

echo ""
echo -e "${BOLD}  Operation Phantom Cart — Pre-Workshop Setup Check${NC}"
echo -e "  $(printf '═%.0s' {1..50})"

# ── 1. Python ──────────────────────────────────────────────
section "1. Python"
if command -v python3 &>/dev/null; then
    PY_VER=$(python3 --version 2>&1)
    ok "Python3 found: $PY_VER"
else
    fail "Python3 not found — install with: sudo apt install python3"
fi

# ── 2. Workshop files ──────────────────────────────────────
section "2. Workshop files"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for f in \
    "ctf/index.html" \
    "ctf/server.py" \
    "ctf/robots.txt" \
    "ctf/PRESENTER_ANSWERS.md" \
    "ctf/beginner/challenge1-source-secrets/index.html" \
    "ctf/beginner/challenge2-rogue-script/index.html" \
    "ctf/beginner/challenge3-decode-payload/index.html" \
    "ctf/beginner/challenge4-reflected-xss/index.html" \
    "ctf/intermediate/challenge5-idor/index.html" \
    "ctf/intermediate/challenge6-stored-xss/index.html" \
    "ctf/intermediate/challenge7-csp-analysis/index.html" \
    "ctf/advanced/challenge8-skimmer-autopsy/index.html" \
    "airnova-booking.html"
do
    if [ -f "$SCRIPT_DIR/$f" ]; then
        ok "$f"
    else
        fail "MISSING: $f"
    fi
done

# ── 3. Webhook URL configured ──────────────────────────────
section "3. Webhook URL"
if grep -q "YOUR-ID-HERE" "$SCRIPT_DIR/ctf/server.py" 2>/dev/null; then
    fail "server.py still has placeholder WEBHOOK_URL — replace YOUR-ID-HERE"
else
    ok "server.py webhook URL configured"
fi

if grep -q "YOUR-ID-HERE" "$SCRIPT_DIR/airnova-booking.html" 2>/dev/null; then
    fail "airnova-booking.html still has placeholder WEBHOOK_URL — replace YOUR-ID-HERE"
else
    ok "airnova-booking.html webhook URL configured"
fi

# ── 4. Port availability ───────────────────────────────────
section "4. Port 8080"
if ss -tlnp 2>/dev/null | grep -q ':8080'; then
    fail "Port 8080 is already in use — check with: ss -tlnp | grep 8080"
    warn "Kill the process using it: sudo fuser -k 8080/tcp"
else
    ok "Port 8080 is free"
fi

# ── 5. Network interfaces ──────────────────────────────────
section "5. Network interfaces"
echo ""
info "Your available IP addresses:"
ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | while read ip; do
    IFACE=$(ip -4 addr show | grep -B2 "$ip" | grep -oP '(?<=\d: )\w+')
    echo -e "     ${BOLD}$ip${NC}"
done

HOTSPOT_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)192\.168\.(43|44)\.\d+' 2>/dev/null | head -1)
if [ -n "$HOTSPOT_IP" ]; then
    ok "Phone hotspot IP detected: $HOTSPOT_IP"
    info "Share this with participants: http://$HOTSPOT_IP:8080"
else
    warn "No phone hotspot IP detected (192.168.43.x or 44.x range)"
    warn "If using hotspot: enable it on your phone first, then re-run this script"
    WIFI_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)192\.168\.\d+\.\d+' 2>/dev/null | head -1)
    if [ -n "$WIFI_IP" ]; then
        info "WiFi IP found: $WIFI_IP → http://$WIFI_IP:8080"
    fi
fi

# ── 6. Quick server smoke test ─────────────────────────────
section "6. Server smoke test"
cd "$SCRIPT_DIR/ctf" || { fail "Cannot cd into ctf/"; exit 1; }

# Start server in background
python3 server.py &>/tmp/ctf_test.log &
SERVER_PID=$!
sleep 2

if kill -0 $SERVER_PID 2>/dev/null; then
    ok "server.py starts without errors (PID $SERVER_PID)"

    # Test login page responds
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8080/ 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ]; then
        ok "Login page responds (HTTP 200)"
    else
        fail "Login page returned HTTP $HTTP_CODE (expected 200)"
    fi

    # Test blocked path
    BLOCK_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8080/PRESENTER_ANSWERS.md 2>/dev/null)
    if [ "$BLOCK_CODE" = "403" ]; then
        ok "PRESENTER_ANSWERS.md correctly blocked (HTTP 403)"
    else
        fail "PRESENTER_ANSWERS.md returned HTTP $BLOCK_CODE (expected 403)"
    fi

    # Test auth flow
    AUTH_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST http://127.0.0.1:8080/auth \
        -d "code=phantom2026" 2>/dev/null)
    if [ "$AUTH_CODE" = "302" ]; then
        ok "Auth with correct code redirects (HTTP 302)"
    else
        warn "Auth returned HTTP $AUTH_CODE — may still work in browser"
    fi

    kill $SERVER_PID 2>/dev/null
    wait $SERVER_PID 2>/dev/null
else
    fail "server.py crashed on startup — check: cat /tmp/ctf_test.log"
    cat /tmp/ctf_test.log
fi

cd "$SCRIPT_DIR" || true

# ── 7. UFW firewall ────────────────────────────────────────
section "7. Firewall"
if command -v ufw &>/dev/null; then
    UFW_STATUS=$(sudo ufw status 2>/dev/null | head -1)
    if echo "$UFW_STATUS" | grep -q "active"; then
        # Check if 8080 is allowed
        if sudo ufw status 2>/dev/null | grep -q "8080"; then
            ok "UFW active and port 8080 is allowed"
        else
            warn "UFW is active but port 8080 is NOT allowed"
            warn "Run: sudo ufw allow 8080/tcp"
            warn "Or temporarily disable: sudo ufw disable"
        fi
    else
        ok "UFW is inactive — no firewall blocking (fine for workshop)"
    fi
else
    ok "UFW not installed — no firewall to worry about"
fi

# ── SUMMARY ────────────────────────────────────────────────
echo ""
echo -e "${BOLD}  Summary${NC}"
echo "  $(printf '═%.0s' {1..50})"
if [ $FAIL -eq 0 ]; then
    echo -e "  ${GREEN}${BOLD}All checks passed ($PASS/$((PASS+FAIL)))${NC}"
    echo -e "  ${GREEN}You are ready to run the workshop.${NC}"
    echo ""

    # Print the launch command
    FINAL_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)192\.168\.\d+\.\d+' 2>/dev/null | head -1)
    echo -e "  ${BOLD}To start the server:${NC}"
    echo -e "  ${GOLD}  cd $(realpath "$SCRIPT_DIR/ctf") && python3 server.py${NC}"
    echo ""
    echo -e "  ${BOLD}Share with participants:${NC}"
    echo -e "  ${GOLD}  http://${FINAL_IP:-YOUR-IP}:8080${NC}"
    echo -e "  ${GOLD}  Access code: phantom2026${NC}"
else
    echo -e "  ${RED}${BOLD}$FAIL check(s) failed, $PASS passed${NC}"
    echo -e "  ${RED}Fix the issues above before the workshop.${NC}"
fi
echo ""
