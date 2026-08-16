#!/bin/sh
set -e
#
# ByeDPI на весь LAN: десинхронизация TLS через два сервиса:
#   - byedpi (порт 1080)       - SOCKS5, для ручных тестов: curl -x socks5://127.0.0.1:1080
#   - byedpi-transparent (1081) - прозрачный режим, весь LAN-трафик tcp 443/80
#     заворачивается цепочкой BYEDPI в nat PREROUTING
#
# Стратегия desync (флаги -d/-s/-r/-a и т.д.) описана в README, раздел
# "ByeDPI: стратегии". Чтобы сменить стратегию вручную:
#   1) Правь строку cmd_opts в /etc/config/byedpi (порт 1080) и аргументы
#      запуска в /etc/init.d/byedpi-transparent (порт 1081)
#   2) /etc/init.d/byedpi restart && /etc/init.d/byedpi-transparent restart
#   3) Проверка: curl -x socks5://127.0.0.1:1080 -I https://ya.ru --max-time 10
#      (ожидается HTTP/1.1 302 - туннель живой)
#
echo "=== [1/5] Скачиваем и ставим ByeDPI ==="
cd /tmp
URL=$(wget -qO- https://api.github.com/repos/DPITrickster/ByeDPI-OpenWrt/releases/latest \
	| grep -o 'https://[^"]*mipsel_24kc[^"]*\.ipk' | head -1)
if [ -z "$URL" ]; then
	echo "Не нашёл .ipk под mipsel_24kc в последнем релизе - проверь вручную:"
	echo "https://github.com/DPITrickster/ByeDPI-OpenWrt/releases"
	exit 1
fi
wget -O byedpi.ipk "$URL"
opkg install byedpi.ipk

echo "=== [2/5] Прописываем desync-стратегию для порта 1080 ==="
sed -i "s|option cmd_opts.*|option cmd_opts '-d1 -d3+s -s6+s -d9+s -s12+s -d15+s -s20+s -d25+s -s30+s -d35+s -r1+s -S -a1 -As -d1 -d3+s -s6+s -d9+s -s12+s -d15+s -s20+s -d25+s -s30+s -d35+s -S -a1'|" /etc/config/byedpi

echo "=== [3/5] Автозагрузка основного сервиса (порт 1080) ==="
/etc/init.d/byedpi enable
/etc/init.d/byedpi start

echo "=== [4/5] Второй сервис - transparent-режим на порту 1081 ==="
cat > /etc/init.d/byedpi-transparent << 'INNERSCRIPT'
#!/bin/sh /etc/rc.common
START=99
STOP=10
start() {
	/usr/bin/ciadpi -d1 -d3+s -s6+s -d9+s -s12+s -d15+s -s20+s -d25+s -s30+s -d35+s -r1+s -S -a1 -As -d1 -d3+s -s6+s -d9+s -s12+s -d15+s -s20+s -d25+s -s30+s -d35+s -S -a1 -p 1081 -E -D -w /var/run/ciadpi-transparent.pid
}
stop() {
	[ -f /var/run/ciadpi-transparent.pid ] && kill $(cat /var/run/ciadpi-transparent.pid) 2>/dev/null
}
INNERSCRIPT
chmod +x /etc/init.d/byedpi-transparent
/etc/init.d/byedpi-transparent enable
/etc/init.d/byedpi-transparent start

echo "=== [5/5] Правила iptables - заворот всего LAN-трафика на 1081 ==="
iptables -t nat -N BYEDPI 2>/dev/null || iptables -t nat -F BYEDPI
iptables -t nat -A BYEDPI -d 0.0.0.0/8 -j RETURN
iptables -t nat -A BYEDPI -d 10.0.0.0/8 -j RETURN
iptables -t nat -A BYEDPI -d 127.0.0.0/8 -j RETURN
iptables -t nat -A BYEDPI -d 169.254.0.0/16 -j RETURN
iptables -t nat -A BYEDPI -d 172.16.0.0/12 -j RETURN
iptables -t nat -A BYEDPI -d 192.168.0.0/16 -j RETURN
iptables -t nat -A BYEDPI -d 224.0.0.0/4 -j RETURN
iptables -t nat -A BYEDPI -d 240.0.0.0/4 -j RETURN
iptables -t nat -A BYEDPI -p tcp --dport 443 -j REDIRECT --to-port 1081
iptables -t nat -A BYEDPI -p tcp --dport 80 -j REDIRECT --to-port 1081
iptables -t nat -D PREROUTING -i br-lan -j BYEDPI 2>/dev/null || true
iptables -t nat -A PREROUTING -i br-lan -j BYEDPI

echo "=== Сохраняем правила в /etc/firewall.user ==="
if ! grep -q "iptables -t nat -N BYEDPI" /etc/firewall.user 2>/dev/null; then
	cat >> /etc/firewall.user << 'FWSCRIPT'

iptables -t nat -N BYEDPI 2>/dev/null
iptables -t nat -F BYEDPI
iptables -t nat -A BYEDPI -d 0.0.0.0/8 -j RETURN
iptables -t nat -A BYEDPI -d 10.0.0.0/8 -j RETURN
iptables -t nat -A BYEDPI -d 127.0.0.0/8 -j RETURN
iptables -t nat -A BYEDPI -d 169.254.0.0/16 -j RETURN
iptables -t nat -A BYEDPI -d 172.16.0.0/12 -j RETURN
iptables -t nat -A BYEDPI -d 192.168.0.0/16 -j RETURN
iptables -t nat -A BYEDPI -d 224.0.0.0/4 -j RETURN
iptables -t nat -A BYEDPI -d 240.0.0.0/4 -j RETURN
iptables -t nat -A BYEDPI -p tcp --dport 443 -j REDIRECT --to-port 1081
iptables -t nat -A BYEDPI -p tcp --dport 80 -j REDIRECT --to-port 1081
iptables -t nat -D PREROUTING -i br-lan -j BYEDPI 2>/dev/null
iptables -t nat -A PREROUTING -i br-lan -j BYEDPI
FWSCRIPT
fi

echo ""
echo "=== ГОТОВО ==="
echo "Проверка (должно быть 2 строки - 1080 и 1081):"
netstat -tlnp | grep ciadpi
echo ""
echo "Тест SOCKS5 с самого роутера:"
echo "  curl -x socks5://127.0.0.1:1080 -I https://ya.ru --max-time 10"
echo "(ответ HTTP/1.1 302 - нормально, туннель рабочий)"