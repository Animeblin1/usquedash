#!/bin/sh
set -e

GITHUB_USER="Animeblin1"
REPO_NAME="warp-byedpi-router"
BRANCH="main"

MODE="${1:-}"
PASSWORD_ARG="${2:-}"
PORT="${3:-1623}"
WARP_SNI="${WARP_SNI:-ya.ru}"
LAN_SUBNET="${LAN_SUBNET:-}"
LAN_IFACE="${LAN_IFACE:-}"
CLASH_FILE="${CLASH_FILE:-}"

usage() {
	echo "Использование: sh install.sh <full|byedpi|warp> [пароль] [порт]"
	echo "  full   - ByeDPI на весь LAN + ядро WARP для целей из дашборда"
	echo "  byedpi - только ByeDPI на весь LAN"
	echo "  warp   - только WARP (usque/MASQUE) на весь LAN"
	echo "Переменные окружения: WARP_SNI, LAN_SUBNET, LAN_IFACE, CLASH_FILE"
}

if [ -z "$MODE" ]; then
	usage
	exit 1
fi
case "$MODE" in
	full|byedpi|warp) ;;
	*) echo "Неизвестный режим: $MODE"; exit 1 ;;
esac

if [ -t 0 ]; then
	printf "SNI-маскировка для MASQUE (по умолчанию %s): " "$WARP_SNI"
	read -r R
	[ -n "$R" ] && WARP_SNI="$R"
	if [ "$MODE" != "byedpi" ]; then
		printf "Путь к Clash-конфигу WARP с warp-gen.github.io (yaml, пусто - пропустить): "
		read -r R
		[ -n "$R" ] && CLASH_FILE="$R"
	fi
fi

if [ -z "$LAN_IFACE" ]; then
	LAN_IFACE=$(uci get network.lan.ifname 2>/dev/null | cut -d' ' -f1)
	[ -z "$LAN_IFACE" ] && LAN_IFACE="br-lan"
fi
if [ -z "$LAN_SUBNET" ]; then
	LAN_SUBNET=$(ip -o -4 addr show dev "$LAN_IFACE" 2>/dev/null | awk '{print $4; exit}')
	[ -z "$LAN_SUBNET" ] && LAN_SUBNET="192.168.1.0/24"
fi
export WARP_SNI LAN_SUBNET LAN_IFACE

WORKDIR="$(pwd)"
if [ ! -d "${WORKDIR}/core" ] || [ ! -d "${WORKDIR}/dashboard" ]; then
	echo "=== Файлов пакета рядом нет - скачиваю архив репозитория ==="
	TMPDIR="/tmp/warp-byedpi-install"
	rm -rf "$TMPDIR"
	mkdir -p "$TMPDIR"
	ARCHIVE_URL="https://codeload.github.com/${GITHUB_USER}/${REPO_NAME}/tar.gz/refs/heads/${BRANCH}"
	wget -O "${TMPDIR}/repo.tar.gz" "$ARCHIVE_URL"
	tar -xzf "${TMPDIR}/repo.tar.gz" -C "$TMPDIR"
	WORKDIR=$(find "$TMPDIR" -maxdepth 1 -type d -name "${REPO_NAME}-*" | head -1)
	if [ -z "$WORKDIR" ]; then
		echo "ОШИБКА: не удалось распаковать архив репозитория."
		exit 1
	fi
fi
cd "$WORKDIR"
echo "Работаю из: ${WORKDIR}"

case "$MODE" in
	full)
		echo "=== Режим FULL: ByeDPI (весь LAN) + ядро WARP (цели из дашборда) ==="
		( cd core && sh install-byedpi.sh )
		if [ -n "$CLASH_FILE" ]; then
			sh core/import-clash.sh "$CLASH_FILE"
		fi
		( cd core && sh install-usque-core.sh )
		NEED_WATCHDOG=1
		;;
	byedpi)
		echo "=== Режим BYEDPI: только ByeDPI на весь LAN ==="
		( cd core && sh install-byedpi.sh )
		NEED_WATCHDOG=0
		;;
	warp)
		echo "=== Режим WARP: только WARP на весь LAN ==="
		if [ -n "$CLASH_FILE" ]; then
			sh core/import-clash.sh "$CLASH_FILE"
		fi
		( cd core && sh install-usque-wholelan.sh )
		NEED_WATCHDOG=1
		;;
esac

if [ "$NEED_WATCHDOG" = "1" ]; then
	echo "=== Ставим cron-watchdog для usque ==="
	cp core/usque-watchdog.sh /usr/bin/usque-watchdog.sh
	chmod +x /usr/bin/usque-watchdog.sh
	CRON_USER=$(awk -F: '$3==0{print $1; exit}' /etc/passwd)
	[ -z "$CRON_USER" ] && CRON_USER="root"
	mkdir -p /etc/crontabs
	if ! grep -q usque-watchdog "/etc/crontabs/${CRON_USER}" 2>/dev/null; then
		echo '* * * * * /usr/bin/usque-watchdog.sh' >> "/etc/crontabs/${CRON_USER}"
	fi
	/etc/init.d/cron restart
fi

echo "=== Ставим веб-дашборд на порт ${PORT} ==="
( cd dashboard && sh install-dashboard.sh "$PORT" "$PASSWORD_ARG" )

echo ""
echo "======================================================================"
echo "ГОТОВО. Режим: ${MODE}"
ROUTER_IP=$(uci get network.lan.ipaddr 2>/dev/null || echo "192.168.1.1")
echo "Дашборд: http://${ROUTER_IP}:${PORT}/"
if [ "$MODE" = "full" ]; then
	echo "ByeDPI разворачивает весь LAN. WARP-ядро поднято, трафик через него"
	echo "пойдёт после добавления целей во вкладке 'WARP-цели' дашборда."
fi
echo "======================================================================"