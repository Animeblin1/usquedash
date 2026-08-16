#!/bin/sh
. "$(dirname "$0")/_lib.sh"

echo "Content-Type: application/json"
echo ""
require_password

CONF="/etc/warp-targets.conf"
PRIO=""
for kv in $(echo "$QUERY_STRING" | tr '&' ' '); do
	key=${kv%%=*}
	val=${kv#*=}
	[ "$key" = "prio" ] && PRIO="$val"
done

echo "$PRIO" | grep -qE '^[0-9]{1,3}$' || {
	echo '{"ok":false,"error":"некорректный приоритет"}'
	exit 0
}

RULE=$(ip rule show 2>/dev/null | grep -E "^${PRIO}:|priority ${PRIO}" | head -1)
[ -n "$RULE" ] || {
	echo '{"ok":false,"error":"правило не найдено"}'
	exit 0
}

FROM=$(echo "$RULE" | awk '{for(i=1;i<=NF;i++) if($i=="from") print $(i+1)}')
LOOKUP=$(echo "$RULE" | awk '{for(i=1;i<=NF;i++) if($i=="lookup") print $(i+1)}')

if ! is_valid_ip "$FROM"; then
	echo '{"ok":false,"error":"взять можно только правило с одиночным IP (без маски /24)"}'
	exit 0
fi
if [ "$LOOKUP" != "warp" ]; then
	echo '{"ok":false,"error":"взять можно только правило с таблицей warp"}'
	exit 0
fi
if grep -q "^${FROM}|" "$CONF" 2>/dev/null; then
	echo '{"ok":false,"error":"этот IP уже под управлением"}'
	exit 0
fi

ip rule del priority "$PRIO" 2>/dev/null
echo "${FROM}|импортированный|${FROM}|warp" >> "$CONF"
/usr/bin/warp-targets-apply.sh >/dev/null 2>&1

echo "{\"ok\":true,\"message\":\"правило ${PRIO} взято под управление (${FROM}, WARP)\"}"