#!/usr/bin/env python3
"""Сборка пропатченного NewPipeExtractor для Android <13.

Проблема: NewPipeExtractor v0.26.5 вызывает URLEncoder.encode(String, Charset)
и URLDecoder.decode(String, Charset) — эти перегрузки есть только с API 33
(Android 13). На Android <=12 любой поиск/открытие видео крашится с
NoSuchMethodError (см. upstream PR #1458, релиза с фиксом пока нет).

Что делает скрипт:
  1. Находит оригинальный NewPipeExtractor-v0.26.5.jar в Gradle-кэше.
  2. Скачивает Utils.java тега v0.26.5, меняет 3 метода на String-варианты
     (URLEncoder.encode(s, "UTF-8") и т.п. — работает с API 1).
  3. Компилирует один Utils.java через javac и подменяет Utils*.class
     в копии jar -> app/libs/NewPipeExtractor-v0.26.5-altertube.jar.
  4. app/android/app/build.gradle.kts исключает оригинальный транзитивный
     артефакт и подключает пропатченный jar (см. README ниже).

Использование:
  python tools/patch_extractor.py [--tag v0.26.5] [--out app/libs/...jar]
Переменные окружения: JAVA_HOME (javac), GRADLE_USER_HOME (иначе .gradle в корне).
"""
import argparse
import os
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GROUP_PATH = Path("com/github/teamnewpipe/NewPipeExtractor")

PATCHES = [
    # encodeUrlUtf8: Charset-перегрузка (API 33+) -> String-вариант (API 1+)
    (
        "    public static String encodeUrlUtf8(final String string) {\n"
        "        return URLEncoder.encode(string, StandardCharsets.UTF_8);\n"
        "    }",
        "    public static String encodeUrlUtf8(final String string) {\n"
        "        try {\n"
        '            return URLEncoder.encode(string, StandardCharsets.UTF_8.name());\n'
        "        } catch (final Exception e) {\n"
        "            return string;\n"
        "        }\n"
        "    }",
    ),
    # decodeUrlUtf8: то же самое
    (
        "    public static String decodeUrlUtf8(final String url) {\n"
        "        return URLDecoder.decode(url, StandardCharsets.UTF_8);\n"
        "    }",
        "    public static String decodeUrlUtf8(final String url) {\n"
        "        try {\n"
        '            return URLDecoder.decode(url, StandardCharsets.UTF_8.name());\n'
        "        } catch (final Exception e) {\n"
        "            return url;\n"
        "        }\n"
        "    }",
    ),
    # isBlank: String.isBlank() существует только с API 29 -> trim().isEmpty()
    (
        "    public static boolean isBlank(final String string) {\n"
        "        return string == null || string.isBlank();\n"
        "    }",
        "    public static boolean isBlank(final String string) {\n"
        "        return string == null || string.trim().isEmpty();\n"
        "    }",
    ),
]


def download(url: str, dest: Path) -> Path:
    print(f"download: {url}")
    req = urllib.request.Request(url, headers={"User-Agent": "AlterTube-patch/1.0"})
    dest.parent.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(req, timeout=300) as r, open(dest, "wb") as f:
        shutil.copyfileobj(r, f)
    print(f"saved {dest} ({dest.stat().st_size // 1024} KB)")
    return dest


def ensure_base_jars(tag: str, work: Path) -> tuple[Path, str]:
    """Возвращает (extractor.jar, classpath). Сначала ищет в Gradle-кэше,
    иначе качает оригинал с JitPack + jsr305 с Maven Central."""
    ver = tag.lstrip("v")
    try:
        orig, gradle_home = find_original_jar(tag)
        print(f"original (cache): {orig}")
        return orig, f"{orig}{os.pathsep}{dep_classpath(gradle_home)}"
    except SystemExit:
        print("В кэше нет — качаю оригинал с JitPack")
    ext = download(
        f"https://jitpack.io/com/github/teamnewpipe/NewPipeExtractor/v{ver}/NewPipeExtractor-v{ver}.jar",
        work / f"NewPipeExtractor-v{ver}.jar",
    )
    jsr = download(
        "https://repo1.maven.org/maven2/com/google/code/findbugs/jsr305/3.0.2/jsr305-3.0.2.jar",
        work / "jsr305-3.0.2.jar",
    )
    return ext, f"{ext}{os.pathsep}{jsr}"


