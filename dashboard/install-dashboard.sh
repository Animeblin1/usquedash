#!/bin/sh
set -e

PORT="${1:-1623}"
PASSWORD_ARG="${2:-}"
WWW_ROOT="/www-dashboard"
HASH_FILE="/etc/dashboard-password.hash"

echo "=== [1/6] Копируем файлы ==="
mkdir -p "${WWW_ROOT}/cgi-bin"
cp index.html "${WWW_ROOT}/index.html"
cp cgi-bin/dash-status.sh cgi-bin/dash-action.sh cgi-bin/dash-target-add.sh cgi-bin/dash-target-remove.sh \
   cgi-bin/dash-target-refresh.sh cgi-bin/dash-backup-create.sh cgi-bin/dash-backup-list.sh \
   cgi-bin/dash-backup-download.sh cgi-bin/dash-backup-restore.sh cgi-bin/dash-backup-delete.sh \
   cgi-bin/dash-import-clash.sh cgi-bin/_lib.sh \
   "${WWW_ROOT}/cgi-bin/"
chmod +x "${WWW_ROOT}"/cgi-bin/dash-*.sh
chmod 644 "${WWW_ROOT}/cgi-bin/_lib.sh"

if [ -f ../core/import-clash.sh ]; then
	cp ../core/import-clash.sh /usr/bin/import-clash.sh
	chmod +x /usr/bin/import-clash.sh
fi

cp warp-targets-apply.sh /usr/bin/warp-targets-apply.sh
chmod +x /usr/bin/warp-targets-apply.sh

cp warp-targets.init /etc/init.d/warp-targets
chmod +x /etc/init.d/warp-targets

touch /etc/warp-targets.conf
mkdir -p /etc/dashboard-backups

echo "=== [2/6] Пароль доступа ==="
if [ -f "$HASH_FILE" ]; then
	echo "Пароль уже задан ранее (хэш в ${HASH_FILE}) - оставляем как есть."
	echo "Сменить пароль: sh install-dashboard.sh ${PORT} НОВЫЙ_ПАРОЛЬ"
else
	if [ -n "$PASSWORD_ARG" ]; then
		PASSWORD="$PASSWORD_ARG"
	elif [ -t 0 ] || [ -r /dev/tty ]; then
		printf "Придумай пароль для дашборда: "
		read -r PASSWORD < /dev/tty 2>/dev/null || read -r PASSWORD
	fi
	if [ -z "$PASSWORD" ]; then
		PASSWORD=$(head -c 12 /dev/urandom | md5sum | cut -c1-14)
		echo "Пароль не введён - сгенерирован случайный: ${PASSWORD}"
		echo "ЗАПОМНИ ЕГО СЕЙЧАС, на роутере хранится только md5-хэш."
	fi
	printf '%s' "$PASSWORD" | md5sum | cut -d' ' -f1 > "$HASH_FILE"
	chmod 600 "$HASH_FILE"
fi

echo "=== [3/6] Отдельный uhttpd на порту ${PORT} ==="
uci -q delete uhttpd.dashboard 2>/dev/null || true
uci set uhttpd.dashboard='uhttpd'
uci add_list uhttpd.dashboard.listen_http="0.0.0.0:${PORT}"
uci set uhttpd.dashboard.home="${WWW_ROOT}"
uci set uhttpd.dashboard.cgi_prefix='/cgi-bin'
uci set uhttpd.dashboard.script_timeout='60'
uci set uhttpd.dashboard.network_timeout='30'
uci set uhttpd.dashboard.max_requests='50'
uci commit uhttpd
/etc/init.d/uhttpd restart

echo "=== [4/6] Включаем автозагрузку warp-targets ==="
/etc/init.d/warp-targets enable
/etc/init.d/warp-targets start

echo "=== [5/6] Cron на переприменение целей раз в 5 минут ==="
CRON_USER=$(awk -F: '$3==0{print $1; exit}' /etc/passwd)
[ -z "$CRON_USER" ] && CRON_USER="root"
mkdir -p /etc/crontabs
if ! grep -q warp-targets-apply "/etc/crontabs/${CRON_USER}" 2>/dev/null; then
	echo "*/5 * * * * /usr/bin/warp-targets-apply.sh" >> "/etc/crontabs/${CRON_USER}"
fi
/etc/init.d/cron restart
sleep 1
if logread | grep -q "ignoring file '${CRON_USER}'"; then
	echo "ВНИМАНИЕ: crond игнорирует файл ${CRON_USER} - проверь"
	echo "  awk -F: '\$3==0{print \$1}' /etc/passwd  и  logread | grep cron"
fi

echo "=== [6/6] Готово ==="
ROUTER_IP=$(uci get network.lan.ipaddr 2>/dev/null || echo "192.168.1.1")
echo ""
echo "Открой в браузере (с устройства в этой же LAN):"
echo "  http://${ROUTER_IP}:${PORT}/"
echo ""
echo "Заходи паролем, который задал(а) выше."