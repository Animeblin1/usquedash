#!/bin/sh
. "$(dirname "$0")/_lib.sh"

echo "Content-Type: application/json"
echo ""
require_password

STR=""
for kv in $(echo "$QUERY_STRING" | tr '&' ' '); do
	key=${kv%%=*}
	val=${kv#*=}
	[ "$key" = "strategy" ] && STR="$val"
done

case "$STR" in
	a|b|c) ;;
	*) echo '{"ok":false,"error":"strategy: a, b или c"}'; exit 0 ;;
esac

FLAGS_A='-d1 -d3+s -s6+s -d9+s -s12+s -d15+s -s20+s -d25+s -s30+s -d35+s -r1+s -S -a1'
FLAGS_B='-d2 -d4+s -s6+s -d9+s -d12+s -d15+s -s20+s -d25+s -d30+s -d35+s -r2+s -S -a1'
FLAGS_C='-d1 -d3+s -s6+s -d9+s -r1+s -S -a1'

case "$STR" in
	a) FLAGS=$FLAGS_A ;;
	b) FLAGS=$FLAGS_B ;;
	c) FLAGS=$FLAGS_C ;;
esac

if [ ! -x /etc/init.d/byedpi ] && [ ! -x /etc/init.d/byedpi-transparent ]; then
	echo '{"ok":false,"error":"ByeDPI не установлен - поставь режим full/byedpi"}'
	exit 0
fi

if [ -f /etc/config/byedpi ]; then
	sed -i "s/option cmd_opts .*/option cmd_opts '${FLAGS}'/" /etc/config/byedpi 2>/dev/null
fi
if [ -f /etc/init.d/byedpi-transparent ]; then
	sed -i "s#/usr/bin/ciadpi .*#/usr/bin/ciadpi ${FLAGS} -p 1081 -E -D -w /var/run/ciadpi-transparent.pid#" /etc/init.d/byedpi-transparent 2>/dev/null
fi

/etc/init.d/byedpi-transparent restart 2>/dev/null || true
/etc/init.d/byedpi restart 2>/dev/null || true

echo "{\"ok\":true,\"message\":\"Стратегия ${STR} применена: ${FLAGS}\"}"