#!/bin/sh
# ==========================================================================
# NordVPN Lite — Standalone Uninstaller
# For OpenWrt 25.12 (apk) and 22.03/23.05/24.10 (opkg)
#
# Removes every trace of the NordVPN Lite LuCI console:
#   - running worker / daemon / WireGuard interfaces
#   - firewall zones, rules and forwardings  (nordvpnlite_*, nordwg, nvlwg0, tun)
#   - network interfaces (nordwg, nordwg_peer, nvlwg0, nvlwg0_peer)
#   - kernel artifacts (nft chain nvl_mss_out, ip rule lookup 100, table 100)
#   - conntrack table
#   - temp files (/tmp/nvl-*), lock dirs, and the application log
#   - LuCI view / menu / ACL / helper script
#   - optionally (--purge): DNS backup, /etc/nordvpnlite, NordVPN feed + key
#
# Usage:
#   sh uninstall.sh                  # light: leaves config + DNS backup
#   sh uninstall.sh --purge          # full:  removes config + DNS + repo
#   sh uninstall.sh --purge --force  # full, even if a server is pinned
#   sh uninstall.sh --dry-run        # show what WOULD be removed, change nothing
#   sh uninstall.sh --help
# ==========================================================================

set -u

PROG="nordvpnlite-uninstall"

# ------------------------------------------------------------------ log
say()  { printf '==> %s\n' "$*"; }
warn() { printf '!!  %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
hdr()  { printf '\n----- %s -----\n' "$*"; }

# ------------------------------------------------------------------ args
PURGE=0
FORCE=0
DRY=0

for a in "$@"; do
	case "$a" in
		--purge)  PURGE=1 ;;
		--force)  FORCE=1 ;;
		--dry-run|-n) DRY=1 ;;
		--help|-h)
			cat <<EOF
$PROG — remove NordVPN Lite from this router

Options:
  --purge         Also remove /etc/nordvpnlite, DNS backup, repo entries
  --force         Proceed even if a fixed server is still pinned
  --dry-run, -n   Print actions without performing them
  --help, -h      Show this help
EOF
			exit 0
			;;
		*)
			warn "unknown option: $a (ignored)"
			;;
	esac
done

# ------------------------------------------------------------------ root
[ "$(id -u)" = "0" ] || die "run as root"

# ------------------------------------------------------------------ exec wrapper
run() {
	if [ "$DRY" = "1" ]; then
		printf '   DRY: %s\n' "$*"
		return 0
	fi
	"$@"
}

# ------------------------------------------------------------------ preflight
hdr "Pre-flight"

_something=0
for _p in \
	/usr/libexec/nordvpnlite-ui \
	/www/luci-static/resources/view/nordvpnlite/settings.js \
	/usr/share/luci/menu.d/luci-app-nordvpnlite.json \
	/usr/share/rpcd/acl.d/luci-app-nordvpnlite-ui.json \
	/etc/nordvpnlite
do
	[ -e "$_p" ] && _something=1
done

if command -v uci >/dev/null 2>&1; then
	uci show firewall 2>/dev/null | grep -q 'nordvpnlite\|nordwg\|nvlwg0' && _something=1
	uci show network  2>/dev/null | grep -q 'nordwg\|nvlwg0' && _something=1
fi

if [ "$_something" = "0" ]; then
	say "Nothing to remove — no NordVPN Lite artifacts found."
	exit 0
fi

# ------------------------------------------------------------------ pin detection
_PINNED=0
if command -v uci >/dev/null 2>&1; then
	for _if in nordwg nvlwg0; do
		[ "$(uci -q get network.$_if 2>/dev/null)" = "interface" ] && _PINNED=1
	done
fi
[ -f /etc/nordvpnlite/managed_iface ] && _PINNED=1

if [ "$_PINNED" = "1" ] && [ "$FORCE" != "1" ]; then
	warn "A fixed server is still pinned."
	warn "  Run one of the following first:"
	warn "    /usr/libexec/nordvpnlite-ui killswitch-panic"
	warn "    /usr/libexec/nordvpnlite-ui wg-off"
	warn "  Or re-run this uninstaller with --force."
	exit 1
fi

# ==========================================================================
# 1. Stop the worker and daemon
# ==========================================================================
hdr "1. Stopping worker and daemon"

