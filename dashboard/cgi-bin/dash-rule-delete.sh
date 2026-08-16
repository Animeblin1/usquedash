#!/bin/sh
. "$(dirname "$0")/_lib.sh"

echo "Content-Type: application/json"
echo ""
require_password

PRIO=""
for kv in $(echo "$QUERY_STRING" | tr '&' ' '); do
	key=${kv%%=*}
	val=${kv#*=}
	[ "$key" = "prio" ] && PRIO="$val"
done

echo "$PRIO" | grep -qE '^[0-9]{1,5}$' || {
	echo '{"ok":false,"error":"некорректный приоритет"}'
	exit 0
}

[ "$PRIO" -gt 70 ] 2>/dev/null || {
	echo '{"ok":false,"error":"системные правила (70 и ниже) не удаляются"}'
	exit 0
}
[ "$PRIO" -ne 80 ] 2>/dev/null || {
	echo '{"ok":false,"error":"правило 80 — WholeLAN, управляется кнопкой"}'
	exit 0
}

RULE=$(ip rule show 2>/dev/null | grep -E "^${PRIO}:|priority ${PRIO}" | head -1)
[ -n "$RULE" ] || {
	echo '{"ok":false,"error":"правило не найдено"}'
	exit 0
}

ip rule del priority "$PRIO" 2>/dev/null

echo "{\"ok\":true,\"message\":\"правило ${PRIO} удалено\"}"