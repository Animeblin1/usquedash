#!/bin/sh
. "$(dirname "$0")/_lib.sh"

echo "Content-Type: application/json"
echo ""
require_password

CONF="/etc/warp-targets.conf"

touch "$CONF"
ADDED=""
SKIPPED=""
	while IFS='|' read -r IP LABEL; do
	[ -z "$IP" ] && continue
	case "$IP" in \#*) continue ;; esac
	if [ "$(conf_has_key "$IP" "$CONF")" = "YES" ]; then
		SKIPPED="${SKIPPED} ${IP}"
	else
		echo "${IP}|${LABEL}|${IP}|warp|suffix" >> "$CONF"
		ADDED="${ADDED} ${IP}"
	fi
done << EOF
.youtube.com|YouTube
.googlevideo.com|Google Video CDN
.ytimg.com|YouTube images
.discord.com|Discord
.discord.gg|Discord invite
.discordapp.com|Discord legacy
.discordapp.net|Discord media
.instagram.com|Instagram
.instagr.am|Instagram short
.cdninstagram.com|Instagram CDN
EOF

/usr/bin/warp-targets-apply.sh >/dev/null 2>&1

[ -n "$ADDED" ] && MSG="добавлено:${ADDED}" || MSG="все уже были в списке"
[ -n "$SKIPPED" ] && MSG="${MSG} (уже были:${SKIPPED})"
echo "{\"ok\":true,\"message\":\"${MSG}\"}"