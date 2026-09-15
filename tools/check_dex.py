#!/usr/bin/env python3
"""Проверка: переписал ли D8 вызов URLEncoder.encode(String, Charset) в j$-дешугаринг.
Использование: python tools/check_dex.py dist/app-debug.apk
Код выхода 0 — вызов переписан (или отсутствует), 1 — остался сырой вызов в framework-класс.
"""
import sys
import zipfile

DOLLAR = chr(36)  # '$' без проблем с экранированием в шелле

def main(apk: str) -> int:
    z = zipfile.ZipFile(apk)
    bad = []
    good = []
    for name in sorted(z.namelist()):
        if not name.endswith(".dex"):
            continue
        raw = z.read(name)
        has_utils = b"encodeUrlUtf8" in raw
        has_charset = b"charset/Charset" in raw
        has_std = b"StandardCharsets" in raw
        jdollar_any = ("j" + DOLLAR + "/").encode() in raw
        n_url = raw.count(b"URLEncoder")
        print(f"{name}: encodeUrlUtf8={has_utils} charset={has_charset} std={has_std} any_j$={jdollar_any} urlencoder_n={n_url}")
        if has_utils:
            bad.append(name)
        if ("j" + DOLLAR + "/net/URLEncoder").encode() in raw:
            good.append(name)
    if bad and not good:
        print("ИТОГ: сырой вызов URLEncoder.encode(String, Charset) НЕ переписан -> краш на Android <13")
        return 1
    print("ИТОГ: ок (вызов переписан дешугарингом или отсутствует)")
    return 0

if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1]))
