#!/bin/sh
. "$(dirname "$0")/_lib.sh"

echo "Content-Type: application/json"
echo ""
require_password

CONF="/etc/warp-targets.conf"
IP=""
for kv in $(echo "$QUERY_STRING" | tr '&' ' '); do
	key=${kv%%=*}
	val=${kv#*=}
	[ "$key" = "ip" ] && IP="$val"
done

if ! is_valid_ip "$IP"; then
	echo '{"ok":false,"error":"некорректный IP"}'
	exit 0
fi

LINE=$(grep "^${IP}|" "$CONF" 2>/dev/null | head -1)
if [ -z "$LINE" ]; then
	echo '{"ok":false,"error":"такого IP нет в списке"}'
	exit 0
fi

SRC=$(echo "$LINE" | cut -d'|' -f3)
if [ -z "$SRC" ] || ! is_valid_domain "$SRC"; then
	echo '{"ok":false,"error":"у записи нет домена для пере-резолва"}'
	exit 0
fi

NEW_IP=$(nslookup "$SRC" 2>/dev/null | awk '/^Address [0-9]+:/{print $3; exit} /^Address:/{a++; if(a>1){print $2; exit}}')
if [ -z "$NEW_IP" ] || ! is_valid_ip "$NEW_IP"; then
	echo '{"ok":false,"error":"не удалось разрешить домен заново"}'
	exit 0
fi

if [ "$NEW_IP" = "$IP" ]; then
	echo "{\"ok\":true,\"message\":\"${SRC} по-прежнему на ${IP}, менять нечего\"}"
	exit 0
fi

LABEL=$(echo "$LINE" | cut -d'|' -f2)
MODE=$(echo "$LINE" | cut -d'|' -f4)
grep -v "^${IP}|" "$CONF" > "${CONF}.tmp" && mv "${CONF}.tmp" "$CONF"
LINE_NEW="${NEW_IP}|${LABEL}|${SRC}"
[ -n "$MODE" ] && LINE_NEW="${LINE_NEW}|${MODE}"
echo "$LINE_NEW" >> "$CONF"
/usr/bin/warp-targets-apply.sh >/dev/null 2>&1
echo "{\"ok\":true,\"message\":\"${SRC}: ${IP} -> ${NEW_IP}\"}"