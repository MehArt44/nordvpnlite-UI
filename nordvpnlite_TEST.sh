#!/bin/sh
# nvl-selftest.sh — NordVPN Lite v624 comprehensive self-test
# For OpenWrt 25.12 + GL.iNet MT3000 (also works on generic OpenWrt)
# Safe to publish: no secrets, no real IPs beyond the first two octets.

PASS=0; FAIL=0; WARN=0; SKIP=0
ok()   { PASS=$((PASS+1)); printf '  \033[32m[PASS]\033[0m %s\n' "$*"; }
no()   { FAIL=$((FAIL+1)); printf '  \033[31m[FAIL]\033[0m %s\n' "$*"; }
warn() { WARN=$((WARN+1)); printf '  \033[33m[WARN]\033[0m %s\n' "$*"; }
skip() { SKIP=$((SKIP+1)); printf '  \033[36m[SKIP]\033[0m %s\n' "$*"; }
info() { printf '  \033[36m[INFO]\033[0m %s\n' "$*"; }
sect() { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }

MODE=$(cat /etc/nordvpnlite/mode 2>/dev/null || echo lite)
KS=$(cat /etc/nordvpnlite/killswitch 2>/dev/null || echo off)

# ============================================================ 1. Environment
sect "1. Environment"

[ -r /etc/openwrt_release ] && {
    . /etc/openwrt_release
    info "OpenWrt: ${DISTRIB_RELEASE:-?} (${DISTRIB_ARCH:-unknown})"
}
[ -r /etc/os-release ] && . /etc/os-release && info "Host: ${PRETTY_NAME:-unknown}"

PKG_MGR=""
command -v apk  >/dev/null 2>&1 && PKG_MGR=apk
command -v opkg >/dev/null 2>&1 && PKG_MGR=opkg
[ -n "$PKG_MGR" ] && info "PkgMgr: $PKG_MGR" || no "no pkg manager found"

if [ "$PKG_MGR" = apk ]; then
    NVL_VER=$(apk list -I nordvpnlite 2>/dev/null | head -n1 | sed -E 's/^nordvpnlite-([0-9][^ ]*).*/\1/')
else
    NVL_VER=$(opkg list-installed nordvpnlite 2>/dev/null | awk '{print $3}' | head -n1)
fi
[ -n "$NVL_VER" ] && ok "nordvpnlite $NVL_VER installed" || no "nordvpnlite not installed"

for TOOL in curl jsonfilter uci nft ip wg; do
    command -v "$TOOL" >/dev/null 2>&1 && ok "$TOOL present" || no "$TOOL MISSING"
done
command -v conntrack >/dev/null 2>&1 && ok "conntrack present" \
    || warn "conntrack missing (KS flush degraded)"
command -v nslookup  >/dev/null 2>&1 || warn "nslookup missing (DNS test limited)"

# ============================================================ 2. Files
sect "2. Installed files"

for F in \
    /usr/libexec/nordvpnlite-ui \
    /www/luci-static/resources/view/nordvpnlite/settings.js \
    /usr/share/luci/menu.d/luci-app-nordvpnlite.json \
    /usr/share/rpcd/acl.d/luci-app-nordvpnlite-ui.json
do
    [ -r "$F" ] && ok "present: $F" || no "missing: $F"
done
[ -x /usr/libexec/nordvpnlite-ui ] && ok "helper executable" \
    || no "helper NOT executable"

if grep -q 'v624' /usr/libexec/nordvpnlite-ui 2>/dev/null; then
    ok "v624 patch present in helper"
elif grep -q 'v623' /usr/libexec/nordvpnlite-ui 2>/dev/null; then
    warn "helper at v623 — v624 (KS direction fix) MISSING"
else
    warn "helper version marker not found"
fi

