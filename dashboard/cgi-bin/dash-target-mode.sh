#!/bin/sh
. "$(dirname "$0")/_lib.sh"

echo "Content-Type: application/json"
echo ""
require_password

CONF="/etc/warp-targets.conf"
IP=""
MODE=""
for kv in $(echo "$QUERY_STRING" | tr '&' ' '); do
	key=${kv%%=*}
	val=${kv#*=}
	case "$key" in
		ip) IP="$val" ;;
		mode) MODE="$val" ;;
	esac
done
IP="$(urldecode "$IP")"
MODE="$(urldecode "$MODE")"

if ! is_valid_ip "$IP"; then
	echo '{"ok":false,"error":"некорректный IP"}'
	exit 0
fi
case "$MODE" in
	warp|direct|byedpi) ;;
	*) echo '{"ok":false,"error":"режим: warp, direct или byedpi"}'; exit 0 ;;
esac

LINE=$(grep "^${IP}|" "$CONF" 2>/dev/null | head -1)
if [ -z "$LINE" ]; then
	echo '{"ok":false,"error":"такого IP нет в списке"}'
	exit 0
fi

LABEL=$(echo "$LINE" | cut -d'|' -f2)
SRC=$(echo "$LINE" | cut -d'|' -f3)
grep -v "^${IP}|" "$CONF" > "${CONF}.tmp" && mv "${CONF}.tmp" "$CONF"
echo "${IP}|${LABEL}|${SRC}|${MODE}" >> "$CONF"
/usr/bin/warp-targets-apply.sh >/dev/null 2>&1
echo "{\"ok\":true,\"message\":\"${IP} переключён в режим ${MODE}\"}"