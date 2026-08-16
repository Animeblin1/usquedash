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

IP="$(urldecode "$IP")"
LABEL="$(urldecode "$LABEL")"
SRC="$(urldecode "$SRC")"

if [ -z "$IP" ] || [ ! -f "$CONF" ] || [ "$(conf_has_key "$IP" "$CONF")" != "YES" ]; then
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
	SRC=$(awk -F'|' -v k="$IP" '$1==k{print $3; exit}' "$CONF")
fi
if ! is_valid_ip "$SRC" && ! is_valid_domain "$SRC" && ! echo "$SRC" | grep -qE '^\.[A-Za-z0-9.-]+$' && ! echo "$SRC" | grep -qE '^[A-Za-z0-9._()\[\]|^$+*?{}\\-]{1,64}$'; then
	echo '{"ok":false,"error":"источник: IP, домен, суффикс или регэксп"}'
	exit 0
fi

TYPE=$(awk -F'|' -v k="$IP" '$1==k{print $5; exit}' "$CONF")
NEWLINE="${IP}|${LABEL}|${SRC}|${MODE}|${TYPE}"
awk -F'|' -v k="$IP" -v nl="$NEWLINE" '
	$1==k { $0=nl; print; next }
	{ print }
' "$CONF" > "${CONF}.tmp"
mv "${CONF}.tmp" "$CONF"
/usr/bin/warp-targets-apply.sh >/dev/null 2>&1

echo "{\"ok\":true,\"message\":\"${IP} обновлён (${MODE})\"}"