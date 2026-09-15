"""AlterTube backend alpha — Flask-компаньон.
Не прокси YouTube API (его нет во форке), а:
- кэш SponsorBlock (экономим запросы, privacy)
- заглушка sync подписок
- health для CI
"""
import time
import requests
from flask import Flask, jsonify, request
from flask_cors import CORS

app = Flask(__name__)
CORS(app)

_SB_CACHE: dict[str, tuple[float, object]] = {}
_SB_TTL = 60 * 30
SB_UPSTREAM = "https://sponsor.ajay.app"

@app.get("/health")
def health():
    return jsonify(ok=True, service="altertube-backend", version="0.1.0")

@app.get("/sb/skipSegments")
def sb_proxy():
    video_id = request.args.get("videoID", "")
    categories = request.args.get("categories", '["sponsor"]')
    if not video_id:
        return jsonify(error="videoID required"), 400
    key = f"{video_id}:{categories}"
    now = time.time()
    if key in _SB_CACHE and now - _SB_CACHE[key][0] < _SB_TTL:
        return jsonify(_SB_CACHE[key][1])
    r = requests.get(
        f"{SB_UPSTREAM}/api/skipSegments",
        params={"videoID": video_id, "categories": categories, "actionTypes": '["skip"]'},
        timeout=10,
    )
    if r.status_code == 404:
        return jsonify([])
    if r.status_code != 200:
        return jsonify(error="upstream"), 502
    data = r.json()
    _SB_CACHE[key] = (now, data)
    return jsonify(data)

# Заглушка под beta: хранение подписок в памяти. Позже — файл/БД.
_SUBS: set[str] = set()

@app.get("/subs")
def subs_list():
    return jsonify(sorted(_SUBS))

@app.post("/subs")
def subs_add():
    body = request.get_json(force=True, silent=True) or {}
    cid = body.get("channelId", "")
    if cid:
        _SUBS.add(cid)
    return jsonify(ok=True, count=len(_SUBS))

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
