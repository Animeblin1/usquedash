#!/bin/sh
. "$(dirname "$0")/_lib.sh"

PASSWORD=""
NAME=""
for kv in $(echo "$QUERY_STRING" | tr '&' ' '); do
	key=${kv%%=*}
	val=${kv#*=}
	case "$key" in
		password) PASSWORD="$val" ;;
		name) NAME="$val" ;;
	esac
done
NAME="$(urldecode "$NAME")"

if ! check_password "$PASSWORD"; then
	echo "Content-Type: text/plain"
	echo ""
	echo "неверный пароль"
	exit 0
fi

if ! is_safe_filename "$NAME" || [ -z "$NAME" ]; then
	echo "Content-Type: text/plain"
	echo ""
	echo "некорректное имя файла"
	exit 0
fi

FILE="/etc/dashboard-backups/${NAME}"
if [ ! -f "$FILE" ]; then
	echo "Content-Type: text/plain"
	echo ""
	echo "файл не найден"
	exit 0
fi

echo "Content-Type: application/gzip"
echo "Content-Disposition: attachment; filename=\"${NAME}\""
echo ""
cat "$FILE"