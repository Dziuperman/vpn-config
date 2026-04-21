# Xray VPN via Docker Compose

Этот репозиторий разворачивает Xray VPN на сервере одной командой. В git хранится только шаблон конфига и инфраструктура деплоя. Рабочий `config.json`, секреты и клиентские параметры генерируются локально на сервере.

Дополнительно в репозитории есть `ansible/` слой для reproducible provisioning и idempotent deploy на Ubuntu/Debian VPS без ручной рутины на хосте.

## Что внутри

- `compose.yaml` поднимает один production-сервис `xray` на официальном образе `ghcr.io/xtls/xray-core`.
- `server/config.template.json` хранит шаблон Xray-конфига для `VLESS + REALITY` и отдельного `telegram-socks` inbound.
- `install.sh` подготавливает хост при необходимости и запускает полный деплой.
- `scripts/install-host.sh` устанавливает Docker/Compose и открывает нужные порты через `ufw` на Ubuntu/Debian.
- `scripts/preflight.sh` делает non-mutating preflight-checks перед первым деплоем.
- `scripts/bootstrap.sh` создает `.env`, генерирует секреты, рендерит конфиг и запускает контейнер.
- `scripts/validate.sh` проверяет `compose` и валидирует Xray-конфиг через официальный контейнер.
- `scripts/doctor.sh` диагностирует уже настроенный сервер и deployment state.
- `ansible/playbooks/provision.yml` приводит хост к ожидаемому системному состоянию.
- `ansible/playbooks/deploy.yml` управляет `.env`, deploy flow и post-deploy verify.
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
./vpn install
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
10. генерирует отдельно `Shadowrocket` rules profile и отдельно `vless://` import link для node
11. запускает post-deploy doctor check

Если Docker уже установлен, `./vpn install` пропускает host bootstrap и сразу переходит к deployment flow.

## Когда использовать Ansible

Для одного VPS shell workflow через `./vpn` остаётся нормальным быстрым путём.

`Ansible` нужен, когда важны:

- воспроизводимый bootstrap нового сервера;
- отсутствие ручного drift в Docker/firewall/system state;
- повторяемый deploy через inventory вместо ручных шагов на хосте;
- удобный переход к нескольким серверам или окружениям.

Профессиональная схема в этом репозитории теперь такая:

- `./vpn` и `scripts/*` остаются application-specific runtime tooling;
- `ansible/` отвечает за host provisioning, `.env` orchestration и repeatable deploy.

Базовый поток:

```sh
cd ansible
ansible-playbook playbooks/provision.yml -l vpn-prod
ansible-playbook playbooks/deploy.yml -l vpn-prod
```

Что именно делает `ansible/`:

- ставит базовые пакеты, Docker Engine и Compose plugin;
- добавляет allow rules для SSH и VPN в `ufw`, не меняя default policy и не включая firewall автоматически;
- раскладывает проект в `project_root`;
- сохраняет существующие секреты из удалённого `.env` или генерирует новые на первом запуске;
- рендерит `config.json`, запускает `docker compose up -d`, ждёт healthy state;
- переиспользует `scripts/validate.sh` и `scripts/doctor.sh` для проверки результата.

Структура настроек:

- `ansible/group_vars/vpn.yml` содержит общие defaults;
- `ansible/host_vars/vpn-prod.yml.example` показывает рекомендуемый per-host формат, а playbooks явно подгружают `ansible/host_vars/<host>.yml`;
- реальные `ansible/host_vars/*.yml` игнорируются в git, чтобы не утекали production secrets.

Если хочешь контролируемые и предсказуемые секреты, храни их в `host_vars` или `Ansible Vault`.
Если секреты не заданы, первый deploy сгенерирует их на удалённом сервере и затем будет переиспользовать без ротации.

`Ansible` firewall management в `ansible/` работает в additive-режиме:

- playbook только добавляет allow rules для SSH и Xray;
- не включает `ufw` автоматически;
- не меняет default incoming/outgoing policy;
- это безопаснее для VPS, где уже есть ручные правила или другие сервисы.

