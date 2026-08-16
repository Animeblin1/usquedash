json_escape() {
	sed -e ':a;N;$!ba' -e 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g'
}

HASH_FILE="/etc/dashboard-password.hash"

check_password() {
	[ -f "$HASH_FILE" ] || return 1
	[ -n "$1" ] || return 1
	SUPPLIED_HASH=$(printf '%s' "$1" | md5sum | cut -d' ' -f1)
	[ "$SUPPLIED_HASH" = "$(cat "$HASH_FILE")" ]
}

require_password() {
	if [ ! -f "$HASH_FILE" ]; then
		echo '{"ok":false,"error":"пароль не настроен на роутере"}'
		exit 0
	fi
	if ! check_password "$HTTP_X_PASSWORD"; then
		echo '{"ok":false,"error":"неверный пароль"}'
		exit 0
	fi
}

is_valid_ip() {
	echo "$1" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$'
}

is_valid_domain() {
	echo "$1" | grep -qE '^[A-Za-z0-9]([A-Za-z0-9.-]{0,251}[A-Za-z0-9])?$'
}

is_valid_label() {
	echo "$1" | grep -qE '^[A-Za-z0-9_-]{0,32}$'
}

is_safe_filename() {
	case "$1" in
		*/*|*..*|"") return 1 ;;
		*) return 0 ;;
	esac
}