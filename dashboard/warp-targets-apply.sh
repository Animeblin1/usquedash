#!/bin/sh
#
# Применение маршрутизации WARP/direct/ByeDPI (idempotent, кроном раз в 5 минут,
# при загрузке через /etc/init.d/warp-targets, вручную - сколько угодно раз).
#
# Список целей: /etc/warp-targets.conf, строка: IP|МЕТКА|ИСТОЧНИК|РЕЖИМ
#   РЕЖИМ: warp (по умолчанию, если поле пусто) | direct | byedpi
#   ИСТОЧНИК: домен, если цель добавлена по домену; пусто для IP.
#   Пример: 192.168.1.50|ТВ|192.168.1.50|warp
#
# Режим wholelan: /etc/warp-wholelan (1 = весь LAN в WARP, 0 = выкл).
#   Если файла нет - правило 80 не управляется вовсе (легаси-поведение).
# Параметры LAN: /etc/warp-lan.conf (SUBNET=, IFACE=); авто-детект если нет.
#
# Управляемые приоритеты (ниже = важнее):
#   75     - direct/byedpi цели: from IP lookup main.
#            direct  - плюс RETURN от ByeDPI (мимо WARP и мимо REDIRECT)
#            byedpi  - без RETURN: tcp 443/80 уходит в REDIRECT ByeDPI:1081
#   80     - wholelan: from SUBNET lookup warp (+RETURN от ByeDPI для всей LAN)
#   150-199 - warp цели: from IP lookup warp (+RETURN от ByeDPI)
# Правила 90/100 (ручные) и все остальные - не трогаются.
# Если tun0 не поднят - молча выходит (применится позже по крону).
#
CONF="/etc/warp-targets.conf"
LOG="/var/log/warp-targets.log"
PRIO_MAIN=75
PRIO_WHOL=80
PRIO_MIN=150
PRIO_MAX=199

[ -f /etc/warp-lan.conf ] && . /etc/warp-lan.conf
if [ -z "$SUBNET" ] || [ -z "$IFACE" ]; then
	[ -z "$IFACE" ] && IFACE=$(uci get network.lan.ifname 2>/dev/null)
	[ -z "$IFACE" ] && IFACE=br-lan
	[ -z "$SUBNET" ] && SUBNET=$(ip -o -4 addr show dev "$IFACE" 2>/dev/null | awk '{print $4; exit}')
fi

WHOL=$(cat /etc/warp-wholelan 2>/dev/null)
MANAGE_WHOL=0
[ -n "$WHOL" ] && MANAGE_WHOL=1

if ! ip link show tun0 >/dev/null 2>&1; then
	exit 0
fi

grep -q "^200 warp" /etc/iproute2/rt_tables || echo "200 warp" >> /etc/iproute2/rt_tables

P=$PRIO_MIN
while [ "$P" -le "$PRIO_MAX" ]; do
	ip rule show 2>/dev/null | grep -E "(table|lookup) warp priority ${P}" | awk '{print $3}' | while read -r R; do
		ip rule del from "$R" table warp priority "$P" 2>/dev/null
		iptables -t nat -D PREROUTING -s "$R" -j RETURN 2>/dev/null
	done
	P=$((P + 1))
done

ip rule show 2>/dev/null | grep -E "(table|lookup) main priority ${PRIO_MAIN}" | awk '{print $3}' | while read -r R; do
	ip rule del from "$R" table main priority "$PRIO_MAIN" 2>/dev/null
	iptables -t nat -D PREROUTING -s "$R" -j RETURN 2>/dev/null
done

if [ "$MANAGE_WHOL" = "1" ] && [ -n "$SUBNET" ]; then
	ip rule show 2>/dev/null | grep -E "(table|lookup) warp priority ${PRIO_WHOL}" | awk '{print $3}' | while read -r R; do
		ip rule del from "$R" table warp priority "$PRIO_WHOL" 2>/dev/null
	done
	iptables -t nat -D PREROUTING -s "$SUBNET" -j RETURN 2>/dev/null
fi

if [ ! -f "$CONF" ]; then
	exit 0
fi

P=$PRIO_MIN
while IFS='|' read -r ip label src mode; do
	[ -z "$ip" ] && continue
	case "$ip" in
		\#*) continue ;;
		*) ;;
	esac
	case "$mode" in
		direct|byedpi)
			ip rule add from "$ip" table main priority "$PRIO_MAIN" 2>/dev/null
			[ "$mode" = "direct" ] && iptables -t nat -I PREROUTING 2 -s "$ip" -j RETURN 2>/dev/null
			;;
		*)
			ip rule add from "$ip" table warp priority "$P" 2>/dev/null
			iptables -t nat -I PREROUTING 2 -s "$ip" -j RETURN 2>/dev/null
			P=$((P + 1))
			if [ "$P" -gt "$PRIO_MAX" ]; then
				echo "$(date '+%Y-%m-%d %H:%M:%S') ВНИМАНИЕ: warp-целей больше ${PRIO_MAX}, остальные не влезли" >> "$LOG"
				break
			fi
			;;
	esac
done < "$CONF"

if [ "$MANAGE_WHOL" = "1" ] && [ "$WHOL" = "1" ] && [ -n "$SUBNET" ]; then
	ip rule add from "$SUBNET" table warp priority "$PRIO_WHOL" 2>/dev/null
	iptables -t nat -I PREROUTING 2 -s "$SUBNET" -j RETURN 2>/dev/null
fi

LOG_TAIL=$(tail -200 "$LOG" 2>/dev/null)
echo "$LOG_TAIL" > "$LOG" 2>/dev/null || true