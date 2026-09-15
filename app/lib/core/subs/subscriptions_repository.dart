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
  /// Возвращает число добавленных каналов.
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
}
