import 'package:shared_preferences/shared_preferences.dart';

// Локальная история и индекс интересов (без аккаунта).
// affinity: сколько раз смотрели видео каждого канала -> вес для ленты.
// recent: последние 100 videoId (для исключения повторов и пометки "смотрено").

class HistoryRepository {
  static const _aff = 'altertube_affinity_v1'; // StringList "channelUrl|count"
  static const _recent = 'altertube_recent_v1'; // StringList videoId (новые в конце)
  static const _recentMax = 100;

  Future<Map<String, int>> affinity() async {
    final p = await SharedPreferences.getInstance();
    final out = <String, int>{};
    for (final e in p.getStringList(_aff) ?? []) {
      final i = e.lastIndexOf('|');
      if (i <= 0) continue;
      out[e.substring(0, i)] = int.tryParse(e.substring(i + 1)) ?? 0;
    }
    return out;
  }

  Future<Set<String>> recentIds() async {
    final p = await SharedPreferences.getInstance();
    return (p.getStringList(_recent) ?? []).toSet();
  }

  /// Вызывать при открытии видео (fire-and-forget).
  Future<void> recordWatch(String videoId, String channelUrl) async {
    if (videoId.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    final recent = (p.getStringList(_recent) ?? []).where((e) => e != videoId).toList()
      ..add(videoId);
    while (recent.length > _recentMax) {
      recent.removeAt(0);
    }
    await p.setStringList(_recent, recent);
    if (channelUrl.isEmpty) return;
    final aff = await affinity();
    aff[channelUrl] = (aff[channelUrl] ?? 0) + 1;
    await p.setStringList(
        _aff, aff.entries.map((e) => '${e.key}|${e.value}').toList());
  }

  Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_aff);
    await p.remove(_recent);
  }
}
