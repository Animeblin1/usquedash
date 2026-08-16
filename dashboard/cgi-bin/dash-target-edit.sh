#!/bin/sh
. "$(dirname "$0")/_lib.sh"

echo "Content-Type: application/json"
echo ""
require_password

CONF="/etc/warp-targets.conf"
IP=""
LABEL=""
SRC=""
MODE=""
for kv in $(echo "$QUERY_STRING" | tr '&' ' '); do
	key=${kv%%=*}
	val=${kv#*=}
	case "$key" in
		ip) IP="$val" ;;
		label) LABEL="$val" ;;
		src) SRC="$val" ;;
		mode) MODE="$val" ;;
	esac
done

if ! is_valid_ip "$IP" || ! grep -q "^${IP}|" "$CONF" 2>/dev/null; then
	echo '{"ok":false,"error":"цель не найдена"}'
	exit 0
fi

case "$MODE" in
	warp|direct|byedpi) ;;
	*) echo '{"ok":false,"error":"режим: warp, direct или byedpi"}'; exit 0 ;;
esac

if ! is_valid_label "$LABEL"; then
	echo '{"ok":false,"error":"метка: только латиница/цифры/дефис/подчёркивание, до 32 символов"}'
	exit 0
fi

if [ -z "$SRC" ]; then
	SRC=$(grep "^${IP}|" "$CONF" | head -1 | cut -d'|' -f3)
fi
if ! is_valid_ip "$SRC" && ! is_valid_domain "$SRC"; then
	echo '{"ok":false,"error":"источник: IP или домен"}'
	exit 0
fi

sed -i "s@^${IP}|.*@${IP}|${LABEL}|${SRC}|${MODE}@" "$CONF"
/usr/bin/warp-targets-apply.sh >/dev/null 2>&1

echo "{\"ok\":true,\"message\":\"${IP} обновлён (${MODE})\"}"