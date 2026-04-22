# Ansible Workflow

Этот каталог добавляет reproducible provisioning/deploy слой поверх существующих shell-скриптов проекта.

## Что делает Ansible

- `playbooks/provision.yml` приводит Ubuntu/Debian VPS в нужное базовое состояние:
  - ставит базовые пакеты,
  - настраивает Docker Engine и Compose plugin,
  - добавляет `ufw` allow rules для SSH и Xray, не меняя default policy и не включая firewall автоматически.
- `playbooks/deploy.yml` раскладывает проект на удалённый хост, управляет `.env`, сохраняет существующие секреты или генерирует новые на первом запуске, рендерит Xray-конфиг и выполняет deploy/verify flow.

## Ожидаемая модель эксплуатации

- Канонический источник inventory defaults: `ansible/inventory/group_vars/*.yml`.
- Канонический источник host overrides: `ansible/inventory/host_vars/<host>.yml`.
- Канонический источник production secrets: `ansible/inventory/host_vars/<host>.vault.yml`, зашифрованный через `ansible-vault`.
- Секреты можно:
  - хранить в `*.vault.yml`,
  - либо не задавать вовсе, тогда первый `deploy.yml` сгенерирует их и сохранит в удалённый `.env`.

### Precedence

1. `ansible/inventory/group_vars/*.yml` задаёт defaults.
2. `ansible/inventory/host_vars/<host>.yml` переопределяет defaults.
3. `ansible/inventory/host_vars/<host>.vault.yml` переопределяет secrets и чувствительные overrides.
4. `deploy.yml` рендерит итоговый удалённый `.env`.
5. `compose.yaml` и `scripts/*` только читают итоговый `.env` и не являются источником конфигурации.

## Быстрый старт

1. Установить Ansible на контроллер.
2. Скопировать `inventory/host_vars/vpn-prod.yml.example` в `inventory/host_vars/vpn-prod.yml` и подставить реальный хост.
3. При необходимости создать `inventory/host_vars/vpn-prod.vault.yml` из шаблона и зашифровать его через `ansible-vault`.
4. При необходимости поправить `inventory/group_vars/vpn.yml`.
5. Выполнить:

```sh
cd ansible
ansible-playbook playbooks/provision.yml -l vpn-prod --ask-vault-pass
ansible-playbook playbooks/deploy.yml -l vpn-prod --ask-vault-pass
```

## Замечания

- `deploy.yml` сознательно переиспользует существующие `scripts/render-config.sh`, `scripts/validate.sh` и `scripts/doctor.sh`, чтобы не дублировать application-specific логику.
- Повторный запуск `deploy.yml` не должен ротировать секреты, если они уже есть в `*.vault.yml` или в удалённом `.env`.
- Для контролируемой ротации секретов задай новые значения в `*.vault.yml` и повторно выполни `deploy.yml`.
- `xray_manage_firewall: true` работает в additive-режиме: роль только добавляет allow rules для SSH/VPN и не берёт весь `ufw` под полное управление.
- Если `ufw` сейчас выключен, playbook не будет включать его сам. Это сделано специально для безопасной миграции с уже существующего сервера.
- `deploy.yml --check` теперь дружелюбнее: файловые и template-задачи оцениваются, а runtime-команды `docker compose`, рендер клиентских артефактов, validate/doctor и генерация секретов пропускаются.

## Vault Workflow

Обычный путь для production:

```sh
cp inventory/host_vars/vpn-prod.vault.yml.example inventory/host_vars/vpn-prod.vault.yml
ansible-vault encrypt inventory/host_vars/vpn-prod.vault.yml
ansible-vault edit inventory/host_vars/vpn-prod.vault.yml
```

Если не хочешь вводить vault password каждый запуск, используй локальный файл:

```sh
printf '%s\n' 'your-vault-password' > .vault_pass.txt
chmod 600 .vault_pass.txt
ansible-playbook playbooks/deploy.yml -l vpn-prod --vault-password-file .vault_pass.txt
```

## Secret Rotation

Контролируемая ротация делается так:

1. Обновить нужные значения в `inventory/host_vars/<host>.vault.yml`.
2. Выполнить `deploy.yml`.
3. Забрать новые client artifacts и переимпортировать VLESS URI/SOCKS credentials на клиентах.

Какие значения считаются ротационными:

- `xray_client_uuid`
- `xray_reality_private_key`
- `xray_reality_short_id`
- `xray_telegram_socks_user`
- `xray_telegram_socks_pass`

## SSH Access Hardening

Рекомендуемый steady-state путь:

- использовать `ansible_ssh_private_key_file`, а не password-based SSH;
- держать `ansible_user` как non-root deploy user с `become: true`;
- отключать SSH password auth на VPS только после проверки входа по ключу;
- для нового deploy user включать `xray_manage_deploy_user: true` и передавать `xray_deploy_user_authorized_keys`.

Минимальный пример plain host vars для key-only доступа:

```yml
ansible_host: 198.51.100.10
ansible_user: xray-deploy
ansible_ssh_private_key_file: ~/.ssh/vpn-prod_ed25519
ansible_become: true
xray_manage_deploy_user: true
xray_deploy_user_name: xray-deploy
xray_deploy_user_authorized_keys:
  - "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA..."
```
