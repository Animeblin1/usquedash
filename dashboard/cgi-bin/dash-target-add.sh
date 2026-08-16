#!/bin/sh
. "$(dirname "$0")/_lib.sh"

echo "Content-Type: application/json"
echo ""
require_password

CONF="/etc/warp-targets.conf"
TARGET=""
LABEL=""
MODE=""
for kv in $(echo "$QUERY_STRING" | tr '&' ' '); do
	key=${kv%%=*}
	val=${kv#*=}
	case "$key" in
		target) TARGET="$val" ;;
		label) LABEL="$val" ;;
		mode) MODE="$val" ;;
	esac
done

TARGET="$(urldecode "$TARGET")"
LABEL="$(urldecode "$LABEL")"

[ -z "$MODE" ] && MODE="warp"
case "$MODE" in
	warp|direct|byedpi) ;;
	*) echo '{"ok":false,"error":"режим: warp, direct или byedpi"}'; exit 0 ;;
esac

if ! is_valid_label "$LABEL"; then
	echo '{"ok":false,"error":"метка: только латиница/цифры/дефис/подчёркивание, до 32 символов"}'
	exit 0
fi

TYPE=""
case "$TARGET" in
	*.*)
		;;
esac
case "$TARGET" in
	\*.)
		echo '{"ok":false,"error":"суффикс: *.домен (например *.youtube.com)"}'
		exit 0
		;;
	\*.?*)
		SUF="$TARGET"
		echo "$SUF" | grep -qE '^\*\.[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$' || {
			echo '{"ok":false,"error":"суффикс: *.домен (например *.youtube.com)"}'
			exit 0
		}
		IP=".${SUF#\*.}"
		SRC="$IP"
		TYPE="suffix"
		;;
	/*)
		RE="${TARGET#/}"
		RE="${RE%/}"
		[ -n "$RE" ] || {
			echo '{"ok":false,"error":"регэксп пустой"}'
			exit 0
		}
		if ! is_valid_regex "$RE"; then
			echo '{"ok":false,"error":"регэксп: до 64 символов, только буквы/цифры/символы . _ ( ) | ^ $ + * ? { } -"}'
			exit 0
		fi
		case "$RE" in
			'^(.*\.)?'*'$')
				D="${RE#'^(.*\.)?'}"
				D="${D%'$'}"
				D=$(printf '%s' "$D" | sed 's/\\\././g')
				D="${D#.}"
				;;
			*)
				D=""
				;;
		esac
		if [ -z "$D" ] || ! is_valid_domain "$D"; then
			echo '{"ok":false,"error":"регэксп: поддерживается только вид ^(.*\\.)?домен$ (эквивалент *.домен)"}'
			exit 0
		fi
		IP=".${D}"
		SRC="$D"
		TYPE="suffix"
		;;
	*)
		if is_valid_ip "$TARGET"; then
			IP="$TARGET"
			SRC="$TARGET"
			TYPE="ip"
		elif is_valid_domain "$TARGET"; then
			SRC="$TARGET"
			IP=$(nslookup "$TARGET" 2>/dev/null | awk '/^Address [0-9]+:/{print $3; exit} /^Address:/{a++; if(a>1){print $2; exit}}')
			if [ -z "$IP" ] || ! is_valid_ip "$IP"; then
				echo '{"ok":false,"error":"не удалось разрешить домен в IP (nslookup не дал ответа)"}'
				exit 0
			fi
			TYPE="domain"
		else
			echo '{"ok":false,"error":"нужен IPv4 (192.168.1.50), домен (youtube.com), суффикс (*.youtube.com) или регэксп (/^(.*\\.)?discord\\\\.gg$/)"}'
			exit 0
		fi
		;;
esac

[ -z "$LABEL" ] && LABEL="$SRC"

touch "$CONF"
[ "$(conf_has_key "$IP" "$CONF")" = "YES" ] && {
	echo '{"ok":false,"error":"такая цель уже в списке"}'
	exit 0
}

echo "${IP}|${LABEL}|${SRC}|${MODE}|${TYPE}" >> "$CONF"
/usr/bin/warp-targets-apply.sh >/dev/null 2>&1

if [ "$TYPE" = "suffix" ]; then
	MSG="${TARGET} и все поддомены добавлены (режим ${MODE})"
elif [ "$TYPE" = "regex" ]; then
	MSG="регэксп /${SRC}/ добавлен (режим ${MODE})"
elif [ "$IP" = "$SRC" ]; then
	MSG="${IP} добавлен (режим ${MODE})"
else
	MSG="${SRC} -> ${IP} добавлен (режим ${MODE})"
fi
echo "{\"ok\":true,\"message\":\"${MSG}\"}"