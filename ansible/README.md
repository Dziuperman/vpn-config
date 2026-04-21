# Ansible Workflow

Этот каталог добавляет reproducible provisioning/deploy слой поверх существующих shell-скриптов проекта.

## Что делает Ansible

- `playbooks/provision.yml` приводит Ubuntu/Debian VPS в нужное базовое состояние:
  - ставит базовые пакеты,
  - настраивает Docker Engine и Compose plugin,
  - добавляет `ufw` allow rules для SSH и Xray, не меняя default policy и не включая firewall автоматически.
- `playbooks/deploy.yml` раскладывает проект на удалённый хост, управляет `.env`, сохраняет существующие секреты или генерирует новые на первом запуске, рендерит Xray-конфиг и выполняет deploy/verify flow.

## Ожидаемая модель эксплуатации

- `group_vars` задают безопасные общие defaults.
- `host_vars/<host>.yml` содержит адрес хоста и production overrides. Playbooks подгружают этот файл явно из репозитория.
- Секреты можно:
  - хранить в `host_vars`/Ansible Vault,
  - либо не задавать вовсе, тогда первый `deploy.yml` сгенерирует их и сохранит в удалённый `.env`.

## Быстрый старт

1. Установить Ansible на контроллер.
2. Скопировать `host_vars/vpn-prod.yml.example` в `host_vars/vpn-prod.yml` и подставить реальный хост.
3. При необходимости поправить `group_vars/vpn.yml`.
4. Выполнить:

```sh
cd ansible
ansible-playbook playbooks/provision.yml -l vpn-prod
ansible-playbook playbooks/deploy.yml -l vpn-prod
```

## Замечания

- `deploy.yml` сознательно переиспользует существующие `scripts/render-config.sh`, `scripts/validate.sh` и `scripts/doctor.sh`, чтобы не дублировать application-specific логику.
- Повторный запуск `deploy.yml` не должен ротировать секреты, если они уже есть в inventory или в удалённом `.env`.
- Для контролируемой ротации секретов задай новые значения в inventory и повторно выполни `deploy.yml`.
- `xray_manage_firewall: true` работает в additive-режиме: роль только добавляет allow rules для SSH/VPN и не берёт весь `ufw` под полное управление.
- Если `ufw` сейчас выключен, playbook не будет включать его сам. Это сделано специально для безопасной миграции с уже существующего сервера.
