#!/bin/sh
. "$(dirname "$0")/_lib.sh"

echo "Content-Type: application/json"
echo ""
require_password

ACTION=""
for kv in $(echo "$QUERY_STRING" | tr '&' ' '); do
	key=${kv%%=*}
	val=${kv#*=}
	[ "$key" = "action" ] && ACTION="$val"
done

case "$ACTION" in
	restart_usque)
		/etc/init.d/usque restart >/dev/null 2>&1
		echo '{"ok":true,"message":"usque перезапущен"}'
		;;
	restart_byedpi)
		/etc/init.d/byedpi restart >/dev/null 2>&1
		echo '{"ok":true,"message":"byedpi перезапущен"}'
		;;
	enable_byedpi)
		/etc/init.d/byedpi enable >/dev/null 2>&1
		/etc/init.d/byedpi start >/dev/null 2>&1
		echo '{"ok":true,"message":"byedpi включён и запущен"}'
		;;
	disable_byedpi)
		/etc/init.d/byedpi stop >/dev/null 2>&1
		/etc/init.d/byedpi disable >/dev/null 2>&1
		echo '{"ok":true,"message":"byedpi остановлен и отключён из автозагрузки"}'
		;;
	restart_dnsmasq)
		/etc/init.d/dnsmasq restart >/dev/null 2>&1
		echo '{"ok":true,"message":"dnsmasq перезапущен, DNS-кэш сброшен"}'
		;;
	apply_targets)
		/usr/bin/warp-targets-apply.sh >/dev/null 2>&1
		echo '{"ok":true,"message":"список целей WARP применён заново"}'
		;;
	reboot_router)
		echo '{"ok":true,"message":"роутер уходит в перезагрузку - страница отвалится на минуту-две"}'
		( sleep 1; reboot ) >/dev/null 2>&1 &
		;;
	*)
		echo '{"ok":false,"error":"неизвестное действие"}'
		;;
esac