if [ -x /usr/libexec/nordvpnlite-ui ] && [ "$DRY" = "0" ]; then
	/usr/libexec/nordvpnlite-ui killswitch-panic >/dev/null 2>&1 || true
	/usr/libexec/nordvpnlite-ui wg-off           >/dev/null 2>&1 || true
	/usr/libexec/nordvpnlite-ui allowlist-clear  >/dev/null 2>&1 || true
fi

pkill -f 'nordvpnlite-ui wg-run' 2>/dev/null && say "killed stray worker" || true

if [ -x /etc/init.d/nordvpnlite ]; then
	run /etc/init.d/nordvpnlite stop
	run /etc/init.d/nordvpnlite disable
fi

# ==========================================================================
# 2. Bring down interfaces
# ==========================================================================
hdr "2. Tearing down WireGuard interfaces"

for _if in nordwg nvlwg0; do
	if [ -d "/sys/class/net/$_if" ]; then
		run ifdown "$_if"
	fi
done

# ==========================================================================
# 3. UCI cleanup — firewall + network
# ==========================================================================
if command -v uci >/dev/null 2>&1; then
	hdr "3. Cleaning UCI (firewall + network)"

	# --- all rules/zones/forwardings/redirects prefixed nordvpnlite_
	for S in $(uci show firewall 2>/dev/null \
		| sed -n "s/^firewall\.\(nordvpnlite_[^.]*\)=.*/\1/p"); do
		say "  delete firewall.$S"
		[ "$DRY" = "0" ] && uci -q delete "firewall.$S" || true
	done

	# --- any zone whose name is ours
	for Z in $(uci show firewall 2>/dev/null \
		| sed -n "s/^firewall\.\([^.=]*\)=zone$/\1/p"); do
		ZN=$(uci -q get "firewall.$Z.name" 2>/dev/null || true)
		case "$ZN" in
			nordwg|nvlwg0|nordvpnlite|tun)
				say "  delete firewall.$Z (zone name=$ZN)"
				[ "$DRY" = "0" ] && uci -q delete "firewall.$Z" || true
				;;
		esac
	done

	# --- forwardings that point at our zones
	for F in $(uci show firewall 2>/dev/null \
		| sed -n "s/^firewall\.\([^.=]*\)=forwarding$/\1/p"); do
		FD=$(uci -q get "firewall.$F.dest" 2>/dev/null || true)
		case "$FD" in
			nordwg|nvlwg0|nordvpnlite)
				say "  delete firewall.$F (dest=$FD)"
				[ "$DRY" = "0" ] && uci -q delete "firewall.$F" || true
				;;
		esac
	done

	# --- network interfaces
	for _if in nordwg nvlwg0; do
		if [ "$(uci -q get network.$_if 2>/dev/null)" = "interface" ]; then
			say "  delete network.$_if"
			[ "$DRY" = "0" ] && uci -q delete "network.$_if" || true
		fi
		if [ "$(uci -q get network.${_if}_peer 2>/dev/null)" = "wireguard_$_if" ]; then
			say "  delete network.${_if}_peer"
			[ "$DRY" = "0" ] && uci -q delete "network.${_if}_peer" || true
		fi
	done

	if [ "$DRY" = "0" ]; then
		uci commit firewall 2>/dev/null || true
		uci commit network  2>/dev/null || true
		/etc/init.d/firewall reload >/dev/null 2>&1 || true
		/etc/init.d/network  reload >/dev/null 2>&1 || true
	fi
else
	warn "uci not found — skipping UCI cleanup"
fi

# ==========================================================================
# 4. Kernel cleanup — nft, ip rule, ip route, conntrack
# ==========================================================================
hdr "4. Cleaning kernel state"

if command -v nft >/dev/null 2>&1; then
	if nft list chain inet fw4 nvl_mss_out >/dev/null 2>&1; then
		say "  flush nft chain inet fw4 nvl_mss_out"
		[ "$DRY" = "0" ] && nft flush  chain inet fw4 nvl_mss_out 2>/dev/null || true
		say "  delete nft chain inet fw4 nvl_mss_out"
		[ "$DRY" = "0" ] && nft delete chain inet fw4 nvl_mss_out 2>/dev/null || true
	fi
fi

if command -v ip >/dev/null 2>&1; then
	# ip rules with lookup 100
	_n=0
	for _p in $(ip rule show 2>/dev/null \
		| awk -F: '/lookup 100/{print $1}' | tr -d ' '); do
		say "  delete ip rule priority $_p"
		[ "$DRY" = "0" ] && ip rule del priority "$_p" 2>/dev/null || true
		_n=$((_n+1))
	done
	[ "$_n" = "0" ] && say "  no ip rule with lookup 100"

	# routing table 100
	if ip route show table 100 2>/dev/null | grep -q .; then
		say "  flush ip route table 100"
		[ "$DRY" = "0" ] && ip route flush table 100 2>/dev/null || true
	fi
