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
#   85     - домен-суффиксы/регэкспы в режиме warp: fwmark 0x8 lookup warp
#            (ipset warp-ips наполняет dnsmasq по ipset=/домен/warp-ips)
#            direct/byedpi-суффиксы: mark 0x9 (идут в main через правило 70)
#   150-199 - warp цели: from IP lookup warp (+RETURN от ByeDPI)
# Правила 90/100 (ручные) и все остальные - не трогаются.
# Если tun0 не поднят - молча выходит (применится позже по крону).
#
# Формат conf: IP|МЕТКА|ИСТОЧНИК|РЕЖИМ[|ТИП]
#   ТИП (пусто = по ИСТОЧНИКУ): ip | domain | suffix | regex
#   suffix: IP-поле = ".youtube.com" (ведущая точка)
#   regex:  IP-поле = "^(.*\.)?discord\.gg$" (без обрамляющих слэшей)
#
CONF="/etc/warp-targets.conf"
LOG="/var/log/warp-targets.log"
PRIO_MAIN=75
PRIO_WHOL=80
PRIO_MARK=85
PRIO_MIN=150
PRIO_MAX=199
DNS_CONF="/etc/dnsmasq.d/usque-ipset.conf"
IPSET_WARP="warp-ips"
IPSET_BYPASS="bypass-ips"

[ -f /etc/warp-lan.conf ] && . /etc/warp-lan.conf
if [ -z "$SUBNET" ] || [ -z "$IFACE" ]; then
	PRIV=$(ip -o -4 addr show 2>/dev/null | awk '$3=="inet" && $4 ~ /^(192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[01])\.)/ {print; exit}')
	[ -z "$IFACE" ] && IFACE=$(echo "$PRIV" | awk '{print $2}')
	[ -z "$SUBNET" ] && SUBNET=$(echo "$PRIV" | awk '{print $4}')
	[ -z "$IFACE" ] && IFACE=br-lan
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
	ip rule show 2>/dev/null | grep -E "^${P}:|priority ${P}" | awk '{print $3}' | while read -r R; do
		ip rule del from "$R" table warp priority "$P" 2>/dev/null
		iptables -t nat -D PREROUTING -s "$R" -j RETURN 2>/dev/null
	done
	P=$((P + 1))
done

ip rule show 2>/dev/null | grep -E "^${PRIO_MAIN}:|priority ${PRIO_MAIN}" | awk '{print $3}' | while read -r R; do
	ip rule del from "$R" table main priority "$PRIO_MAIN" 2>/dev/null
	iptables -t nat -D PREROUTING -s "$R" -j RETURN 2>/dev/null
done

if [ "$MANAGE_WHOL" = "1" ] && [ -n "$SUBNET" ]; then
	ip rule show 2>/dev/null | grep -E "^${PRIO_WHOL}:|priority ${PRIO_WHOL}" | awk '{print $3}' | while read -r R; do
		ip rule del from "$R" table warp priority "$PRIO_WHOL" 2>/dev/null
	done
	iptables -t nat -D PREROUTING -s "$SUBNET" -j RETURN 2>/dev/null
fi

# --- delete-фаза домен-суффиксов/регэкспов (ipset + fwmark + dnsmasq) ---
ip rule del fwmark 0x8 table warp priority "$PRIO_MARK" 2>/dev/null
iptables -t mangle -D PREROUTING -i "$IFACE" -m set --match-set "$IPSET_WARP" dst -j MARK --set-xmark 0x8/0xffffffff 2>/dev/null
iptables -t mangle -D PREROUTING -i "$IFACE" -m set --match-set "$IPSET_BYPASS" dst -j MARK --set-xmark 0x9/0xffffffff 2>/dev/null
rm -f "$DNS_CONF"

if [ ! -f "$CONF" ]; then
	exit 0
fi

P=$PRIO_MIN
while IFS='|' read -r ip label src mode type; do
	[ -z "$ip" ] && continue
	case "$ip" in
		\#*) continue ;;
		*) ;;
	esac
	case "$type" in
		suffix|regex)
			case "$mode" in
				warp)
					echo "ipset=/${ip}/${IPSET_WARP}" >> "$DNS_CONF"
					USE_WARP=1
					;;
				direct|byedpi)
					echo "ipset=/${ip}/${IPSET_BYPASS}" >> "$DNS_CONF"
					USE_BYPASS=1
					;;
			esac
			continue
			;;
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

# --- add-фаза домен-суффиксов/регэкспов ---
if [ -f "$DNS_CONF" ]; then
	mkdir -p /etc/dnsmasq.d
	grep -q "^conf-dir=/etc/dnsmasq.d/$" /etc/dnsmasq.conf || echo "conf-dir=/etc/dnsmasq.d/" >> /etc/dnsmasq.conf
	if [ "$USE_WARP" = "1" ]; then
		ipset -exist create "$IPSET_WARP" hash:ip
		iptables -t mangle -A PREROUTING -i "$IFACE" -m set --match-set "$IPSET_WARP" dst -j MARK --set-xmark 0x8/0xffffffff
		ip rule add fwmark 0x8 table warp priority "$PRIO_MARK" 2>/dev/null
	fi
	if [ "$USE_BYPASS" = "1" ]; then
		ipset -exist create "$IPSET_BYPASS" hash:ip
		iptables -t mangle -A PREROUTING -i "$IFACE" -m set --match-set "$IPSET_BYPASS" dst -j MARK --set-xmark 0x9/0xffffffff
	fi
	if ! cmp -s "$DNS_CONF" /tmp/usque-ipset.conf.old 2>/dev/null; then
		cp "$DNS_CONF" /tmp/usque-ipset.conf.old
		/etc/init.d/dnsmasq restart >/dev/null 2>&1 || kill -HUP "$(pidof dnsmasq)" 2>/dev/null
	fi
fi

if [ "$MANAGE_WHOL" = "1" ] && [ "$WHOL" = "1" ] && [ -n "$SUBNET" ]; then
	ip rule add from "$SUBNET" table warp priority "$PRIO_WHOL" 2>/dev/null
	iptables -t nat -I PREROUTING 2 -s "$SUBNET" -j RETURN 2>/dev/null
fi

LOG_TAIL=$(tail -200 "$LOG" 2>/dev/null)
echo "$LOG_TAIL" > "$LOG" 2>/dev/null || true