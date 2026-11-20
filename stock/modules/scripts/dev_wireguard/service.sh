#!/system/bin/sh
# dev_wireguard: bring up the aosp-academy WireGuard tunnel (wg0) on the stock system at boot, the
# same tunnel the aosp-academy image brings up, so the device node reaches the phone over the
# tunnel on either system (aosp-academy deploy can then run without a cable).
#
# Everything private lives in /data/adb/aospacademy-wg (Magisk's root-only area, kept across
# reboots; stock's data is never wiped by a deploy): wg (built from the pinned wireguard-tools),
# wg0.conf (wg setconf format: the phone's private key and the hub peer) and wg0.env (ADDRESS4=,
# ADDRESS6=, ROUTES4=, ROUTES6=). aosp-academy stock tunnel puts them there. Without them, nothing
# happens. The kernel has WireGuard built in. Android routes by policy per network, so the
# tunnel's subnets get a table of their own (1999) and a rule ahead of the per-network rules.
# The result goes to /data/adb/aospacademy-wg/status. Disable the module and reboot to stop it.
D=/data/adb/aospacademy-wg
until [ "$(getprop sys.boot_completed)" = 1 ]; do sleep 2; done
[ -x "$D/wg" ] && [ -f "$D/wg0.conf" ] && [ -f "$D/wg0.env" ] || exit 0
umask 077
result() { echo "$*" > "$D/status"; log -t dev_wireguard "$*"; exit 0; }
val() { sed -n "s/^$1=//p" "$D/wg0.env" | head -n 1; }
a4="$(val ADDRESS4)"; a6="$(val ADDRESS6)"; r4="$(val ROUTES4)"; r6="$(val ROUTES6)"
ip link del wg0 2>/dev/null
ip link add wg0 type wireguard || result "failed: the kernel refused a wireguard link"
"$D/wg" setconf wg0 "$D/wg0.conf" || { ip link del wg0; result "failed: wg setconf"; }
[ -n "$a4" ] && ip addr add "$a4" dev wg0
[ -n "$a6" ] && ip -6 addr add "$a6" dev wg0
ip link set wg0 up || result "failed: wg0 did not come up"
for r in $r4; do
    ip route replace "$r" dev wg0 table 1999
    ip rule del to "$r" lookup 1999 2>/dev/null
    ip rule add to "$r" lookup 1999 priority 9000
done
for r in $r6; do
    ip -6 route replace "$r" dev wg0 table 1999
    ip -6 rule del to "$r" lookup 1999 2>/dev/null
    ip -6 rule add to "$r" lookup 1999 priority 9000
done
result "up ${a4%/*}"