fi

if command -v conntrack >/dev/null 2>&1; then
	say "  flush conntrack table"
	[ "$DRY" = "0" ] && conntrack -F >/dev/null 2>&1 || true
fi

# ==========================================================================
# 5. Optional — restore DNS from backup (only with --purge)
# ==========================================================================
if [ "$PURGE" = "1" ] && [ -f /etc/nordvpnlite/dns_backup ]; then
	hdr "5. Restoring DNS settings from backup"

	if [ "$DRY" = "1" ]; then
		say "  DRY: would restore dnsmasq/network DNS settings from /etc/nordvpnlite/dns_backup"
	else
		_BACKUP=/etc/nordvpnlite/dns_backup
		_FLAG=/etc/nordvpnlite/dns_hardened

		_dns_backup_get() {
			awk -F'\t' -v k="$1" '$1==k{sub(/^[^\t]*\t/,"");print;exit}' "$_BACKUP" 2>/dev/null
		}

		if command -v uci >/dev/null 2>&1; then
			if uci -q get dhcp.@dnsmasq[0] >/dev/null 2>&1; then
				uci -q delete dhcp.@dnsmasq[0].server   2>/dev/null || true
				uci -q delete dhcp.@dnsmasq[0].noresolv 2>/dev/null || true
				[ "$(_dns_backup_get dnsmasq_server_present)" = "1" ] && \
					for S in $(_dns_backup_get dnsmasq_server); do
						uci add_list dhcp.@dnsmasq[0].server="$S"
					done
				_NV=$(_dns_backup_get dnsmasq_noresolv)
				[ "$(_dns_backup_get dnsmasq_noresolv_present)" = "1" ] && \
					[ -n "$_NV" ] && uci set dhcp.@dnsmasq[0].noresolv="$_NV"
			fi

			for _if in $(uci show network 2>/dev/null \
				| sed -n "s/^network\.\([^.=]*\)=interface$/\1/p"); do
				_PP=$(_dns_backup_get "${_if}_peerdns_present")
				_DP=$(_dns_backup_get "${_if}_dns_present")
				[ -z "$_PP" ] && [ -z "$_DP" ] && continue
				if [ "$_PP" = "1" ]; then
					_PV=$(_dns_backup_get "${_if}_peerdns")
					[ -n "$_PV" ] && uci set network.${_if}.peerdns="$_PV" || \
						uci -q delete network.${_if}.peerdns 2>/dev/null || true
				else
					uci -q delete network.${_if}.peerdns 2>/dev/null || true
				fi
				uci -q delete network.${_if}.dns 2>/dev/null || true
				[ "$_DP" = "1" ] && for S in $(_dns_backup_get "${_if}_dns"); do
					uci add_list network.${_if}.dns="$S"
				done
			done
			uci commit network 2>/dev/null || true
			uci commit dhcp    2>/dev/null || true
		fi
		/etc/init.d/network  reload  >/dev/null 2>&1 || true
		/etc/init.d/dnsmasq  restart >/dev/null 2>&1 || true
		rm -f "$_FLAG" 2>/dev/null || true
		say "  DNS settings restored"
	fi
fi

# ==========================================================================
# 6. Remove installed LuCI files
# ==========================================================================
hdr "6. Removing installed files"

for F in \
	/www/luci-static/resources/view/nordvpnlite/settings.js \
	/usr/share/luci/menu.d/luci-app-nordvpnlite.json \
	/usr/share/rpcd/acl.d/luci-app-nordvpnlite-ui.json \
	/usr/libexec/nordvpnlite-ui
do
	if [ -e "$F" ]; then
		say "  rm $F"
		[ "$DRY" = "0" ] && rm -f "$F" || true
	fi
done

if [ -d /www/luci-static/resources/view/nordvpnlite ]; then
	say "  rmdir /www/luci-static/resources/view/nordvpnlite"
	[ "$DRY" = "0" ] && rmdir /www/luci-static/resources/view/nordvpnlite 2>/dev/null || true
fi

# ==========================================================================
# 7. Temp files and log
# ==========================================================================
hdr "7. Cleaning temp files and log"

