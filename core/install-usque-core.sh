#!/bin/sh
set -e

SNI="${WARP_SNI:-ya.ru}"
LAN_SUBNET="${LAN_SUBNET:-192.168.1.0/24}"
LAN_IFACE="${LAN_IFACE:-br-lan}"

echo "=== [1/6] Проверяем наличие бинарника usque ==="
if [ ! -f "./usque-mipsel" ] && [ ! -f "/usr/bin/usque" ]; then
	echo "ОШИБКА: usque-mipsel не найден рядом со скриптом и /usr/bin/usque отсутствует."
	exit 1
fi
if [ -f "./usque-mipsel" ]; then
	cp ./usque-mipsel /usr/bin/usque
	chmod +x /usr/bin/usque
fi
echo "usque установлен в /usr/bin/usque"

echo "=== [2/6] Проверяем конфиг ключей ==="
mkdir -p /etc/usque
if [ ! -f /etc/usque/config.json ]; then
	echo "ОШИБКА: /etc/usque/config.json не найден."
	echo "Закинь Clash-конфиг с warp-gen.github.io в дашборд (вкладка 'Clash-конфиг')"
	echo "или запусти sh core/import-clash.sh /путь/к/файлу.yaml, затем повтори."
	exit 1
fi
echo "Конфиг найден: /etc/usque/config.json"

echo "=== [3/6] Модуль ядра TUN ==="
opkg update
opkg install kmod-tun
insmod tun 2>/dev/null || true
mkdir -p /dev/net
[ -c /dev/net/tun ] || mknod /dev/net/tun c 10 200

echo "=== [4/6] Создаём init-скрипт /etc/init.d/usque ==="
cat > /etc/init.d/usque << SCRIPT2
#!/bin/sh /etc/rc.common
START=97
STOP=12

LAN_SUBNET="${LAN_SUBNET}"
LAN_IFACE="${LAN_IFACE}"
SNI="${SNI}"

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

	iptables -C FORWARD -i \${LAN_IFACE} -o tun0 -j ACCEPT 2>/dev/null || iptables -I FORWARD 1 -i \${LAN_IFACE} -o tun0 -j ACCEPT
	iptables -C FORWARD -i tun0 -o \${LAN_IFACE} -j ACCEPT 2>/dev/null || iptables -I FORWARD 2 -i tun0 -o \${LAN_IFACE} -j ACCEPT
	iptables -t nat -C POSTROUTING -o tun0 -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE
	iptables -t mangle -C FORWARD -o tun0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || iptables -t mangle -A FORWARD -o tun0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

	/etc/init.d/dnsmasq restart 2>/dev/null || true
}

stop() {
	ip route flush table warp 2>/dev/null
	[ -f /var/run/usque.pid ] && kill \$(cat /var/run/usque.pid) 2>/dev/null
	ip link delete tun0 2>/dev/null
}
SCRIPT2
chmod +x /etc/init.d/usque

echo "=== [5/6] Включаем автозагрузку и стартуем ==="
/etc/init.d/usque enable
/etc/init.d/usque start
sleep 3

echo "=== [6/6] Проверка ==="
ps w | grep usqu[e]
ip link show tun0 2>/dev/null || echo "tun0 не поднялся - смотри /var/log/usque-tun.log"
ip route show table warp

echo ""
echo "=== ГОТОВО (ядро) ==="
echo "tun0 и таблица warp готовы, но пусты - добавь цели (IP/домены)"
echo "во вкладке 'WARP-цели' дашборда, либо в /etc/warp-targets.conf"
echo "с последующим sh /usr/bin/warp-targets-apply.sh"