## CLI

Основной публичный интерфейс проекта теперь это `./vpn`.

```sh
./vpn install
./vpn preflight
./vpn doctor
./vpn validate
./vpn status
./vpn logs --tail 100
./vpn restart
./vpn client summary
./vpn client shadowrocket-rules
./vpn client shadowrocket-rules-url
./vpn client uri
./vpn env get XRAY_VLESS_PORT
./vpn env set XRAY_VLESS_PORT 9443
```

Для `install`, `deploy` и `preflight` доступны флаги:

```sh
./vpn install --vless-port 9443 --server-address vpn.example.com
./vpn deploy --image-tag 25.12.8
```

Поддерживаемые флаги:

- `--server-address`
- `--vless-port`
- `--telegram-socks-port`
- `--image-tag`
- `--log-level`
- `--reality-dest`
- `--reality-server-name`

## Примеры запуска

Стандартный деплой:

```sh
./vpn install
```

Деплой с явным адресом сервера:

```sh
./vpn install --server-address vpn.example.com
```

Деплой на нестандартном VLESS-порту:

```sh
./vpn install --vless-port 9443
```

Деплой, если на сервере уже заняты и VLESS, и SOCKS порты:

```sh
./vpn install --vless-port 9443 --telegram-socks-port 29419
```

Повторный деплой только runtime-части без host bootstrap:

```sh
./vpn deploy --vless-port 9443 --telegram-socks-port 29419
```

Смена порта после первого запуска:

```sh
./vpn env set XRAY_VLESS_PORT 9443
./vpn env set XRAY_TELEGRAM_SOCKS_PORT 29419
./vpn deploy
```

Быстрая проверка перед деплоем с параметрами, без изменений на сервере:

```sh
./vpn preflight --vless-port 9443 --telegram-socks-port 29419
```

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
./vpn install
```

Первичная валидация:

```sh
./vpn validate
```

Preflight без изменений на хосте:

```sh
./vpn preflight
```

Диагностика уже настроенного сервера:

```sh
./vpn doctor
```

Просмотр статуса:

```sh
./vpn status
```

Логи:

```sh
./vpn logs
```

Перезапуск:

```sh
./vpn restart
```

Обновление Xray:

1. поменять `XRAY_IMAGE_TAG` через `./vpn env set XRAY_IMAGE_TAG <value>` или вручную в `.env`
2. заново выполнить `./vpn validate`
3. выполнить `docker compose pull && docker compose up -d`

## Клиентские данные

После `bootstrap` готовые параметры лежат в `.generated/client/connection-summary.txt`.

Готовые клиентские артефакты:

- `.generated/client/connection-summary.txt`
- `.generated/client/shadowrocket-rules.conf`
- `.generated/client/shadowrocket-vless.txt`

Там есть:

- адрес сервера
- UUID
- REALITY server name
- REALITY public key
- short ID
- готовый VLESS URI
- готовая строка для Telegram SOCKS

Для Shadowrocket правильный production-путь теперь такой:

1. импортировать node через `.generated/client/shadowrocket-vless.txt`
2. импортировать rules profile по remote URL или через `.generated/client/shadowrocket-rules.conf`

То есть node и rules теперь разделены намеренно.

Для updateable rules profile используй URL:

```sh
./vpn client shadowrocket-rules-url
```

Этот URL указывает на публичный rules-файл в GitHub, а внутри самого rules profile уже прописан `update-url`, поэтому после корректного remote-импорта в Shadowrocket rules можно обновлять без повторного переимпорта.

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
./vpn install
```

Если работаешь не под `root`, скрипт использует `sudo` для установки Docker и firewall.

## Надёжность деплоя

- Повторный `./vpn install` безопасен: существующие секреты в `.env` не перегенерируются.
- `./vpn install` падает раньше, если порты заняты или если есть явный риск с `ufw` и SSH.
- При проблемах post-deploy проверка выводит статус контейнера и последние логи.
