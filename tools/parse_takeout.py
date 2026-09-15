#!/usr/bin/env python3
"""Парсер Google Takeout -> формат AlterTube.
Вход: subscriptions.json из https://takeout.google.com (YouTube -> subscriptions).
Формат входа: [{"snippet": {"resourceId": {"channelId": "..."}, "title": "..."}}]
Выход: [{"channelId": "...", "title": "..."}] — кладется в app через импорт.
Использование: python tools/parse_takeout.py subscriptions.json app_subs.json
"""
import json
import sys
from pathlib import Path

def main(inp: str, out: str) -> int:
    data = json.loads(Path(inp).read_text(encoding="utf-8-sig"))
    items = data if isinstance(data, list) else data.get("items", data)
    res = []
    for e in items:
        sn = e.get("snippet", e)
        rid = (sn.get("resourceId") or {})
        cid = rid.get("channelId") or sn.get("channelId") or e.get("channelId") or ""
        title = sn.get("title") or cid
        if cid:
            res.append({"channelId": cid, "title": title})
    # dedup
    seen, uniq = set(), []
    for r in res:
        if r["channelId"] not in seen:
            seen.add(r["channelId"])
            uniq.append(r)
    Path(out).write_text(json.dumps(uniq, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"OK: {len(uniq)} channels -> {out}")
    return 0

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__)
        raise SystemExit(2)
    raise SystemExit(main(sys.argv[1], sys.argv[2]))
