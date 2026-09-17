import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

// Локальные подписки без Google-входа (как NewPipe/PipePipe).
// Новый формат: base64url(json([id, name, url])) — переживает '|' и ',' в названиях.
// Старый 'id|name|url' читается для совместимости и мигрирует при записи.

class Sub {
  final String id;
  final String name;
  final String url;
  const Sub({required this.id, required this.name, required this.url});

  String get channelUrl =>
      url.isNotEmpty ? url : 'https://www.youtube.com/channel/$id';

  String encode() {
    final raw = jsonEncode([id, name, url]);
    return 'j:${base64Url.encode(utf8.encode(raw))}';
  }

  static Sub? decode(String raw) {
    if (raw.startsWith('j:')) {
      try {
        final parts = jsonDecode(
            utf8.decode(base64Url.decode(raw.substring(2)))) as List;
        final id = parts.isNotEmpty ? '${parts[0]}' : '';
        if (id.isEmpty) return null;
        return Sub(
          id: id,
          name: parts.length > 1 ? '${parts[1]}' : id,
          url: parts.length > 2 ? '${parts[2]}' : '',
        );
      } catch (_) {
        return null;
      }
    }
    // Legacy 'id|name|url': id до первого '|', url — последний сегмент,
    // всё между — имя (в нём мог быть '|').
    final first = raw.indexOf('|');
    if (first <= 0) return null;
    final last = raw.lastIndexOf('|');
    if (last == first) {
      return Sub(
          id: raw.substring(0, first),
          name: raw.substring(first + 1),
          url: '');
    }
    return Sub(
      id: raw.substring(0, first),
      name: raw.substring(first + 1, last),
      url: raw.substring(last + 1),
    );
  }
}

class SubscriptionsRepository {
  static const _k = 'altertube_subs_v1';

  Future<List<Sub>> load() async {
    final p = await SharedPreferences.getInstance();
    return (p.getStringList(_k) ?? [])
        .map(Sub.decode)
        .whereType<Sub>()
        .toList();
  }

  Future<bool> isSub(String channelId) async {
    final all = await load();
    return all.any((s) => s.id == channelId);
  }

  Future<void> subscribe(String channelId, String name, String url) async {
    final p = await SharedPreferences.getInstance();
    final cur = (p.getStringList(_k) ?? [])
        .map(Sub.decode)
        .whereType<Sub>()
        .where((e) => e.id != channelId)
        .map((e) => e.encode())
        .toList()
      ..add(Sub(id: channelId, name: name, url: url).encode());
    await p.setStringList(_k, cur);
  }

