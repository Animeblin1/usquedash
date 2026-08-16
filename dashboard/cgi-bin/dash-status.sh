#!/bin/sh
. "$(dirname "$0")/_lib.sh"

echo "Content-Type: application/json"
echo ""

NOW=$(date '+%Y-%m-%d %H:%M:%S')
UPTIME=$(uptime | sed 's/^[^,]*up *//; s/,.*//' | json_escape)
MEM=$(free | awk 'NR==2{printf "used %dMB / total %dMB / available %dMB", $3/1024, $2/1024, $7/1024}' | json_escape)
OVERLAY=$(df -h /overlay 2>/dev/null | awk 'NR==2{print $3" used / "$4" free / "$5" full"}' | json_escape)

USQUE_PID=$(ps w | grep usqu[e] | awk '{print $1}' | head -1)
if [ -n "$USQUE_PID" ]; then USQUE_STATUS="running"; else USQUE_STATUS="stopped"; fi
USQUE_AUTOSTART="no"
[ -e /etc/rc.d/S97usque ] && USQUE_AUTOSTART="yes"

if ip link show tun0 >/dev/null 2>&1; then
	TUN_STATUS="up"
	TUN_STATS=$(ip -s link show tun0 2>/dev/null | json_escape)
else
	TUN_STATUS="down"
	TUN_STATS=""
fi

WARP_ROUTE=$(ip route show table warp 2>/dev/null | json_escape)
WARP_RULES=$(ip rule show 2>/dev/null | grep warp | json_escape)

BYEDPI_COUNT=$(ps w | grep ciadp[i] | wc -l | tr -d ' ')
if [ -x /etc/init.d/byedpi ]; then
	if /etc/init.d/byedpi enabled 2>/dev/null; then BYEDPI_ENABLED="yes"; else BYEDPI_ENABLED="no"; fi
else
	BYEDPI_ENABLED="unknown"
fi
BYEDPI_STRATEGY=""
[ -f /etc/config/byedpi ] && BYEDPI_STRATEGY=$(grep "option cmd_opts" /etc/config/byedpi 2>/dev/null | head -1 | cut -d"'" -f2 | json_escape)

WHOL_STATE="unmanaged"
[ -f /etc/warp-wholelan ] && WHOL_STATE=$(cat /etc/warp-wholelan 2>/dev/null)
WHOL_RULE="no"
ip rule show 2>/dev/null | grep -q "priority 80" && WHOL_RULE="yes"

WATCHDOG_LOG=""
[ -f /var/log/usque-watchdog.log ] && WATCHDOG_LOG=$(tail -20 /var/log/usque-watchdog.log | json_escape)
WATCHDOG_CRON="no"
grep -q usque-watchdog /etc/crontabs/* 2>/dev/null && WATCHDOG_CRON="yes"

TARGETS_CRON="no"
grep -q warp-targets-apply /etc/crontabs/* 2>/dev/null && TARGETS_CRON="yes"

CLASH_IMPORTER="no"
[ -x /usr/bin/import-clash.sh ] && CLASH_IMPORTER="yes"

TARGETS_JSON=""
FIRST=1
if [ -f /etc/warp-targets.conf ]; then
	while IFS='|' read -r ip label src mode; do
		[ -z "$ip" ] && continue
		case "$ip" in \#*) continue ;; esac
		[ -z "$mode" ] && mode="warp"
		if ip rule show 2>/dev/null | grep -q "from ${ip} "; then
			ST="active"
		else
			ST="pending"
		fi
		IP_J=$(echo "$ip" | json_escape)
		LABEL_J=$(echo "$label" | json_escape)
		SRC_J=$(echo "$src" | json_escape)
		ITEM="{\"ip\":\"${IP_J}\",\"label\":\"${LABEL_J}\",\"src\":\"${SRC_J}\",\"mode\":\"${mode}\",\"status\":\"${ST}\"}"
		if [ "$FIRST" = "1" ]; then TARGETS_JSON="$ITEM"; FIRST=0; else TARGETS_JSON="${TARGETS_JSON},${ITEM}"; fi
	done < /etc/warp-targets.conf
fi

cat << EOF
{
  "time": "$NOW",
  "uptime": "$UPTIME",
  "memory": "$MEM",
  "overlay": "$OVERLAY",
  "usque": {
    "status": "$USQUE_STATUS",
    "pid": "$USQUE_PID",
    "autostart": "$USQUE_AUTOSTART"
  },
  "tunnel": {
    "status": "$TUN_STATUS",
    "stats": "$TUN_STATS"
  },
  "warp": {
    "routes": "$WARP_ROUTE",
    "rules": "$WARP_RULES"
  },
  "byedpi": {
    "process_count": $BYEDPI_COUNT,
    "enabled": "$BYEDPI_ENABLED",
    "strategy": "$BYEDPI_STRATEGY"
  },
  "wholelan": {
    "state": "$WHOL_STATE",
    "rule": "$WHOL_RULE"
  },
  "watchdog": {
    "cron_active": "$WATCHDOG_CRON",
    "log": "$WATCHDOG_LOG"
  },
  "targets_cron_active": "$TARGETS_CRON",
  "clash_importer": "$CLASH_IMPORTER",
  "targets": [ $TARGETS_JSON ]
}
EOF