# Xray VPN via Docker Compose

Этот репозиторий разворачивает Xray VPN на сервере одной командой через `docker compose`. В git хранится только шаблон конфига и инфраструктура деплоя. Рабочий `config.json`, секреты и клиентские параметры генерируются локально на сервере.

## Что внутри

- `compose.yaml` поднимает один production-сервис `xray` на официальном образе `ghcr.io/xtls/xray-core`.
- `server/config.template.json` хранит шаблон Xray-конфига для `VLESS + REALITY` и отдельного `telegram-socks` inbound.
- `scripts/bootstrap.sh` создает `.env`, генерирует секреты, рендерит конфиг и запускает контейнер.
- `scripts/validate.sh` проверяет `compose` и валидирует Xray-конфиг через официальный контейнер.
- `.generated/` содержит только локально сгенерированные артефакты и не коммитится.

## Требования

- Linux/VPS с установленными `docker` и `docker compose`
- Открытые входящие порты:
  - `XRAY_VLESS_PORT`/tcp
  - `XRAY_TELEGRAM_SOCKS_PORT`/tcp
  - `XRAY_TELEGRAM_SOCKS_PORT`/udp

## Быстрый старт

```sh
git clone <your-repo-url>
cd vpn-config
./scripts/bootstrap.sh
```

Скрипт:

1. создает `.env` из `.env.example`, если файла еще нет
2. генерирует UUID, REALITY private key, short ID и SOCKS credentials
3. рендерит `.generated/server/config.json`
4. запускает `docker compose up -d`
5. пишет клиентские параметры в `.generated/client/connection-summary.txt`

## Основные переменные

Править обычно нужно только `.env`.

- `XRAY_SERVER_ADDRESS`: внешний IP или DNS сервера для клиентских подсказок; если пусто, скрипт попробует определить адрес автоматически
- `XRAY_IMAGE_TAG`: версия официального Xray image
- `XRAY_VLESS_PORT`: входящий VLESS/REALITY порт
- `XRAY_REALITY_DEST`: маскируемый target, по умолчанию `www.cloudflare.com:443`
- `XRAY_REALITY_SERVER_NAME`: SNI для REALITY
- `XRAY_TELEGRAM_SOCKS_PORT`: SOCKS порт

## Операционные команды

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

Там есть:

- адрес сервера
- UUID
- REALITY server name
- REALITY public key
- short ID
- готовая строка для Telegram SOCKS

## Бэкап

Для переноса сервера достаточно сохранить:

- `.env`
- содержимое `.generated/client/connection-summary.txt` при необходимости

Рабочий `config.json` можно не бэкапить: он детерминированно рендерится из `.env`.
