#!/bin/sh

LOG="/var/log/usque-watchdog.log"
LOCK="/var/run/usque-watchdog.lock"

if [ -f "$LOCK" ]; then
	LOCK_AGE=$(( $(date +%s) - $(date -r "$LOCK" +%s 2>/dev/null || echo 0) ))
	if [ "$LOCK_AGE" -lt 120 ]; then
		exit 0
	fi
	echo "$(date '+%Y-%m-%d %H:%M:%S') lock старше 120с, вероятно завис прошлый запуск - продолжаем" >> "$LOG"
fi
touch "$LOCK"

BAD=0
REASON=""

if ! ps w | grep -q usqu[e]; then
	BAD=1
	REASON="процесс usque не найден"
elif ! ip link show tun0 >/dev/null 2>&1; then
	BAD=1
	REASON="tun0 отсутствует"
elif ! ip route show table warp | grep -q "default dev tun0"; then
	BAD=1
	REASON="нет default-маршрута через tun0 в таблице warp"
fi

if [ "$BAD" = "1" ]; then
	UP=$(uptime | sed 's/^[^,]*up *//; s/,.*//')
	echo "$(date '+%Y-%m-%d %H:%M:%S') ПАДЕНИЕ: ${REASON} (аптайм: ${UP}) - перезапускаю usque" >> "$LOG"
	/etc/init.d/usque restart >/dev/null 2>&1
	sleep 5
	if ip link show tun0 >/dev/null 2>&1 && ip route show table warp | grep -q "default dev tun0"; then
		echo "$(date '+%Y-%m-%d %H:%M:%S') рестарт успешен, tun0 поднялся" >> "$LOG"
	else
		echo "$(date '+%Y-%m-%d %H:%M:%S') ВНИМАНИЕ: рестарт не помог, tun0 всё ещё не поднялся - нужна ручная проверка" >> "$LOG"
	fi
fi

rm -f "$LOCK"