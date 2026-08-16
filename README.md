# warp-byedpi-router

Поднимает на роутере (OpenWrt-совместимые прошивки, проверено на SNR-CPE) обход блокировок двумя слоями:

- **WARP** — туннель usque (MASQUE-протокол Cloudflare) на весь LAN или на отдельные цели
- **ByeDPI** — десинхронизация TLS на весь LAN
- **Веб-дашборд** — управление всем из браузера на отдельном порту

## Быстрая установка одной командой

```sh
wget -qO- https://raw.githubusercontent.com/Animeblin1/warp-byedpi-router/main/install.sh | sh -s full
```

(если на роутере есть `curl`):

```sh
curl -fsSL https://raw.githubusercontent.com/Animeblin1/warp-byedpi-router/main/install.sh | sh -s full
```

Скрипт сам скачает пакет с GitHub, поставит всё и в конце напечатает адрес дашборда.

### Режимы

| Режим | Что ставит |
|---|---|
| `full` | ByeDPI на весь LAN + ядро WARP (цели добавляются из дашборда) |
| `warp` | Только WARP на весь LAN |
| `byedpi` | Только ByeDPI на весь LAN |

### Параметры

```sh
sh install.sh <режим> [пароль_дашборда] [порт_дашборда]
```

Переменные окружения (можно задать до запуска: `WARP_SNI=ya.ru sh install.sh full`):

| Переменная | По умолчанию | Что делает |
|---|---|---|
| `WARP_SNI` | `ya.ru` | SNI-маскировка MASQUE-сессии |
| `LAN_SUBNET` | определяется автоматически | Подсеть LAN, например `192.168.1.0/24` |
| `LAN_IFACE` | определяется автоматически | LAN-интерфейс (обычно `br-lan`) |
| `CLASH_FILE` | пусто | Путь к Clash-конфигу WARP — импортируется при установке |

При запуске в терминале скрипт спросит SNI и путь к Clash-конфигу, если они не заданы.

Пароль дашборда задаётся вторым аргументом, либо будет запрошен (или сгенерирован случайно). На роутере хранится только md5-хэш.

## Ключи WARP: совместимость с warp-gen.github.io

Ключи и параметры туннеля берутся из готового Clash-конфига:

1. Зайди на **https://warp-gen.github.io/**
2. Раздел **Clash**, тип **Masque** — скачай yaml-файл (например `ClashWARP_93.yaml`)
3. Один из способов:
   - **Дашборд**: вкладка «Clash-конфиг» → вставь содержимое файла → «Импортировать» → «Перезапустить usque»
   - **SSH**: `sh /usr/bin/import-clash.sh /путь/к/файлу.yaml`
   - **При установке**: `CLASH_FILE=/tmp/ClashWARP_93.yaml sh install.sh full`

Из yaml извлекаются: `private-key`, `public-key` (заворачивается в PEM), `ip`, `ipv6`, `server`, `sni` (SNI дополнительно прописывается в init-скрипт usque). Результат — `/etc/usque/config.json`.

Проверить руками:

```sh
/usr/bin/usque nativetun -c /etc/usque/config.json -s ya.ru
```

## Дашборд

- Адрес: `http://<ip-роутера>:<порт>` (по умолчанию порт **1623**, LuCI на 80-м не трогается)
- Вход по паролю (md5-хэш в `/etc/dashboard-password.hash`)
- Обновление статуса раз в 5 секунд

Вкладки:

- **Статус** — usque/tun0/ByeDPI/watchdog/память//overlay, кнопки рестартов, сброс DNS, перезагрузка роутера
- **WARP-цели** — добавляй IP или домен, они идут через WARP; домены автоматически резолвятся, есть кнопка пере-резолва. Список в `/etc/warp-targets.conf`, переприменяется кроном каждые 5 минут и при загрузке роутера
- **Бэкапы** — создание/скачивание/восстановление/удаление архивов конфигов (ключи WARP, init-скрипты, цели, cron, iptables)
- **Clash-конфиг** — импорт yaml с warp-gen.github.io прямо в браузер

## Watchdog

`usque` на слабых роутерах умирает молча (без записей в лог). `/usr/bin/usque-watchdog.sh` по крону раз в минуту проверяет процесс, `tun0` и маршрут в таблице `warp`; при падении перезапускает тоннель и пишет в `/var/log/usque-watchdog.log`.

```sh
cat /var/log/usque-watchdog.log
```

Пустой файл — падений не было. Записи вида `ПАДЕНИЕ: ... (аптайм: N min)` → `рестарт успешен` — watchdog работает.

## Troubleshooting

**tun0 не поднимается, лог usque пуст, /overlay почти полон**
Usque падает с сегфолтом при нехватке места в jffs2. `df -h /overlay` — если ~100%, нужен `reboot` (jffs2 не освобождает место от удалённых файлов без перемонтирования).

**Видео/сайты отваливаются раз в несколько минут**
Это падение usque — работает watchdog, поднимает за минуту. Смотри `/var/log/usque-watchdog.log` на предмет закономерности. Память: `free -m` (на роутере ~124 МБ, свободно должно быть не меньше ~30 МБ при живом тоннеле).

**`not pollable` при апгрейде бинарника usque**
Старый процесс держит старый бинарник. `kill $(cat /var/run/usque.pid)` и `/etc/init.d/usque start` заново.

**crond пишет `ignoring file 'root' (no such user)`**
На прошивках типа SNR-CPE реальный пользователь — `Admin` (uid=0), а не `root`. Скрипты установки определяют имя автоматически и пишут в `/etc/crontabs/<реальное_имя>`.

**usque не поднимается после ребута**
`ls -la /etc/rc.d/ | grep usque` — должны быть `S97usque`/`K12usque`. Нет — `/etc/init.d/usque enable`.

**Старые открытые соединения не идут через WARP**
`ip rule` применяется к новым соединениям. Перезапусти приложения/вкладки.

## Откат

```sh
/etc/init.d/usque stop && /etc/init.d/usque disable
/etc/init.d/byedpi stop && /etc/init.d/byedpi disable
```

Удалить все WARP-правила целиком: `ip rule flush table warp; iptables -t nat -F BYEDPI`.

## Структура репозитория

```
install.sh                      главный установщик (одна команда)
core/
  install-usque-core.sh         ядро WARP: tun0 + таблица warp, цели из дашборда
  install-usque-wholelan.sh     WARP на весь LAN
  install-byedpi.sh             ByeDPI на весь LAN
  import-clash.sh               конвертер Clash yaml (warp-gen) -> config.json
  usque-watchdog.sh             авторестарт при падении тоннеля
  usque-mipsel                  бинарник usque под mipsel
  config.json.example           пример конфига usque
dashboard/
  install-dashboard.sh          установка дашборда (отдельный uhttpd)
  index.html                    страница дашборда
  warp-targets-apply.sh         применение списка целей (idempotent)
  warp-targets.init             автозагрузка целей
  cgi-bin/                      CGI-скрипты (статус, действия, цели, бэкапы, импорт)
```

## Совместимость

Проверено на: SNR-CPE-ME2-SFP-Lite, прошивка 3.5.1-2607021209, BusyBox v1.34.1, 124 МБ RAM. Любая OpenWrt-совместимая прошивка с `uci`, `opkg`, `uhttpd`, `iptables` и `ip` (iproute2) подойдёт. Бинарник usque — mipsel (24kc).