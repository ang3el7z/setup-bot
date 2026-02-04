# mbt

```shell
curl -sL https://raw.githubusercontent.com/ang3el7z/mbt/master/install | sudo bash
```

Параметры передаются в `mbt`: добавь `-s --` после `bash` и укажи команду:

```shell
curl -sL https://raw.githubusercontent.com/ang3el7z/mbt/master/install | sudo bash -s -- -all
```

После установки можно вызывать `mbt` напрямую: интерактивное меню — просто `mbt`, нужная команда — `mbt` и параметр, например `mbt -bbr`, `mbt -all`.

## Параметры

| Параметр | Описание |
|----------|----------|
| `-r`, `-restart` | Перезапуск бота (make r) |
| `-s`, `-swap` | Создать и включить swap (1.5 GB) |
| `-suc`, `-stop-unwanted-containers` | Остановить ненужные Docker-контейнеры |
| `-crontab-r`, `-crontab-reboot` | Добавить в crontab автоперезапуск бота при загрузке |
| `-crontab-suc`, `-crontab-stop-unwanted-containers` | Добавить в crontab остановку контейнеров после загрузки |
| `-bbr` | Подменю BBR (вкл/выкл) |
| `-ipv6` | Подменю IPv6 (вкл/выкл) |
| `-f2b`, `-fail2ban` | Подменю Fail2ban (защита SSH) |
| `-tz`, `-timezone` | Выбор часового пояса (TZ в override.env для бота) |
| `-sub` | Подписка: mbt_verify_user.php + правки в bot.php (если нет) |
| `-all` | Все в одном (swap, контейнеры, crontab, BBR, IPv6 выкл, Fail2ban) |
| `-h`, `--help` | Справка |
