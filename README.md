# usquedash

Поднимает на роутере (OpenWrt-совместимые прошивки, проверено на SNR-CPE) обход блокировок двумя слоями:

- **WARP** — туннель usque (MASQUE-протокол Cloudflare) на весь LAN или на отдельные цели
- **ByeDPI** — десинхронизация TLS на весь LAN
- **Веб-дашборд** — управление всем из браузера на отдельном порту

## Быстрая установка одной командой

```sh
wget -qO- https://raw.githubusercontent.com/Animeblin1/usquedash/main/install.sh | sh -s full
```

(если на роутере есть `curl`):

```sh
curl -fsSL https://raw.githubusercontent.com/Animeblin1/usquedash/main/install.sh | sh -s full
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

## Установка вручную (без скрипта)

Всё то же самое можно сделать руками — скрипты идемпотентны, порядок шагов не важен. В каждом скрипте есть комментарии с пояснениями для ручной настройки.

```sh
# 0. Модуль TUN (нужен для WARP)
opkg update && opkg install kmod-tun
insmod tun
mkdir -p /dev/net && [ -c /dev/net/tun ] || mknod /dev/net/tun c 10 200

# 1. WARP: бинарник + ключи + ядро (цели из дашборда)
cp core/usque-mipsel /usr/bin/usque && chmod +x /usr/bin/usque
mkdir -p /etc/usque
sh core/import-clash.sh /tmp/ClashWARP_93.yaml    # ключи из Clash-конфига warp-gen
# или вручную: cp core/config.json.example /etc/usque/config.json и заполни ключи
sh core/install-usque-core.sh                      # создаст /etc/init.d/usque и стартует

# 1b. ИЛИ WARP на ВЕСЬ LAN (вместо п.1):
sh core/install-usque-wholelan.sh

# 2. ByeDPI (десинхронизация на весь LAN)
sh core/install-byedpi.sh

# 3. Watchdog (авторестарт тоннеля при падении)
cp core/usque-watchdog.sh /usr/bin/usque-watchdog.sh && chmod +x /usr/bin/usque-watchdog.sh
echo '* * * * * /usr/bin/usque-watchdog.sh' >> /etc/crontabs/Admin   # имя файла = реальный
/etc/init.d/cron restart                                              # пользователь из /etc/passwd!

# 4. Дашборд на порту 1623 с паролем
cd dashboard && sh install-dashboard.sh 1623 мой_пароль

# 5. Цели WARP (IP или домен; домен резолвится автоматически)
echo "192.168.1.50|ТВ|192.168.1.50" >> /etc/warp-targets.conf
sh /usr/bin/warp-targets-apply.sh

# Откат любого шага:
/etc/init.d/usque stop && /etc/init.d/usque disable
/etc/init.d/byedpi stop && /etc/init.d/byedpi disable
ip rule flush table warp; iptables -t nat -F BYEDPI
```

## Маршрутизация: что куда идёт

Три пути трафика из LAN, в зависимости от установленных компонентов:

| Компонент | Трафик | Механизм |
|---|---|---|
| WARP-цели (дашборд) | только IP/домены из `/etc/warp-targets.conf` | `ip rule` 150-199 → таблица `warp` → tun0 |
| WARP wholelan | весь LAN | `ip rule` priority 80: `from <LAN_SUBNET> lookup warp` |
| ByeDPI | весь LAN, tcp 443/80 | `nat PREROUTING` цепочка `BYEDPI` → REDIRECT на 1081 |
| Ничего из выше | прямой интернет | обычная маршрутизация `main` |

Порядок обработки пакета из LAN (важно для понимания):

1. **nat PREROUTING**: если адрес источника = WARP-цель (или вся подсеть в режиме wholelan) — `RETURN`, мимо ByeDPI. Это исключение вставляется позицией 2, до цепочки `BYEDPI`.
2. Иначе, если `tcp 443/80` — `REDIRECT` в ByeDPI (1081): пакет десинхронизируется и дальше идёт обычным путём.
3. **Решение о маршрутизации** (`ip rule`, проверяются от меньшего приоритета к большему):
   - 150-199 — цель из дашборда → таблица `warp` → **WARP**;
   - 80 — wholelan → таблица `warp` → **WARP**;
   - иначе — таблица `main` → **прямой WAN**.
4. FORWARD/POSTROUTING: MASQUERADE на tun0.

Важные следствия:

- **В режиме wholelan ByeDPI фактически не работает** — весь LAN-трафик исключён из REDIRECT и уходит в WARP. ByeDPI имеет смысл в режиме `full` (ядро WARP + цели): сайты вне списка целей идут напрямую, но с десинхронизацией.
- Сам тоннель usque ходит на `162.159.198.2:443` **с роутера** (не из LAN), поэтому в ByeDPI-редирект не попадает и не зацикливается.
- WARP-трафик внутри туннеля уже зашифрован (MASQUE) — второй прогон через ByeDPI не нужен.
- Правила 90/100 (ручные, из старых экспериментов) установщик не трогает.
- `ip rule` применяется к новым соединениям — старые открытые пойдут по старому пути до закрытия.

## ByeDPI: стратегии, тесты, фоллбэк

ByeDPI ставит два сервиса:
- `byedpi` (порт **1080**) — SOCKS5, для тестов стратегии;
- `byedpi-transparent` (порт **1081**) — прозрачный, в него REDIRECTит iptables.

**Флаги стратегии** (одинаковые в обоих сервисах):

| Флаг | Смысл |
|---|---|
| `-d N+s` | фейковый сегмент после N-го пакета данных, `+s` — с разбиением |
| `-s N+s` | разбить N-й пакет на части (запутывает DPI-анализ потока) |
| `-r N+s` | отправить N пакетов в обратном порядке |
| `-S` | фейковый SACK в служебных опциях TCP |
| `-a N` | фейковый ACK после N-го сегмента |
| `-E -D` | служебные (фрагментация исходящих и т.п.) — не трогай без необходимости |

**Тест стратегии** (с роутера, порт 1080):

```sh
curl -x socks5://127.0.0.1:1080 -I https://ya.ru --max-time 10
curl -x socks5://127.0.0.1:1080 -I https://youtube.com --max-time 10
```

Ожидается `HTTP/1.1 302` (или 200) — туннель живой. Сравни с прямым запросом без `-x`.

**Смена стратегии** (например, если сайт не открывается или скорость просела):

1. Правь строку `option cmd_opts` в `/etc/config/byedpi` (порт 1080) и аргументы запуска в `/etc/init.d/byedpi-transparent` (порт 1081).
2. Перезапуск:
```sh
/etc/init.d/byedpi restart && /etc/init.d/byedpi-transparent restart
```
3. Повтори тест из пункта выше.

**Готовые стратегии для перебора** (по возрастанию агрессивности):

| # | Флаги |
|---|---|
| A (по умолчанию) | `-d1 -d3+s -s6+s -d9+s -s12+s -d15+s -s20+s -d25+s -s30+s -d35+s -r1+s -S -a1` |
| B | `-d2 -d4+s -s6+s -d9+s -d12+s -d15+s -s20+s -d25+s -d30+s -d35+s -r2+s -S -a1` |
| C (минимальная) | `-d1 -d3+s -s6+s -d9+s -r1+s -S -a1` |

**Фоллбэк** — если ByeDPI мешает (сайт перестал открываться вообще) или стратегия не подходит:

```sh
/etc/init.d/byedpi stop && /etc/init.d/byedpi-transparent stop
iptables -t nat -F BYEDPI
```

WARP при этом продолжает работать — сайты из списка целей идут через туннель, остальные напрямую.

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