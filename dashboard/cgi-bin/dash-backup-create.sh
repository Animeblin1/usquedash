#!/bin/sh
. "$(dirname "$0")/_lib.sh"

echo "Content-Type: application/json"
echo ""
require_password

TS=$(date +%Y%m%d-%H%M%S)
STAGE="/tmp/backup-stage-${TS}"
BACKUP_DIR="/etc/dashboard-backups"

rm -rf "$STAGE"
mkdir -p "$STAGE"

mkdir -p "$STAGE/etc/usque" "$STAGE/etc/init.d" "$STAGE/usr/bin" "$STAGE/etc/crontabs"
[ -f /etc/usque/config.json ] && cp /etc/usque/config.json "$STAGE/etc/usque/"
[ -f /etc/init.d/usque ] && cp /etc/init.d/usque "$STAGE/etc/init.d/"
[ -f /etc/init.d/warp-targets ] && cp /etc/init.d/warp-targets "$STAGE/etc/init.d/"
[ -f /etc/init.d/byedpi ] && cp /etc/init.d/byedpi "$STAGE/etc/init.d/"
[ -f /etc/init.d/byedpi-transparent ] && cp /etc/init.d/byedpi-transparent "$STAGE/etc/init.d/"
[ -f /etc/warp-targets.conf ] && cp /etc/warp-targets.conf "$STAGE/etc/"
[ -f /usr/bin/warp-targets-apply.sh ] && cp /usr/bin/warp-targets-apply.sh "$STAGE/usr/bin/"
[ -f /usr/bin/usque-watchdog.sh ] && cp /usr/bin/usque-watchdog.sh "$STAGE/usr/bin/"
[ -f /usr/bin/import-clash.sh ] && cp /usr/bin/import-clash.sh "$STAGE/usr/bin/"
for f in /etc/crontabs/*; do
	[ -f "$f" ] && cp "$f" "$STAGE/etc/crontabs/crontab-$(basename "$f")"
done
iptables-save > "$STAGE/iptables.rules" 2>/dev/null
ip rule show > "$STAGE/ip-rules.txt" 2>/dev/null
ip route show table warp > "$STAGE/route-warp.txt" 2>/dev/null

mkdir -p "$BACKUP_DIR"
BACKUP_FILE="${BACKUP_DIR}/backup-${TS}.tar.gz"
tar -czf "$BACKUP_FILE" -C "$STAGE" . 2>/dev/null
rm -rf "$STAGE"

if [ -f "$BACKUP_FILE" ]; then
	NAME=$(basename "$BACKUP_FILE")
	SIZE=$(du -h "$BACKUP_FILE" | awk '{print $1}')
	echo "{\"ok\":true,\"message\":\"бэкап создан\",\"name\":\"${NAME}\",\"size\":\"${SIZE}\"}"
else
	echo '{"ok":false,"error":"не удалось создать архив"}'
fi