  Future<void> unsubscribe(String channelId) async {
    final p = await SharedPreferences.getInstance();
    final cur = (p.getStringList(_k) ?? [])
        .map(Sub.decode)
        .whereType<Sub>()
        .where((e) => e.id != channelId)
        .map((e) => e.encode())
        .toList();
    await p.setStringList(_k, cur);
  }

  Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_k);
  }

  /// Импорт из вставленного Takeout-JSON (тот же формат, что ест tools/parse_takeout.py).
  Future<int> importTakeoutJson(String text) async {
    final data = jsonDecode(text);
    final items = data is List ? data : (data['items'] ?? []);
    int n = 0;
    for (final e in items) {
      final sn = (e['snippet'] ?? e) as Map;
      final rid = (sn['resourceId'] ?? {}) as Map;
      final cid = (rid['channelId'] ?? sn['channelId'] ?? e['channelId'] ?? '').toString();
      final title = (sn['title'] ?? cid).toString();
      if (cid.isEmpty) continue;
      if (!await isSub(cid)) {
        await subscribe(cid, title, 'https://www.youtube.com/channel/$cid');
        n++;
      }
    }
    return n;
  }

  /// Импорт из NewPipe-экспорта:
  /// {"app_version":"...","app_version_int":N,"subscriptions":
  ///  [{"service_id":0,"url":"https://www.youtube.com/channel/UC...","name":"..."}]}
  /// service_id 0 = YouTube, остальные пропускаем.
  Future<int> importNewPipeJson(String text) async {
    final data = jsonDecode(text);
    final items = (data is Map ? data['subscriptions'] : data) as List? ?? [];
    int n = 0;
    for (final e in items) {
      final m = e as Map;
      if ((m['service_id'] ?? 0) != 0) continue; // только YouTube
      final url = (m['url'] ?? '').toString().trim();
      final name = (m['name'] ?? url).toString();
      if (url.isEmpty) continue;
      final id = _idFromChannelUrl(url);
      if (id.isEmpty) continue;
      if (!await isSub(id)) {
        await subscribe(id, name, url);
        n++;
      }
    }
    return n;
  }

  /// Импорт из YouTube-CSV (Takeout): "Channel Id,Channel Url,Channel Title".
  /// Также ест plain-список: по одной ссылке/UC-id/@handle на строку.
  /// CSV разбирается с учётом кавычек: "UC...,https://...,\"Name, with comma\"".
  Future<int> importCsv(String text) async {
    int n = 0;
    for (var line in text.split('\n')) {
      line = line.trim().replaceAll('\r', '');
      if (line.isEmpty || line.startsWith('Channel Id')) continue;
      String url = '';
      String name = '';
      if (line.contains(',')) {
        final parts = _splitCsv(line);
        if (parts.length >= 2 && parts[1].contains('http')) {
          url = parts[1].trim();
          name = parts.length >= 3 ? parts.sublist(2).join(',').trim() : url;
        }
      }
      url = url.isEmpty ? line : url;
      if (!url.contains('http') && !url.startsWith('UC') && !url.startsWith('@')) {
        continue;
      }
      final full = url.startsWith('http')
          ? url
          : url.startsWith('UC')
              ? 'https://www.youtube.com/channel/$url'
              : 'https://www.youtube.com/$url';
      final id = _idFromChannelUrl(full);
      if (id.isEmpty) continue;
      if (!await isSub(id)) {
        await subscribe(id, name.isEmpty ? id : name, full);
        n++;
      }
    }
    return n;
  }

  /// Умный импорт: сам определяет формат (NewPipe / Takeout / CSV / список).
  Future<(int count, String format)> importSmart(String text) async {
    final t = text.trim();
    if (t.startsWith('{') && t.contains('"subscriptions"')) {
      return (await importNewPipeJson(t), 'NewPipe');
    }
    if (t.startsWith('[') || t.contains('"snippet"') || t.contains('"kind"')) {
      return (await importTakeoutJson(t), 'Takeout');
    }
    return (await importCsv(t), 'CSV/список');
  }

  /// Пакетный импорт готовых (name, url) — например, разобранных нативным
  /// экстрактором из файла. Одна запись в prefs вместо N. Возвращает
  /// число реально добавленных (дубли и мусор пропускаются).
  Future<int> importItems(List<({String name, String url})> items) async {
    final p = await SharedPreferences.getInstance();
    final cur = (p.getStringList(_k) ?? [])
        .map(Sub.decode)
        .whereType<Sub>()
        .toList();
    final have = cur.map((e) => e.id).toSet();
    var n = 0;
    for (final e in items) {
      final url = e.url.trim();
      if (url.isEmpty) continue;
      var id = _idFromChannelUrl(url);
      id = id.isEmpty ? url : id;
      if (have.contains(id)) continue;
      final name = e.name.trim().isEmpty ? id : e.name.trim();
      cur.add(Sub(id: id, name: name, url: url));
      have.add(id);
      n++;
    }
    await p.setStringList(_k, cur.map((e) => e.encode()).toList());
    return n;
  }

  /// Экспорт в формате NewPipe — такой файл съедят NewPipe, PipePipe и мы.
  Future<String> exportNewPipeJson() async {
    final all = await load();
    return jsonEncode({
      'app_version': '0.4.0',
      'app_version_int': 4,
      'subscriptions': [
        for (final s in all)
          {'service_id': 0, 'url': s.channelUrl, 'name': s.name},
      ],
    });
  }

  static const _cookieDateKey = 'altertube_cookie_date';

  Future<String?> cookieDate() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_cookieDateKey);
  }

  Future<void> setCookieDate(String v) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_cookieDateKey, v);
  }

  static String _idFromChannelUrl(String url) {
    final m = RegExp(r'youtube\.com/(?:channel/|@|c/|user/)([\w@.-]+)').firstMatch(url);
    if (m != null) return m.group(1)!;
    if (RegExp(r'^UC[\w-]{10,}$').hasMatch(url)) return url;
    return '';
  }

  /// Мини CSV-сплиттер с поддержкой "..." (удвоенные кавычки = одна кавычка).
  static List<String> _splitCsv(String line) {
    final out = <String>[];
    final buf = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          buf.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (ch == ',' && !inQuotes) {
        out.add(buf.toString());
        buf.clear();
      } else {
        buf.write(ch);
      }
    }
    out.add(buf.toString());
    return out.map((e) {
      var s = e.trim();
      if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
        s = s.substring(1, s.length - 1).replaceAll('""', '"');
      }
      return s;
    }).toList();
  }
}
