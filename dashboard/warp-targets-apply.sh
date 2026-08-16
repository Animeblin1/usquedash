#!/bin/sh
#
# Применение списка WARP-целей (idempotent - можно гонять сколько угодно раз).
# Список в /etc/warp-targets.conf, формат строки: IP|МЕТКА|ИСТОЧНИК
# (ИСТОЧНИК = домен, если цель добавлена по домену; пусто для IP).
# Пример: 192.168.1.50|ТВ|192.168.1.50
#
# Ручное использование:
#   echo "192.168.1.50|ТВ|192.168.1.50" >> /etc/warp-targets.conf
#   sh /usr/bin/warp-targets-apply.sh
#
# Логика: удаляет ВСЕ правила в диапазоне приоритетов PRIO_MIN..PRIO_MAX
# (150-199) и пересоздаёт их из конфига. Правила вне диапазона (например
# 80 - wholelan, 90/100 - ручные) не трогает. Вызывается по крону раз в 5
# минут и при загрузке роутера (/etc/init.d/warp-targets).
#
# ВАЖНО про порядок маршрутизации (см. README): приоритет ниже = важнее.
# 80  - весь LAN в WARP (режим wholelan)
# 150-199 - цели из дашборда (перекрывают wholelan для этих адресов)
# Если tun0 не поднят - скрипт молча выходит (цели применятся позже).
#
CONF="/etc/warp-targets.conf"
LOG="/var/log/warp-targets.log"
PRIO_MIN=150
PRIO_MAX=199

if ! ip link show tun0 >/dev/null 2>&1; then
	exit 0
fi

grep -q "^200 warp" /etc/iproute2/rt_tables || echo "200 warp" >> /etc/iproute2/rt_tables

P=$PRIO_MIN
while [ "$P" -le "$PRIO_MAX" ]; do
	RULE=$(ip rule show 2>/dev/null | grep "table warp priority ${P}" | awk '{print $3}')
	if [ -n "$RULE" ]; then
		ip rule del from "$RULE" table warp priority "$P" 2>/dev/null
		iptables -t nat -D PREROUTING -s "$RULE" -j RETURN 2>/dev/null
	fi
	P=$((P + 1))
done

if [ ! -f "$CONF" ]; then
	exit 0
fi

P=$PRIO_MIN
while IFS='|' read -r ip label src; do
	[ -z "$ip" ] && continue
	case "$ip" in
		\#*) continue ;;
		*) ;;
	esac
	ip rule add from "$ip" table warp priority "$P" 2>/dev/null
	iptables -t nat -I PREROUTING 2 -s "$ip" -j RETURN 2>/dev/null
	P=$((P + 1))
	if [ "$P" -gt "$PRIO_MAX" ]; then
		echo "$(date '+%Y-%m-%d %H:%M:%S') ВНИМАНИЕ: целей больше ${PRIO_MAX}, остальные не влезли" >> "$LOG"
		break
	fi
done < "$CONF"

LOG_TAIL=$(tail -200 "$LOG" 2>/dev/null)
echo "$LOG_TAIL" > "$LOG" 2>/dev/null || true