if [ -r /usr/share/rpcd/acl.d/luci-app-nordvpnlite-ui.json ]; then
    grep -q 'nordvpnlite-ui' /usr/share/rpcd/acl.d/luci-app-nordvpnlite-ui.json \
        && ok "ACL references helper" || no "ACL does not reference helper"
fi

# ============================================================ 3. Config
sect "3. Config files"

CONFIG=/etc/nordvpnlite/config.json
[ -r "$CONFIG" ] && ok "config.json present" || no "config.json MISSING"

for F in dns.conf ipv6_mode doh_mode wg_mtu lan_discovery allowlist pq analytics killswitch; do
    [ -r "/etc/nordvpnlite/$F" ] || warn "  $F missing"
done

if command -v jsonfilter >/dev/null 2>&1; then
    T=$(jsonfilter -i "$CONFIG" -e '@.authentication_token' 2>/dev/null | head -n1)
    case "$T" in
        ""|null|NULL|Null|None|undefined) no "token empty / invalid" ;;
        *) [ ${#T} -ge 20 ] && ok "token present (${#T} chars, hidden)" \
                            || no "token too short: ${#T} chars" ;;
    esac
fi

# ============================================================ 4. Helper actions
sect "4. Helper actions available"

for ACT in status route-check dns-status ipv6-status killswitch-status \
           ui-config wg-debug baseline-info public-ip version; do
    /usr/libexec/nordvpnlite-ui "$ACT" >/dev/null 2>&1 \
        && ok "action works: $ACT" || no "action FAILED: $ACT"
done

info "version: $(/usr/libexec/nordvpnlite-ui version 2>/dev/null)"

# ============================================================ 5. Mode/pin
sect "5. Mode and pin"
info "mode: $MODE"

if [ "$MODE" = wg ]; then
    HOST=$(sed -n 's/^host=//p' /etc/nordvpnlite/pinned 2>/dev/null | head -n1)
    IP=$(sed -n 's/^ip=//p' /etc/nordvpnlite/pinned 2>/dev/null | head -n1)
    [ -n "$HOST" ] && ok "pinned host: $HOST" || no "pinned host empty"
    case "$IP" in
        ""|null) no "pinned IP invalid" ;;
        *)       ok "pinned IP:   $IP" ;;
    esac
fi

# ============================================================ 6. Firewall zones
sect "6. Firewall zones and NAT"

case "$MODE" in
    wg)
        Z=$(uci -q get firewall.nordwg_zone.network 2>/dev/null | tr '\n' ' ')
        [ -n "$Z" ] && ok "nordwg zone members: $Z" \
                    || no "nordwg zone empty (NAT will fail)"
        [ "$(uci -q get firewall.nordwg_zone.masq 2>/dev/null)" = 1 ] \
            && ok "nordwg masq=1" || no "nordwg masq != 1"
        ;;
    lite)
        Z=$(uci -q get firewall.nordvpnlite_zone.network 2>/dev/null | tr '\n' ' ')
        [ -n "$Z" ] && ok "nordvpnlite zone members: $Z" \
                    || no "nordvpnlite zone empty (NAT will fail)"
        ;;
esac

if nft list ruleset 2>/dev/null | grep -q 'Masquerade IPv4 nordwg traffic'; then
    ok "nordwg masquerade rule present in kernel"
else
    case "$MODE" in
        wg) no "nordwg masquerade MISSING in kernel" ;;
        *)  skip "nordwg masquerade (lite mode)" ;;
    esac
fi

# ============================================================ 7. WireGuard
sect "7. WireGuard tunnel"

if [ "$MODE" != wg ]; then
    skip "not in wg mode"
elif wg show nordwg >/dev/null 2>&1; then
    ok "nordwg interface exists"
    HS=$(wg show nordwg latest-handshakes 2>/dev/null | awk 'NR==1{print $2}')
    if [ -n "$HS" ] && [ "${HS:-0}" -gt 0 ] 2>/dev/null; then
        AGE=$(( $(date +%s) - HS ))
        [ "$AGE" -lt 180 ] && ok "handshake fresh (${AGE}s ago)" \
                           || warn "handshake stale (${AGE}s ago)"
    else
        no "no handshake yet"
    fi
    IP=$(ip -4 addr show nordwg 2>/dev/null | awk '/inet /{print $2;exit}')
    [ -n "$IP" ] && ok "nordwg IPv4: $IP" || no "nordwg has no IPv4"
