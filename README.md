# Xray VPN via Docker Compose

Этот репозиторий разворачивает Xray VPN на сервере одной командой. В git хранится только шаблон конфига и инфраструктура деплоя. Рабочий `config.json`, секреты и клиентские параметры генерируются локально на сервере.

## Что внутри

- `compose.yaml` поднимает один production-сервис `xray` на официальном образе `ghcr.io/xtls/xray-core`.
- `server/config.template.json` хранит шаблон Xray-конфига для `VLESS + REALITY` и отдельного `telegram-socks` inbound.
- `install.sh` подготавливает хост при необходимости и запускает полный деплой.
- `scripts/install-host.sh` устанавливает Docker/Compose и открывает нужные порты через `ufw` на Ubuntu/Debian.
- `scripts/preflight.sh` делает non-mutating preflight-checks перед первым деплоем.
- `scripts/bootstrap.sh` создает `.env`, генерирует секреты, рендерит конфиг и запускает контейнер.
- `scripts/validate.sh` проверяет `compose` и валидирует Xray-конфиг через официальный контейнер.
- `scripts/doctor.sh` диагностирует уже настроенный сервер и deployment state.
- `.generated/` содержит только локально сгенерированные артефакты и не коммитится.

## Требования

- Ubuntu/Debian VPS
- Открытые входящие порты:
  - `XRAY_VLESS_PORT`/tcp
  - `XRAY_TELEGRAM_SOCKS_PORT`/tcp
  - `XRAY_TELEGRAM_SOCKS_PORT`/udp

## Быстрый старт

```sh
git clone <your-repo-url>
cd vpn-config
./install.sh
```

Скрипт:

1. запускает preflight-проверки
2. при необходимости устанавливает Docker и Compose plugin
3. настраивает `ufw` и открывает порты VPN, не ломая существующие правила
4. создает `.env` из `.env.example`, если файла еще нет
5. генерирует UUID, REALITY private key, short ID и SOCKS credentials
6. рендерит `.generated/server/config.json`
7. запускает `docker compose up -d`
8. ждет healthy status контейнера и проверяет опубликованные порты
9. пишет клиентские параметры в `.generated/client/connection-summary.txt`
10. генерирует готовый `Shadowrocket`-конфиг и отдельный `vless://` import link
11. запускает post-deploy doctor check

Если Docker уже установлен, `install.sh` пропускает host bootstrap и сразу переходит к deployment flow.

## Основные переменные

Править обычно нужно только `.env`.

- `XRAY_SERVER_ADDRESS`: внешний IP или DNS сервера для клиентских подсказок; если пусто, скрипт сначала попробует определить публичный IPv4 через внешние сервисы, потом локальный IPv4
- `XRAY_IMAGE_TAG`: версия официального Xray image
- `XRAY_VLESS_PORT`: входящий VLESS/REALITY порт
- `XRAY_REALITY_DEST`: маскируемый target, по умолчанию `www.cloudflare.com:443`
- `XRAY_REALITY_SERVER_NAME`: SNI для REALITY
- `XRAY_TELEGRAM_SOCKS_PORT`: SOCKS порт

## Операционные команды

Полный повторный деплой:

```sh
./install.sh
```

Первичная валидация:

```sh
./scripts/validate.sh
```

Preflight без изменений на хосте:

```sh
./scripts/preflight.sh
```

Диагностика уже настроенного сервера:

```sh
./scripts/doctor.sh
```

Просмотр статуса:

```sh
docker compose ps
```

Логи:

```sh
docker compose logs -f
```

Перезапуск:

```sh
docker compose restart
```

Обновление Xray:

1. поменять `XRAY_IMAGE_TAG` в `.env`
2. заново выполнить `./scripts/validate.sh`
3. выполнить `docker compose pull && docker compose up -d`

## Клиентские данные

После `bootstrap` готовые параметры лежат в `.generated/client/connection-summary.txt`.

Готовые клиентские артефакты:

- `.generated/client/connection-summary.txt`
- `.generated/client/shadowrocket.conf`
- `.generated/client/shadowrocket-vless.txt`

Там есть:

- адрес сервера
- UUID
- REALITY server name
- REALITY public key
- short ID
- готовый VLESS URI
- готовая строка для Telegram SOCKS

Для Shadowrocket основной путь теперь такой:

1. забрать `.generated/client/shadowrocket.conf`
2. импортировать файл в клиент

Если конкретная версия клиента не примет локальный `.conf`, запасной путь:

1. открыть `.generated/client/shadowrocket-vless.txt`
2. импортировать содержащийся там `vless://` link

## Бэкап

Для переноса сервера достаточно сохранить:

- `.env`
- содержимое `.generated/client/connection-summary.txt` при необходимости

Рабочий `config.json` можно не бэкапить: он детерминированно рендерится из `.env`.

## Чистый сервер

Минимальный сценарий для fresh VPS:

```sh
apt-get update && apt-get install -y git
git clone <your-repo-url>
cd vpn-config
./install.sh
```

Если работаешь не под `root`, скрипт использует `sudo` для установки Docker и firewall.

## Надёжность деплоя

- Повторный `./install.sh` безопасен: существующие секреты в `.env` не перегенерируются.
- `install.sh` падает раньше, если не может достучаться до `ghcr.io`, если порты заняты или если есть явный риск с `ufw` и SSH.
- При проблемах post-deploy проверка выводит статус контейнера и последние логи.