def find_original_jar(tag: str) -> tuple[Path, Path]:
    """Возвращает (jar, gradle_home)."""
    homes = []
    if os.environ.get("GRADLE_USER_HOME"):
        homes.append(Path(os.environ["GRADLE_USER_HOME"]))
    homes.append(ROOT / ".gradle")
    homes.append(Path.home() / ".gradle")
    for home in homes:
        base = home / "caches" / "modules-2" / "files-2.1" / GROUP_PATH
        if not base.is_dir():
            continue
        for jar in sorted(base.rglob(f"NewPipeExtractor-{tag.lstrip('v')}.jar")):
            if "sources" in jar.name or "javadoc" in jar.name:
                continue
            return jar, home
    raise SystemExit(f"Не найден NewPipeExtractor {tag} в Gradle-кэше. Сначала запусти сборку/gradle resolve.")


def find_javac() -> str:
    java_home = os.environ.get("JAVA_HOME")
    if java_home:
        cand = str(Path(java_home) / "bin" / ("javac.exe" if os.name == "nt" else "javac"))
        if Path(cand).exists():
            return cand
    found = shutil.which("javac")
    if found:
        return found
    raise SystemExit("javac не найден. Укажи JAVA_HOME.")


def dep_classpath(home: Path) -> str:
    jars = []
    mods = home / "caches" / "modules-2" / "files-2.1"
    for jar in mods.rglob("*.jar"):
        name = jar.name
        if "sources" in name or "javadoc" in name:
            continue
        jars.append(str(jar))
    return os.pathsep.join(sorted(set(jars)))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", default="v0.26.5")
    ap.add_argument("--out", default=str(ROOT / "app" / "libs" / "NewPipeExtractor-v0.26.5-altertube.jar"))
    a = ap.parse_args()

    base_dir = ROOT / ".tools" / "npe-base"  # кэш скачанного оригинала (в .gitignore)
    orig, cp = ensure_base_jars(a.tag, base_dir)
    print(f"original: {orig}")

    url = (
        f"https://raw.githubusercontent.com/TeamNewPipe/NewPipeExtractor/"
        f"{a.tag}/extractor/src/main/java/org/schabi/newpipe/extractor/utils/Utils.java"
    )
    print(f"download: {url}")
    src = urllib.request.urlopen(url, timeout=120).read().decode("utf-8")
    for old, new in PATCHES:
        if old not in src:
            raise SystemExit("Патч не применился: исходник Utils.java отличается от ожидаемого. Обнови PATCHES.")
        src = src.replace(old, new)
    print("patched: encodeUrlUtf8, decodeUrlUtf8, isBlank")

    with tempfile.TemporaryDirectory() as tmp:
        tmp_p = Path(tmp)
        src_dir = tmp_p / "src" / "org" / "schabi" / "newpipe" / "extractor" / "utils"
        src_dir.mkdir(parents=True)
        (src_dir / "Utils.java").write_text(src, encoding="utf-8")
        out_classes = tmp_p / "classes"
        out_classes.mkdir()
        javac = find_javac()
        print(f"javac: {javac}")
        r = subprocess.run(
            [javac, "--release", "8", "-nowarn", "-cp", cp,
             "-d", str(out_classes), str(src_dir / "Utils.java")],
            capture_output=True, text=True,
        )
        if r.returncode != 0:
            print(r.stdout[-3000:])
            print(r.stderr[-3000:])
            raise SystemExit("javac упал")
        compiled = sorted((out_classes / "org/schabi/newpipe/extractor/utils").glob("Utils*.class"))
        print(f"compiled: {[c.name for c in compiled]}")
        if not compiled:
            raise SystemExit("Нет class-файлов после компиляции")

        out_jar = Path(a.out)
        out_jar.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(orig, "r") as zin, zipfile.ZipFile(out_jar, "w", zipfile.ZIP_DEFLATED) as zout:
            replaced = set()
            for item in zin.infolist():
                if item.filename.startswith("org/schabi/newpipe/extractor/utils/Utils") and item.filename.endswith(".class"):
                    local = out_classes / item.filename
                    if local.exists():
                        zout.writestr(item, local.read_bytes())
                        replaced.add(item.filename)
                        continue
                zout.writestr(item, zin.read(item.filename))
        print(f"wrote {out_jar} ({out_jar.stat().st_size // 1024} KB), replaced: {sorted(replaced)}")

    # проверка: в новом jar не должно быть ссылок на Charset-перегрузки из Utils
    with zipfile.ZipFile(out_jar) as z:
        blob = b"".join(z.read(n) for n in z.namelist() if n.endswith("Utils.class"))
    assert b"encodeUrlUtf8" in blob
    print("OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
