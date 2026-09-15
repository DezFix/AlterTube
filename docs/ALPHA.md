# AlterTube alpha 0.1.0 — что сделано и как проверить без Flutter

## Сделано
- `app/pubspec.yaml` + `main.dart` + `app.dart` (3 таба)
- `core/extractor` (mock с TODO под реальный extractor), `core/sponsorblock`, `core/subs`
- `features/videos` `shorts` `subs` `player` (SponsorBlock auto-skip)
- `backend/app.py` Flask + `requirements.txt`
- `tools/build.py` + `tools/parse_takeout.py`

## Проверить сейчас (без Flutter)
python tools/build.py check
python -m py_compile tools/build.py tools/parse_takeout.py backend/app.py
