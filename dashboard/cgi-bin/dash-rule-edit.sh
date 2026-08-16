#!/bin/sh
. "$(dirname "$0")/_lib.sh"

echo "Content-Type: application/json"
echo ""
require_password

PRIO=""
NPRIO=""
FROM=""
LOOKUP=""
for kv in $(echo "$QUERY_STRING" | tr '&' ' '); do
	key=${kv%%=*}
	val=${kv#*=}
	case "$key" in
		prio) PRIO="$val" ;;
		nprio) NPRIO="$val" ;;
		from) FROM="$val" ;;
		lookup) LOOKUP="$val" ;;
	esac
done
PRIO="$(urldecode "$PRIO")"
NPRIO="$(urldecode "$NPRIO")"
FROM="$(urldecode "$FROM")"
LOOKUP="$(urldecode "$LOOKUP")"

echo "$PRIO" | grep -qE '^[0-9]{1,5}$' || {
	echo '{"ok":false,"error":"некорректный приоритет"}'
	exit 0
}

[ "$PRIO" -gt 70 ] 2>/dev/null || {
	echo '{"ok":false,"error":"системные правила (70 и ниже) не редактируются"}'
	exit 0
}
[ "$PRIO" -ne 80 ] 2>/dev/null || {
	echo '{"ok":false,"error":"правило 80 — WholeLAN, управляется кнопкой"}'
	exit 0
}

[ -z "$NPRIO" ] && NPRIO="$PRIO"
echo "$NPRIO" | grep -qE '^[0-9]{1,5}$' || {
	echo '{"ok":false,"error":"некорректный новый приоритет"}'
	exit 0
}
[ "$NPRIO" -gt 70 ] && [ "$NPRIO" -ne 80 ] && [ "$NPRIO" -le 32767 ] 2>/dev/null || {
	echo '{"ok":false,"error":"новый приоритет: 71-32767 (70 и 80 заняты системой)"}'
	exit 0
}

case "$FROM" in
	all|0.0.0.0/0) FROM="all" ;;
	*)
		echo "$FROM" | grep -qE '^[0-9]{1,3}(\.[0-9]{1,3}){3}(/[0-9]{1,2})?$' || {
			echo '{"ok":false,"error":"источник: all или IP (192.168.1.50) или IP/маска"}'
			exit 0
		}
		;;
esac

case "$LOOKUP" in
	warp|main) ;;
	*) echo '{"ok":false,"error":"таблица: warp или main"}'; exit 0 ;;
esac

RULE=$(ip rule show 2>/dev/null | grep -E "^${PRIO}:|priority ${PRIO}" | head -1)
[ -n "$RULE" ] || {
	echo '{"ok":false,"error":"правило не найдено"}'
	exit 0
}

if [ "$NPRIO" != "$PRIO" ]; then
	CONFLICT=$(ip rule show 2>/dev/null | grep -E "^${NPRIO}:|priority ${NPRIO}")
	[ -z "$CONFLICT" ] || {
		echo "{\"ok\":false,\"error\":\"приоритет ${NPRIO} уже занят\"}"
		exit 0
	}
fi

ip rule del priority "$PRIO" 2>/dev/null
if [ "$FROM" = "all" ]; then
	ip rule add priority "$NPRIO" from all lookup "$LOOKUP" 2>/dev/null
else
	ip rule add priority "$NPRIO" from "$FROM" lookup "$LOOKUP" 2>/dev/null
fi

echo "{\"ok\":true,\"message\":\"правило ${PRIO} изменено: приоритет ${NPRIO}, from ${FROM}, таблица ${LOOKUP}\"}"