for F in \
	/tmp/nvl-token.in \
	/tmp/nvl-public-ip \
	/tmp/nvl-status.cache \
	/tmp/nvl-v6-proof \
	/tmp/nvl-baseline-verdict \
	/tmp/nvl-rich-fp \
	/tmp/nvl-dns-last \
	/tmp/nvl-wg.cancel \
	/tmp/nvl-wg.result \
	/tmp/nvl-speedtest.stamp \
	/tmp/nvl-countries \
	/var/log/nordvpnlite.log
do
	[ -e "$F" ] && { say "  rm $F"; [ "$DRY" = "0" ] && rm -f "$F" || true; }
done

# wildcards — carefully
for pat in /tmp/nvl-servers-* /tmp/nvl-[cs]-* /tmp/nvl-lk.* /tmp/nvl-*.log; do
	for F in $pat; do
		[ -e "$F" ] && { say "  rm $F"; [ "$DRY" = "0" ] && rm -f "$F" || true; }
	done
done

if [ -d /tmp/nvl-api.lock ]; then
	say "  rm -r /tmp/nvl-api.lock"
	[ "$DRY" = "0" ] && rm -rf /tmp/nvl-api.lock || true
fi

# ==========================================================================
# 8. --purge extras
# ==========================================================================
if [ "$PURGE" = "1" ]; then
	hdr "8. Purging repo entries and /etc/nordvpnlite"

	# repo key and feed
	[ -f /etc/apk/repositories.d/nordvpn.list ] && {
		say "  rm /etc/apk/repositories.d/nordvpn.list"
		[ "$DRY" = "0" ] && rm -f /etc/apk/repositories.d/nordvpn.list || true
	}
	[ -f /etc/apk/keys/nordvpnlite-apk.rsa.pub ] && {
		say "  rm /etc/apk/keys/nordvpnlite-apk.rsa.pub"
		[ "$DRY" = "0" ] && rm -f /etc/apk/keys/nordvpnlite-apk.rsa.pub || true
	}
	[ -f /etc/opkg/keys/nordvpn-feed.pub ] && {
		say "  rm /etc/opkg/keys/nordvpn-feed.pub"
		[ "$DRY" = "0" ] && rm -f /etc/opkg/keys/nordvpn-feed.pub || true
	}
	if [ -f /etc/opkg/customfeeds.conf ] && \
	   grep -q 'downloads.nordcdn.com/nordvpnlite/feeds' /etc/opkg/customfeeds.conf; then
		say "  filter /etc/opkg/customfeeds.conf"
		if [ "$DRY" = "0" ]; then
			_T=$(mktemp)
			grep -vF 'downloads.nordcdn.com/nordvpnlite/feeds' \
				/etc/opkg/customfeeds.conf > "$_T" 2>/dev/null || true
			mv "$_T" /etc/opkg/customfeeds.conf
		fi
	fi

	# config directory
	if [ -d /etc/nordvpnlite ]; then
		say "  rm -r /etc/nordvpnlite"
		[ "$DRY" = "0" ] && rm -rf /etc/nordvpnlite || true
	fi
else
	hdr "8. Kept (no --purge)"

	say "  /etc/nordvpnlite/  (config, DNS backup, allowlist)"
	say "  /etc/apk/repositories.d/nordvpn.list"
	say "  /etc/apk/keys/nordvpnlite-apk.rsa.pub"
	say ""
	say "  Re-run with '--purge' to remove these too."
fi

# ==========================================================================
# 9. Reload UI backends
# ==========================================================================
hdr "9. Reloading rpcd / uhttpd"

[ "$DRY" = "0" ] && {
	/etc/init.d/rpcd   restart >/dev/null 2>&1 || true
	/etc/init.d/uhttpd restart >/dev/null 2>&1 || true
	rm -f /tmp/luci-indexcache /tmp/luci-modulecache/* 2>/dev/null || true
}

# ==========================================================================
# Summary
# ==========================================================================
printf '\n'
if [ "$DRY" = "1" ]; then
	printf '==== DRY RUN COMPLETE — no changes were made ====\n'
	printf 'Re-run without --dry-run to apply.\n'
else
	printf '==== Uninstall complete ====\n'
	printf 'The upstream "nordvpnlite" package was left installed.\n'
	printf 'To remove it as well, run:\n'
	printf '    apk del nordvpnlite    # OpenWrt 25.12+\n'
	printf '    opkg remove nordvpnlite   # OpenWrt 22.03–24.10\n'
fi