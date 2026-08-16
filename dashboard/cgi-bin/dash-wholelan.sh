#!/bin/sh
. "$(dirname "$0")/_lib.sh"

echo "Content-Type: application/json"
echo ""
require_password

STATE=""
for kv in $(echo "$QUERY_STRING" | tr '&' ' '); do
	key=${kv%%=*}
	val=${kv#*=}
	[ "$key" = "state" ] && STATE="$val"
done

case "$STATE" in
	on|off) ;;
	*) echo '{"ok":false,"error":"state: on или off"}'; exit 0 ;;
esac

if [ "$STATE" = "on" ]; then
	echo "1" > /etc/warp-wholelan
else
	echo "0" > /etc/warp-wholelan
fi
/usr/bin/warp-targets-apply.sh >/dev/null 2>&1

if [ "$STATE" = "on" ]; then
	echo '{"ok":true,"message":"WholeLAN включён: весь LAN идёт через WARP (ByeDPI для целей теперь не работает)"}'
else
	echo '{"ok":true,"message":"WholeLAN выключен: WARP только для целей, ByeDPI снова работает"}'
fi