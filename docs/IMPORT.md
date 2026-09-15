# Перенос подписок в AlterTube

AlterTube хранит подписки локально, без Google-входа (как NewPipe).
Импорт — во вкладке **Подписки → «+ Добавить»**: вставь текст файла целиком,
формат определяется сам. Что поддерживается:

## 1. NewPipe-экспорт (рекомендуется — 1 в 1 как в NewPipe)

Формат:
```json
{"app_version":"0.28.5","app_version_int":1010,"subscriptions":[
  {"service_id":0,"url":"https://www.youtube.com/channel/UC...","name":"Канал"}
]}
```
`service_id: 0` = YouTube (остальные пропускаем).

Как выгрузить из NewPipe:
1. Открой NewPipe → вкладка **Подписки**.
2. Меню **⋮ → Экспорт в → файл** (JSON).
3. Открой файл текстовым редактором, скопируй всё и вставь в AlterTube.

## 2. Google Takeout

1. https://takeout.google.com/takeout/custom/youtube → только **subscriptions** → создать экспорт.
2. Из zip достань `YouTube и YouTube Music/subscriptions/subscriptions.json`.
3. Вставь в AlterTube — или конвертни скриптом:
   `python tools/parse_takeout.py subs.json app_subs.json [--to altertube|newpipe]`
   (`--to newpipe` выдаст файл, который съест и NewPipe, и AlterTube).

## 3. YouTube CSV / простой список

- CSV из Takeout (`Channel Id,Channel Url,Channel Title`) — вставляется как есть.
- Или просто ссылки/UC-id/@handle — по одной на строку.

## Ограничения (как у NewPipe)

- Каналы-«топики» без видеоленты могут давать пустую выдачу.
- Лента опрашивает каналы последовательно с паузами, чтобы не словить 429.
