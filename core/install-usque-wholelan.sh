#!/bin/sh
set -e
#
# WARP на ВЕСЬ LAN: весь трафик подсети уходит в туннель usque (tun0).
# Отличие от install-usque-core.sh: добавляется policy-правило
# "from <подсеть> lookup warp priority 80" - всё, что не попало под
# более приоритетные правила (150-199, цели из дашборда), идёт в WARP.
#
# Ручная установка (вместо этого скрипта):
#   1) Бинарник:   cp usque-mipsel /usr/bin/usque && chmod +x /usr/bin/usque
#   2) Конфиг:     mkdir -p /etc/usque && cp config.json /etc/usque/config.json
#   3) TUN:        opkg install kmod-tun && insmod tun
#   4) Задать SNI/подсеть/интерфейс ниже и создать /etc/init.d/usque (генератор ниже)
#   5) /etc/init.d/usque enable && /etc/init.d/usque start
#   6) Проверка:   ip route show table warp  (должен быть default dev tun0)
#                  ip rule | grep warp       (80: from <подсеть> lookup warp)
#
# Переменные окружения: WARP_SNI, LAN_SUBNET, LAN_IFACE (см. install-usque-core.sh)
#
SNI="${WARP_SNI:-ya.ru}"
LAN_SUBNET="${LAN_SUBNET:-192.168.1.0/24}"
LAN_IFACE="${LAN_IFACE:-br-lan}"

echo "=== [1/7] Проверяем наличие бинарника usque ==="
if [ ! -f "./usque-mipsel" ] && [ ! -f "/usr/bin/usque" ]; then
	echo "ОШИБКА: usque-mipsel не найден в текущей директории и /usr/bin/usque отсутствует."
	echo "Перенеси бинарник на роутер и повтори."
	exit 1
fi
if [ -f "./usque-mipsel" ]; then
	cp ./usque-mipsel /usr/bin/usque
	chmod +x /usr/bin/usque
fi
echo "usque установлен в /usr/bin/usque"

echo "=== [2/7] Проверяем конфиг ключей ==="
mkdir -p /etc/usque
if [ ! -f /etc/usque/config.json ]; then
	echo "ОШИБКА: /etc/usque/config.json не найден."
	echo "Закинь Clash-конфиг с warp-gen.github.io в дашборд (вкладка 'Clash-конфиг')"
	echo "или запусти sh core/import-clash.sh /путь/к/файлу.yaml, затем повтори."
	exit 1
fi
echo "Конфиг найден: /etc/usque/config.json"

echo "=== [3/7] Модуль ядра TUN ==="
opkg update
opkg install kmod-tun
insmod tun 2>/dev/null || true
mkdir -p /dev/net
[ -c /dev/net/tun ] || mknod /dev/net/tun c 10 200
echo "Проверка: $(ls /dev/net/tun 2>/dev/null || echo 'НЕ СОЗДАН - см. Troubleshooting в README')"

echo "=== [4/7] Проверяем место на /overlay ==="
df -h /overlay 2>/dev/null || true

echo "=== [5/7] Создаём init-скрипт /etc/init.d/usque ==="
cat > /etc/init.d/usque << SCRIPT
#!/bin/sh /etc/rc.common
START=97
STOP=12

LAN_SUBNET="${LAN_SUBNET}"
LAN_IFACE="${LAN_IFACE}"
SNI="${SNI}"
PRIORITY=80

start() {
	insmod tun 2>/dev/null
	mkdir -p /dev/net
	[ -c /dev/net/tun ] || mknod /dev/net/tun c 10 200

	/usr/bin/usque nativetun -c /etc/usque/config.json -s \${SNI} > /var/log/usque-tun.log 2>&1 &
	echo \$! > /var/run/usque.pid

	for i in \$(seq 1 15); do
		[ -e /sys/class/net/tun0 ] && break
		sleep 1
	done

	grep -q "^200 warp" /etc/iproute2/rt_tables || echo "200 warp" >> /etc/iproute2/rt_tables
	ip route add default dev tun0 table warp 2>/dev/null
	ip route add \${LAN_SUBNET} dev \${LAN_IFACE} table warp 2>/dev/null
	ip rule del from \${LAN_SUBNET} table warp priority \${PRIORITY} 2>/dev/null
	ip rule add from \${LAN_SUBNET} table warp priority \${PRIORITY}

	iptables -t nat -C PREROUTING -s \${LAN_SUBNET} -j RETURN 2>/dev/null || iptables -t nat -I PREROUTING 2 -s \${LAN_SUBNET} -j RETURN

	iptables -C FORWARD -i \${LAN_IFACE} -o tun0 -j ACCEPT 2>/dev/null || iptables -I FORWARD 1 -i \${LAN_IFACE} -o tun0 -j ACCEPT
	iptables -C FORWARD -i tun0 -o \${LAN_IFACE} -j ACCEPT 2>/dev/null || iptables -I FORWARD 2 -i tun0 -o \${LAN_IFACE} -j ACCEPT
	iptables -t nat -C POSTROUTING -o tun0 -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE

	iptables -t mangle -C FORWARD -o tun0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || iptables -t mangle -A FORWARD -o tun0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

	/etc/init.d/dnsmasq restart 2>/dev/null || true
}

stop() {
	ip rule del from \${LAN_SUBNET} table warp priority \${PRIORITY} 2>/dev/null
	iptables -t nat -D PREROUTING -s \${LAN_SUBNET} -j RETURN 2>/dev/null
	ip route flush table warp 2>/dev/null
	[ -f /var/run/usque.pid ] && kill \$(cat /var/run/usque.pid) 2>/dev/null
	ip link delete tun0 2>/dev/null
}
SCRIPT
chmod +x /etc/init.d/usque

echo "=== [6/7] Включаем автозагрузку и стартуем ==="
/etc/init.d/usque enable
/etc/init.d/usque start
sleep 3

echo "=== [7/7] Проверка ==="
echo "--- процесс ---"
ps w | grep usqu[e]
echo "--- интерфейс tun0 ---"
ip link show tun0 2>/dev/null || echo "tun0 не поднялся - смотри /var/log/usque-tun.log"
echo "--- policy routing ---"
ip rule show | grep "${LAN_SUBNET}"
echo "--- исключение из ByeDPI ---"
iptables -t nat -L PREROUTING -n --line-numbers | grep "${LAN_SUBNET}" || echo "ВНИМАНИЕ: исключение не найдено, см. Troubleshooting в README"
echo ""
echo "=== ГОТОВО ==="
echo "Весь LAN (${LAN_SUBNET}) теперь идёт через WARP-туннель (tun0)."
echo "Старые открытые TCP-сессии продолжат идти по старому пути до закрытия -"
echo "перезапусти приложения/вкладки на клиентах, если что-то не ожило сразу."
echo ""
echo "Следи за стабильностью: free -m / ps w | grep usqu[e] / ip -s link show tun0"
echo "Откат: /etc/init.d/usque stop && /etc/init.d/usque disable"