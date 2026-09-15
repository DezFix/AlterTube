#!/usr/bin/env python3
"""Парсер Google Takeout -> формат AlterTube или NewPipe.
Вход: subscriptions.json из https://takeout.google.com (YouTube -> subscriptions).
Формат входа: [{"snippet": {"resourceId": {"channelId": "..."}, "title": "..."}}]
--to altertube (по умолчанию): [{"channelId": "...", "title": "..."}]
--to newpipe: {"app_version": "...", "app_version_int": N, "subscriptions":
  [{"service_id": 0, "url": "https://www.youtube.com/channel/...", "name": "..."}]}
Использование: python tools/parse_takeout.py subscriptions.json app_subs.json [--to altertube|newpipe]
"""
import json
import sys
from pathlib import Path

def main(inp: str, out: str, to: str = "altertube") -> int:
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
    if to == "newpipe":
        payload = {
            "app_version": "0.28.5",
            "app_version_int": 1010,
            "subscriptions": [
                {"service_id": 0,
                 "url": f"https://www.youtube.com/channel/{r['channelId']}",
                 "name": r["title"]}
                for r in uniq
            ],
        }
    else:
        payload = uniq
    Path(out).write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"OK: {len(uniq)} channels ({to}) -> {out}")
    return 0

if __name__ == "__main__":
    to = "altertube"
    positional = []
    argv = sys.argv[1:]
    i = 0
    while i < len(argv):
        if argv[i] == "--to" and i + 1 < len(argv):
            to = argv[i + 1]
            i += 2
        elif argv[i].startswith("--to="):
            to = argv[i].split("=", 1)[1]
            i += 1
        else:
            positional.append(argv[i])
            i += 1
    if len(positional) != 2 or to not in ("altertube", "newpipe"):
        print(__doc__)
        raise SystemExit(2)
    raise SystemExit(main(positional[0], positional[1], to))
