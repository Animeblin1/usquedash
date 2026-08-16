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

RESTORE="/tmp/restore-$$"
rm -rf "$RESTORE"
mkdir -p "$RESTORE"

if ! tar -xzf "$FILE" -C "$RESTORE" 2>/dev/null; then
	rm -rf "$RESTORE"
	echo '{"ok":false,"error":"архив повреждён или не tar.gz"}'
	exit 0
fi

[ -f "$RESTORE/etc/usque/config.json" ] && cp "$RESTORE/etc/usque/config.json" /etc/usque/config.json
[ -f "$RESTORE/etc/warp-targets.conf" ] && cp "$RESTORE/etc/warp-targets.conf" /etc/warp-targets.conf
[ -f "$RESTORE/etc/init.d/usque" ] && cp "$RESTORE/etc/init.d/usque" /etc/init.d/usque && chmod +x /etc/init.d/usque
[ -f "$RESTORE/etc/init.d/warp-targets" ] && cp "$RESTORE/etc/init.d/warp-targets" /etc/init.d/warp-targets && chmod +x /etc/init.d/warp-targets
[ -f "$RESTORE/etc/init.d/byedpi" ] && cp "$RESTORE/etc/init.d/byedpi" /etc/init.d/byedpi && chmod +x /etc/init.d/byedpi
[ -f "$RESTORE/etc/init.d/byedpi-transparent" ] && cp "$RESTORE/etc/init.d/byedpi-transparent" /etc/init.d/byedpi-transparent && chmod +x /etc/init.d/byedpi-transparent
[ -f "$RESTORE/usr/bin/warp-targets-apply.sh" ] && cp "$RESTORE/usr/bin/warp-targets-apply.sh" /usr/bin/warp-targets-apply.sh && chmod +x /usr/bin/warp-targets-apply.sh
[ -f "$RESTORE/usr/bin/usque-watchdog.sh" ] && cp "$RESTORE/usr/bin/usque-watchdog.sh" /usr/bin/usque-watchdog.sh && chmod +x /usr/bin/usque-watchdog.sh
[ -f "$RESTORE/usr/bin/import-clash.sh" ] && cp "$RESTORE/usr/bin/import-clash.sh" /usr/bin/import-clash.sh && chmod +x /usr/bin/import-clash.sh

for f in "$RESTORE"/etc/crontabs/crontab-*; do
	[ -f "$f" ] || continue
	NAME2=$(basename "$f" | sed 's/^crontab-//')
	cp "$f" "/etc/crontabs/${NAME2}"
done

if [ -f "$RESTORE/iptables.rules" ]; then
	iptables-restore < "$RESTORE/iptables.rules" 2>/dev/null || true
fi

rm -rf "$RESTORE"

/etc/init.d/warp-targets restart >/dev/null 2>&1 || true
/etc/init.d/cron restart >/dev/null 2>&1 || true

echo "{\"ok\":true,\"message\":\"конфиги восстановлены из ${NAME}\"}"