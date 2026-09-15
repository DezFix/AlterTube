#!/usr/bin/env python3
"""Единая сборка AlterTube (план 2, alpha).
Использование:
  python tools/build.py check        — проверить окружение
  python tools/build.py run --dev    — flutter run (нужен Flutter SDK)
  python tools/build.py apk          — flutter build apk --release
  python tools/build.py backend      — запустить Flask
  python tools/build.py takeout --in subscriptions.json --out app_subs.json
"""
import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "app"

def sh(*cmd: str, cwd: Path = ROOT) -> int:
    print(f"$ {' '.join(cmd)}")
    return subprocess.call(list(cmd), cwd=str(cwd))

def patch_pubcache() -> None:
    """Воркэраунд: flutter_inappwebview_android использует getDefaultProguardFile('proguard-android.txt'),
    который AGP 9 отклоняет. Меняем на proguard-android-optimize.txt в локальном PUB_CACHE.
    Вызывать после каждого `pub get` (иначе свежий кэш затрет патч)."""
    pub_cache = Path(os.environ.get("PUB_CACHE", str(ROOT / ".pub-cache")))
    for gradle in pub_cache.glob("hosted/pub.dev/flutter_inappwebview_android-*/android/build.gradle"):
        try:
            text = gradle.read_text(encoding="utf-8")
        except OSError:
            continue
        fixed = text.replace(
            "getDefaultProguardFile('proguard-android.txt')",
            "getDefaultProguardFile('proguard-android-optimize.txt')",
        )
        if fixed != text:
            gradle.write_text(fixed, encoding="utf-8")
            print(f"patched {gradle.relative_to(ROOT)}")

def check() -> int:
    print(f"ROOT={ROOT}")
    print(f"python={sys.version.split()[0]}")
    for tool in ("flutter", "dart", "adb"):
        print(f"{tool}: {shutil.which(tool) or 'NOT FOUND'}")
    for p in (APP / "pubspec.yaml", ROOT / "backend" / "app.py", ROOT / "tools" / "parse_takeout.py"):
        print(f"{'OK ' if p.exists() else 'MISS'} {p.relative_to(ROOT)}")
    if not shutil.which("flutter"):
        print("\nFlutter не установлен. Скачай с https://docs.flutter.dev/get-started/install/windows")
        print("Затем: flutter doctor, cd app && flutter pub get")
        return 1
    return 0

def main() -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("check")
    p_run = sub.add_parser("run"); p_run.add_argument("--dev", action="store_true")
    sub.add_parser("apk")
    sub.add_parser("backend")
    p_t = sub.add_parser("takeout"); p_t.add_argument("--in", dest="inp", required=True); p_t.add_argument("--out", dest="out", required=True)
    a = ap.parse_args()

    if a.cmd == "check":
        return check()
    if a.cmd == "run":
        rc = sh("flutter", "pub", "get", cwd=APP)
        if rc == 0:
            patch_pubcache()
            rc = sh("flutter", "run", cwd=APP)
        return rc
    if a.cmd == "apk":
        rc = sh("flutter", "pub", "get", cwd=APP)
        if rc == 0:
            patch_pubcache()
            rc = sh("flutter", "build", "apk", "--release", cwd=APP)
        return rc
    if a.cmd == "backend":
        return sh(sys.executable, "-m", "pip", "install", "-r", "requirements.txt", cwd=ROOT / "backend") or \
               sh(sys.executable, "app.py", cwd=ROOT / "backend")
    if a.cmd == "takeout":
        return sh(sys.executable, "tools/parse_takeout.py", a.inp, a.out)
    return 1

if __name__ == "__main__":
    raise SystemExit(main())
