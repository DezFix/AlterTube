# AlterTube — beta 0.2.0 (план 2: свой UI + чужой экстрактор)

![Build debug APK](https://github.com/DezFix/AlterTube/actions/workflows/build.yml/badge.svg)

Минималистичный YouTube-клиент: отдельно **Видео**, отдельно **Shorts**, отдельно **Подписки**.
Dart/Flutter — приложение, Python — сборка (`tools/build.py`), Flask — компаньон (кэш SponsorBlock).

Готовый APK: вкладка Actions → последний успешный `Build debug APK` → артефакт `altertube-debug`.
Сборка идёт в облаке GitHub Actions, локально собирать не нужно.

> ⚠️ Дисклеймер: это форк-подход (как NewPipe / PipePipe). Используется reverse-engineered экстрактор,
> а не официальный YouTube Data API. Это нарушает YouTube ToS: возможны поломки при изменениях
> YouTube (SABR-шифрование и т.п.), IP-баны, бан cookie-аккаунта. Нет публикации в Play Market —
> только GitHub Releases / F-Droid. Рекламы нет по дизайну (прямые потоки в своем плеере).

## Upstream / благодарности
- NewPipe + NewPipeExtractor (GPL-3.0) — идея и протокол извлечения
- PipePipe (GPL-3.0) — SABR-исследование, SponsorBlock-интеграция как референс
- SponsorBlock `sponsor.ajay.app` — пропуск спонсорских сегментов
- `newpipeextractor_dart` — Flutter-обертка экстрактора (Android-only)

Форк обязан оставаться под **GPL-3.0**, см. `LICENSE`.

## Структура
```
app/lib/
  main.dart app.dart
  core/extractor/extractor_service.dart   # trending/search/resolveStreamUrl (alpha: mock, alpha2: реальный extractor)
  core/sponsorblock/sponsorblock_service.dart
  core/subs/subscriptions_repository.dart # локальные подписки без Google-входа
  features/videos/ shorts/ subs/ player/
backend/app.py         # Flask: /health /sb/skipSegments (кэш 30 мин) /subs
tools/build.py         # check | run | apk | backend | takeout
tools/parse_takeout.py # Takeout subscriptions.json -> app_subs.json
```

## Быстрый старт
```bash
python tools/build.py check
# 1. Установи Flutter SDK, затем:
cd app && flutter pub get && flutter run
# 2. Backend (опционально, кэш SponsorBlock):
python tools/build.py backend
# 3. Импорт подписок из Google Takeout:
python tools/build.py takeout --in subscriptions.json --out app_subs.json
```

## Что работает в beta 0.2.0
- 3 таба + живой поиск, меню ⋮ → Настройки (тема, регион, SponsorBlock, backend)
- Видео-лента (тренды), Shorts PageView, Подписки (добавление по ссылке, лента)
- Плеер на прямых потоках + SponsorBlock auto-skip + похожие видео
- Flask `/sb/skipSegments` с кэшем, `/health`

## Известный фикс: краш на Android <13
NewPipeExtractor v0.26.5 вызывает `URLEncoder.encode(String, Charset)` (есть только с API 33).
Upstream-фикс (PR #1458) в релизах отсутствует, поэтому:
- `tools/patch_extractor.py` собирает `app/libs/NewPipeExtractor-v0.26.5-altertube.jar`
  (3 метода переписаны на API-1 варианты, происхождение задокументировано в скрипте),
- `app/android/app/build.gradle.kts` исключает оригинальный транзитивный артефакт.
При обновлении экстрактора: обновить тег в скрипте, пересобрать jar, закоммитить.

## Следующее
- ExoPlayer/media3, фон, загрузки, группы подписок, ReturnDislike
- Автообновление экстрактора при поломках YouTube
