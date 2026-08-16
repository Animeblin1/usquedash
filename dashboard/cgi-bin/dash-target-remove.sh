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

if [ ! -f "$CONF" ] || ! grep -q "^${IP}|" "$CONF"; then
	echo '{"ok":false,"error":"такого IP нет в списке"}'
	exit 0
fi

grep -v "^${IP}|" "$CONF" > "${CONF}.tmp" && mv "${CONF}.tmp" "$CONF"
/usr/bin/warp-targets-apply.sh >/dev/null 2>&1
echo "{\"ok\":true,\"message\":\"${IP} убран из WARP\"}"