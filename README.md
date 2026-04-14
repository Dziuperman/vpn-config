# Xray VPN via Docker Compose

Этот репозиторий разворачивает Xray VPN на сервере одной командой. В git хранится только шаблон конфига и инфраструктура деплоя. Рабочий `config.json`, секреты и клиентские параметры генерируются локально на сервере.

## Что внутри

- `compose.yaml` поднимает один production-сервис `xray` на официальном образе `ghcr.io/xtls/xray-core`.
- `server/config.template.json` хранит шаблон Xray-конфига для `VLESS + REALITY` и отдельного `telegram-socks` inbound.
- `install.sh` подготавливает хост при необходимости и запускает полный деплой.
- `scripts/install-host.sh` устанавливает Docker/Compose и открывает нужные порты через `ufw` на Ubuntu/Debian.
- `scripts/bootstrap.sh` создает `.env`, генерирует секреты, рендерит конфиг и запускает контейнер.
- `scripts/validate.sh` проверяет `compose` и валидирует Xray-конфиг через официальный контейнер.
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

1. при необходимости устанавливает Docker и Compose plugin
2. настраивает `ufw` и открывает порты VPN
3. создает `.env` из `.env.example`, если файла еще нет
4. генерирует UUID, REALITY private key, short ID и SOCKS credentials
5. рендерит `.generated/server/config.json`
6. запускает `docker compose up -d`
7. ждет healthy status контейнера
8. пишет клиентские параметры в `.generated/client/connection-summary.txt`
9. генерирует готовый `Shadowrocket`-конфиг и отдельный `vless://` import link

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
