# setup-bot

```shell
curl -sL https://raw.githubusercontent.com/ang3el7z/setup-bot/master/install | sudo bash
```

## Параметры (cron, одна команда)

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
| `-h`, `--help` | Справка |
