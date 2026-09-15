import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

// Локальные подписки без Google-входа (как NewPipe/PipePipe).
// Формат записи: channelId|name|channelUrl (url может быть пустым у старых записей).

class Sub {
  final String id;
  final String name;
  final String url;
  const Sub({required this.id, required this.name, required this.url});

  String get channelUrl =>
      url.isNotEmpty ? url : 'https://www.youtube.com/channel/$id';

  String encode() => '$id|$name|$url';

  static Sub? decode(String raw) {
    final p = raw.split('|');
    if (p.isEmpty || p.first.isEmpty) return null;
    return Sub(id: p[0], name: p.length > 1 ? p[1] : p[0], url: p.length > 2 ? p[2] : '');
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
        .where((e) => !e.startsWith('$channelId|'))
        .toList()
      ..add(Sub(id: channelId, name: name, url: url).encode());
    await p.setStringList(_k, cur);
  }

  Future<void> unsubscribe(String channelId) async {
    final p = await SharedPreferences.getInstance();
    final cur = (p.getStringList(_k) ?? []).where((e) => !e.startsWith('$channelId|')).toList();
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
  Future<int> importCsv(String text) async {
    int n = 0;
    for (var line in text.split('\n')) {
      line = line.trim().replaceAll('\r', '');
      if (line.isEmpty || line.startsWith('Channel Id')) continue;
      String url = '';
      String name = '';
      if (line.contains(',')) {
        final parts = line.split(',');
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

  static String _idFromChannelUrl(String url) {
    final m = RegExp(r'youtube\.com/(?:channel/|@|c/|user/)([\w@.-]+)').firstMatch(url);
    if (m != null) return m.group(1)!;
    if (RegExp(r'^UC[\w-]{10,}$').hasMatch(url)) return url;
    return '';
  }
}
