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
| `-s`, `-swap` | Подменю Swap (вкл/выкл) (1.5 GB) |
| `-suc`, `-stop-unwanted-containers` + опционально `1` или `2` | Остановить контейнеры по списку. В меню п.3 — также запуск контейнеров (пресет 1 или 2). Примеры: `-suc`, `-suc 1`, `-suc 2`. Без аргумента — пресет 2 |
| `-crontab-r`, `-crontab-reboot` | Добавить в crontab автоперезапуск бота при загрузке |
| `-crontab-suc`, `-crontab-stop-unwanted-containers` + опционально `1` или `2` | Добавить в crontab остановку контейнеров. Примеры: `-crontab-suc`, `-crontab-suc 2`, `-crontab-stop-unwanted-containers 1`. Без аргумента — пресет 2 |
| `-bbr` | Подменю BBR (вкл/выкл) |
| `-ipv6` | Подменю IPv6 (вкл/выкл) |
| `-f2b`, `-fail2ban` | Подменю Fail2ban (защита SSH) |
| `-tz`, `-timezone` | Выбор часового пояса (TZ в override.env для бота) |
| `-sub` | Подписка: mbt_verify_user.php + правки в bot.php (если нет) |
| `-all` [1\|2] | Все в одном. Пресет контейнеров: 1 (с adguard) или 2 (без adguard); по умолчанию 2. Примеры: `-all`, `-all 1`, `-all 2` |
| `-all-not` [1\|2] | Отменить -all. Пресет запуска контейнеров 1 или 2; по умолчанию 2. Примеры: `-all-not`, `-all-not 1` |
| `-h`, `--help` | Справка |

