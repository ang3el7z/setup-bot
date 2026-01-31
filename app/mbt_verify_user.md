# После обновления bot.php

Если обновили `bot.php` из другого источника — верните только 2 места ( `mbt_verify_user.php` не трогать).

## 1) auth() — блок для не‑админа

Заменить:

```
} elseif (!in_array($this->input['from'], $c['admin'])) {
    $this->verifyUser();   // или что там было
    exit;
}
```

на:

```
} elseif (!in_array($this->input['from'], $c['admin'])) {
    if (preg_match('~^/verifySub~', $this->input['callback'] ?? '')) {
        return;
    }
    require_once __DIR__ . '/mbt_verify_user.php';
    mbt_verify_user_show($this);
    exit;
}
```

## 2) action() — switch (true)

Добавить **первым** `case` (перед `/menu` и т.д.):

```
case preg_match('~^/verifySub(?:\s+(?P<arg>.+))?$~', $this->input['callback'], $m):
    require_once __DIR__ . '/mbt_verify_user.php';
    mbt_verify_user_callback($this, $m['arg'] ?? 'list');
    break;
```

## 3) Превью ссылок

Если нужно отключить превью ссылок глобально, раскомментируйте строку в `send()`:

```
'disable_web_page_preview' => true,
```

Файл `app/mbt_verify_user.php` — вся логика подписки; его при обновлении `bot.php` не перезаписывают.