else
    no "nordwg interface does not exist"
fi

# ============================================================ 8. Routing
sect "8. Routing"

DEF=$(ip -4 route show default | head -n1)
case "$DEF" in
    *"dev nordwg"*) ok "default route via nordwg" ;;
    "")             no "no default route at all" ;;
    *)              no "default route NOT via nordwg" ;;
esac

R=$(/usr/libexec/nordvpnlite-ui route-check 2>/dev/null)
[ "$R" = vpn ] && ok "route-check = vpn" || warn "route-check = $R"

if ip rule show 2>/dev/null | grep -q 'lookup 100'; then
    info "ip rule lookup 100 (allowlist) present"
fi

# ============================================================ 9. Connectivity
sect "9. Connectivity"

ping -c2 -W3 1.1.1.1 >/dev/null 2>&1 && ok "ping 1.1.1.1 via tunnel" \
    || no "ping 1.1.1.1 FAILED"

H=$(curl -m 10 -s -o /dev/null -w '%{http_code}' https://1.1.1.1/ 2>/dev/null)
case "$H" in 200|301|302) ok "HTTPS 1.1.1.1 -> $H" ;;
             *) no "HTTPS 1.1.1.1 failed (code=$H)" ;; esac

H=$(curl -m 10 -s -o /dev/null -w '%{http_code}' https://www.google.com/ 2>/dev/null)
case "$H" in 200|301|302) ok "HTTPS google.com -> $H" ;;
             *) no "HTTPS google.com failed (code=$H)" ;; esac

# ============================================================ 10. DNS
sect "10. DNS"

DS=$(/usr/libexec/nordvpnlite-ui dns-status 2>/dev/null)
case "$DS" in
    protected) ok "dns-status = protected" ;;
    partial)   warn "dns-status = partial (some queries may leak)" ;;
    leak)      no "dns-status = LEAK" ;;
    *)         warn "dns-status = $DS" ;;
esac

NR=$(uci -q get dhcp.@dnsmasq[0].noresolv 2>/dev/null)
[ "$NR" = 1 ] && ok "dnsmasq noresolv=1" || warn "dnsmasq noresolv != 1"

_ALL_NORD=1
for S in $(uci -q get dhcp.@dnsmasq[0].server 2>/dev/null); do
    case "$S" in
        103.86.96.100|103.86.99.100) ;;
        *) _ALL_NORD=0 ;;
    esac
done
[ "$_ALL_NORD" = 1 ] && ok "dnsmasq only uses Nord DNS" \
                     || warn "dnsmasq has non-Nord upstream servers"

if command -v nslookup >/dev/null 2>&1; then
    nslookup nordvpn.com 127.0.0.1 >/dev/null 2>&1 \
        && ok "resolve via dnsmasq works" \
        || no "resolve via dnsmasq FAILED"
fi

# ============================================================ 11. IPv6
sect "11. IPv6"

V6=$(/usr/libexec/nordvpnlite-ui ipv6-status 2>/dev/null)
V6P=$(/usr/libexec/nordvpnlite-ui ipv6-public-check 2>/dev/null)
case "$V6" in
    disabled)  ok "IPv6 disabled router-wide" ;;
    tunneled)  ok "IPv6 tunneled via VPN" ;;
    enabled)
        case "$V6P" in
            *no_route*) ok "IPv6 enabled but no default route (cannot leak)" ;;
            *fail*)     no "IPv6 reachable externally — potential leak" ;;
            *)          warn "IPv6 status: enabled ($V6P)" ;;
        esac
        ;;
    *) info "IPv6 status: $V6" ;;
