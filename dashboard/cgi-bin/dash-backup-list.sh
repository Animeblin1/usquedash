#!/bin/sh
. "$(dirname "$0")/_lib.sh"

echo "Content-Type: application/json"
echo ""
require_password

BACKUP_DIR="/etc/dashboard-backups"
LIST=""
FIRST=1

if [ -d "$BACKUP_DIR" ]; then
	for f in "$BACKUP_DIR"/backup-*.tar.gz; do
		[ -f "$f" ] || continue
		NAME=$(basename "$f")
		SIZE=$(du -h "$f" | awk '{print $1}')
		DATE=$(date -r "$f" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)
		ITEM="{\"name\":\"${NAME}\",\"size\":\"${SIZE}\",\"date\":\"${DATE}\"}"
		if [ "$FIRST" = "1" ]; then LIST="$ITEM"; FIRST=0; else LIST="${LIST},${ITEM}"; fi
	done
fi

echo "{\"backups\":[ ${LIST} ]}"