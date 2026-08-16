#!/bin/sh
set -e
#
# Конвертер Clash-конфига WARP (warp-gen.github.io, раздел Clash, тип Masque)
# в /etc/usque/config.json для usque.
#
# Ручное использование:
#   sh import-clash.sh /путь/к/ClashWARP_93.yaml
#
# Что извлекается из yaml:
#   private-key -> private_key;  public-key -> endpoint_pub_key (заворачивается в PEM);
#   ip -> ipv4;  ipv6 -> ipv6;  server -> endpoint_v4;  sni -> SNI в /etc/init.d/usque
# Если в yaml нет server/ip/ipv6 - подставляются значения по умолчанию ниже.
#
FILE="${1:-}"
[ -f "$FILE" ] || { echo "ОШИБКА: файл не найден: ${FILE}"; exit 1; }

PRIV=$(sed -n 's/^[[:space:]]*private-key:[[:space:]]*//p' "$FILE" | head -1)
PUB=$(sed -n 's/^[[:space:]]*public-key:[[:space:]]*//p' "$FILE" | head -1)
IP4=$(sed -n 's/^[[:space:]]*ip:[[:space:]]*//p' "$FILE" | head -1)
IP6=$(sed -n 's/^[[:space:]]*ipv6:[[:space:]]*//p' "$FILE" | head -1)
PROXIES=$(sed -n '/^[[:space:]]*proxies:/,/^[[:space:]]*rules:/p' "$FILE")
SNI=$(echo "$PROXIES" | sed -n 's/^[[:space:]]*sni:[[:space:]]*//p' | head -1)
SERVER=$(echo "$PROXIES" | sed -n 's/^[[:space:]]*server:[[:space:]]*//p' | head -1)

if [ -z "$PRIV" ]; then
	echo "ОШИБКА: private-key не найден в ${FILE}"
	echo "Нужен Clash-конфиг типа Masque с warp-gen.github.io (секция Clash)."
	exit 1
fi
[ -z "$SERVER" ] && SERVER="162.159.198.2"
if [ -z "$PUB" ]; then
	echo "ВНИМАНИЕ: public-key не найден - endpoint_pub_key будет пустым."
fi

PUB_ESC="-----BEGIN PUBLIC KEY-----\n$(echo "$PUB" | awk '{while(length($0)>64){printf "%s\\n",substr($0,1,64); $0=substr($0,65)} printf "%s\\n",$0}')-----END PUBLIC KEY-----"
[ -z "$IP4" ] && IP4="172.16.0.2"
[ -z "$IP6" ] && IP6="2606:4700:110:8340:60db:9326:975a:e4f0"

mkdir -p /etc/usque
cat > /etc/usque/config.json << EOF
{
  "private_key": "${PRIV}",
  "endpoint_v4": "${SERVER}",
  "endpoint_v6": "2606:4700:d0::a29f:c602",
  "endpoint_pub_key": "${PUB_ESC}",
  "license": "",
  "id": "",
  "access_token": "",
  "ipv4": "${IP4}",
  "ipv6": "${IP6}"
}
EOF

if [ -n "$SNI" ] && [ -f /etc/init.d/usque ]; then
	sed -i "s/^SNI=\".*\"/SNI=\"${SNI}\"/" /etc/init.d/usque
	echo "SNI в /etc/init.d/usque обновлён: ${SNI}"
fi

echo "OK: /etc/usque/config.json создан из ${FILE}"
echo "  endpoint: ${SERVER}, ipv4: ${IP4}, ipv6: ${IP6}, sni: ${SNI:-не указан}"