esac

V6DEF=$(ip -6 route show default 2>/dev/null | head -n1)
[ -z "$V6DEF" ] && ok "no IPv6 default route (cannot leak)" \
                || info "IPv6 default: $V6DEF"

# ============================================================ 12. Kill switch
sect "12. Kill switch"
info "killswitch state: $KS"

if [ "$KS" = on ]; then
    F1=$(uci -q get firewall.@defaults[0].flow_offloading 2>/dev/null)
    F2=$(uci -q get firewall.@defaults[0].flow_offloading_hw 2>/dev/null)
    case "$F1:$F2" in
        0:0) ok "flow offload disabled (KS can enforce)" ;;
        *)   no "flow offload $F1/$F2 — KS bypassed by HW!" ;;
    esac

    nft list ruleset 2>/dev/null | grep -q 'NordVPN Lite KS escape' \
        && ok "escape-hatch rules present in kernel" \
        || no "escape-hatch rules MISSING"

    C=$(nft list ruleset 2>/dev/null | grep -c 'NordVPN Lite KS - forward')
    if [ "$C" -gt 0 ]; then
        ok "KS reject rules in kernel: $C"
    else
        no "KS reject rules MISSING — fw4 rejected 'direction=forward'"
        info "  → apply patch_v624.py, reinstall, then re-enable KS"
    fi
else
    skip "Kill switch is OFF — rule checks skipped"
    info "  (enable KS and rerun to test the reject rules)"
fi

# ============================================================ 13. UI backend
sect "13. UI backend (rpcd)"
/etc/init.d/rpcd   status >/dev/null 2>&1 && ok "rpcd running"   || warn "rpcd status unclear"
/etc/init.d/uhttpd status >/dev/null 2>&1 && ok "uhttpd running" || warn "uhttpd status unclear"

# ============================================================ 14. Log
sect "14. Log file"
LOG=/var/log/nordvpnlite.log
if [ -r "$LOG" ]; then
    SZ=$(wc -c < "$LOG" 2>/dev/null || echo 0)
    info "log size: $SZ bytes"
    [ "$SZ" -gt 0 ] && [ "$SZ" -lt 2000000 ] \
        && ok "log within reasonable bounds" \
        || warn "log size out of normal range"
    ERRS=$(grep -c ERROR "$LOG" 2>/dev/null || echo 0)
    info "recent ERROR lines: $ERRS"
else
    warn "log file not yet created"
fi

# ============================================================ 15. Performance
sect "15. Performance snapshot"

PING=$(ping -c3 -W3 1.1.1.1 2>/dev/null | awk -F'/' '/avg/{print $5}')
[ -n "$PING" ] && info "ping avg: ${PING} ms" || info "ping avg: unavailable"

DL=$(curl -m 8 -s -o /dev/null -w '%{size_download}' \
    'https://speed.cloudflare.com/__down?bytes=1000000' 2>/dev/null)
[ -n "$DL" ] && info "download 1MB: $(( DL / 1024 )) KB" || info "download: n/a"

PUB=$(/usr/libexec/nordvpnlite-ui public-ip 2>/dev/null)
case "$PUB" in
    ""|null) info "public IP: unavailable" ;;
    *)       info "public IP prefix: $(printf '%s' "$PUB" | cut -d. -f1-2).x.x" ;;
esac

# ============================================================ Summary
sect "Summary"
printf '  PASS: %s\n' "$PASS"
printf '  FAIL: %s\n' "$FAIL"
printf '  WARN: %s\n' "$WARN"
printf '  SKIP: %s\n' "$SKIP"
echo
if [ "$FAIL" -gt 0 ]; then
    printf '\033[31mSome tests FAILED — see above for details.\033[0m\n'
else
    printf '\033[32mAll critical tests passed.\033[0m\n'
fi

echo
echo "Run finished at $(date -Iseconds)"