#!/bin/sh
. "$(dirname "$0")/_lib.sh"

echo "Content-Type: application/json"
echo ""
require_password

CONF="/etc/warp-targets.conf"
TARGET=""
LABEL=""
for kv in $(echo "$QUERY_STRING" | tr '&' ' '); do
	key=${kv%%=*}
	val=${kv#*=}
	case "$key" in
		target) TARGET="$val" ;;
		label) LABEL="$val" ;;
	esac
done

if ! is_valid_label "$LABEL"; then
	echo '{"ok":false,"error":"метка: только латиница/цифры/дефис/подчёркивание, до 32 символов"}'
	exit 0
fi

if is_valid_ip "$TARGET"; then
	IP="$TARGET"
	SRC="$TARGET"
elif is_valid_domain "$TARGET"; then
	SRC="$TARGET"
	IP=$(nslookup "$TARGET" 2>/dev/null | awk '/^Address [0-9]+:/{print $3; exit} /^Address:/{a++; if(a>1){print $2; exit}}')
	if [ -z "$IP" ] || ! is_valid_ip "$IP"; then
		echo '{"ok":false,"error":"не удалось разрешить домен в IP (nslookup не дал ответа)"}'
		exit 0
	fi
else
	echo '{"ok":false,"error":"нужен IPv4 (192.168.1.50) или домен (youtube.com)"}'
	exit 0
fi

[ -z "$LABEL" ] && LABEL="$SRC"

touch "$CONF"
if grep -q "^${IP}|" "$CONF" 2>/dev/null; then
	echo '{"ok":false,"error":"этот IP уже в списке"}'
	exit 0
fi

echo "${IP}|${LABEL}|${SRC}" >> "$CONF"
/usr/bin/warp-targets-apply.sh >/dev/null 2>&1

if [ "$IP" = "$SRC" ]; then
	echo "{\"ok\":true,\"message\":\"${IP} добавлен в WARP\"}"
else
	echo "{\"ok\":true,\"message\":\"${SRC} -> ${IP} добавлен в WARP\"}"
fi