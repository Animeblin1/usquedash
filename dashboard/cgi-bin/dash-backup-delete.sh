#!/bin/sh
. "$(dirname "$0")/_lib.sh"

echo "Content-Type: application/json"
echo ""
require_password

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

FILE="/etc/dashboard-backups/${NAME}"
if [ ! -f "$FILE" ]; then
	echo '{"ok":false,"error":"файл не найден"}'
	exit 0
fi

rm -f "$FILE"
echo "{\"ok\":true,\"message\":\"бэкап ${NAME} удалён\"}"