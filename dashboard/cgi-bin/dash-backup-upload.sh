#!/bin/sh
. "$(dirname "$0")/_lib.sh"

echo "Content-Type: application/json"
echo ""
require_password

if [ "$REQUEST_METHOD" != "POST" ]; then
	echo '{"ok":false,"error":"нужен POST-запрос с телом tar.gz"}'
	exit 0
fi

NAME=""
for kv in $(echo "$QUERY_STRING" | tr '&' ' '); do
	key=${kv%%=*}
	val=${kv#*=}
	[ "$key" = "name" ] && NAME="$val"
done
if ! is_safe_filename "$NAME" || [ -z "$NAME" ]; then
	echo '{"ok":false,"error":"некорректное имя файла"}'
	exit 0
fi
NAME=$(echo "$NAME" | cut -c1-80)
case "$NAME" in
	*.tar.gz) ;;
	*) NAME="${NAME}.tar.gz" ;;
esac

if [ -n "$CONTENT_LENGTH" ] && [ "$CONTENT_LENGTH" -gt 0 ] 2>/dev/null; then
	dd bs=1024 count=$((CONTENT_LENGTH / 1024 + 1)) 2>/dev/null > "/etc/dashboard-backups/${NAME}"
fi

SIZE=$(wc -c < "/etc/dashboard-backups/${NAME}" 2>/dev/null)
if [ -z "$SIZE" ] || [ "$SIZE" -eq 0 ] 2>/dev/null; then
	rm -f "/etc/dashboard-backups/${NAME}"
	echo '{"ok":false,"error":"пустое тело запроса - файл не принят"}'
	exit 0
fi

if ! tar -tzf "/etc/dashboard-backups/${NAME}" >/dev/null 2>&1; then
	rm -f "/etc/dashboard-backups/${NAME}"
	echo '{"ok":false,"error":"файл не является корректным tar.gz - отклонён"}'
	exit 0
fi

echo "{\"ok\":true,\"message\":\"бэкап ${NAME} загружен (${SIZE} байт)\"}"