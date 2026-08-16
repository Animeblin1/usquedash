#!/bin/sh
. "$(dirname "$0")/_lib.sh"

echo "Content-Type: application/json"
echo ""
require_password

if [ "$REQUEST_METHOD" != "POST" ]; then
	echo '{"ok":false,"error":"нужен POST-запрос с телом yaml"}'
	exit 0
fi

[ -x /usr/bin/import-clash.sh ] || {
	echo '{"ok":false,"error":"import-clash.sh не установлен на роутере"}'
	exit 0
}

if [ -n "$CONTENT_LENGTH" ] && [ "$CONTENT_LENGTH" -gt 0 ] 2>/dev/null; then
	dd bs=1024 count=$((CONTENT_LENGTH / 1024 + 1)) 2>/dev/null > /tmp/clash-import.yaml
fi

if [ ! -s /tmp/clash-import.yaml ]; then
	echo '{"ok":false,"error":"пустое тело запроса - вставь содержимое yaml-файла"}'
	exit 0
fi

if /usr/bin/import-clash.sh /tmp/clash-import.yaml > /tmp/clash-import.log 2>&1; then
	MSG=$(tail -3 /tmp/clash-import.log | tr '\n' ' ' | json_escape)
	echo "{\"ok\":true,\"message\":\"${MSG}\"}"
else
	MSG=$(tail -5 /tmp/clash-import.log | tr '\n' ' ' | json_escape)
	echo "{\"ok\":false,\"error\":\"${MSG}\"}"
fi