import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/extractor/extractor_service.dart';
import '../../core/history/history_repository.dart';
import '../../core/settings/app_settings.dart';
import '../../core/subs/subscriptions_repository.dart';
import '../player/player_screen.dart';

// Лента Видео с индексацией под пользователя:
// - без подписок (или с выключенной персонализацией) — чистые тренды;
// - с подписками — сначала свежее с подписанных каналов (вес = affinity:
//   чем чаще смотришь канал, тем выше), затем тренды без дублей.
// Просмотренное (recent) помечается галочкой.

class VideosTab extends StatefulWidget {
  const VideosTab({super.key});
  @override
  State<VideosTab> createState() => _VideosTabState();
}

class _VideosTabState extends State<VideosTab> {
  final ext = ExtractorService();
  final subsRepo = SubscriptionsRepository();
  final histRepo = HistoryRepository();
  final List<VideoItem> items = [];
  dynamic next;
  bool loading = true;
  bool moreLoading = false;
  String? error;
  String feedNote = '';
  Set<String> seen = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final personalized = context.read<AppSettings>().personalizedFeed;
      final subs = await subsRepo.load();
      if (personalized && subs.isNotEmpty) {
        await _loadPersonalized(subs);
      } else {
        final p = await ext.trendingPage(null);
        items
          ..clear()
          ..addAll(p.items);
        next = p.next;
        feedNote = '';
      }
      seen = await histRepo.recentIds();
    } catch (e) {
      error = e.toString();
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _loadPersonalized(List<Sub> subs) async {
    final aff = await histRepo.affinity();
    // Загрузки подписанных каналов (до 8, по 3) — последовательно, вежливо.
    final fromSubs = <VideoItem>[];
    for (final s in subs.take(8)) {
      final up = await ext.channelUploads(s.channelUrl, limit: 3);
      fromSubs.addAll(up);
      await Future.delayed(const Duration(milliseconds: 300));
    }
    fromSubs.sort((a, b) =>
        (aff[b.channelUrl] ?? 0).compareTo(aff[a.channelUrl] ?? 0));
    final p = await ext.trendingPage(null);
    final have = fromSubs.map((v) => v.id).toSet();
    final trend =
        p.items.where((v) => !have.contains(v.id)).toList();
    items
      ..clear()
      ..addAll(fromSubs)
      ..addAll(trend);
    next = p.next;
    feedNote = 'Подобрано по подпискам • ${fromSubs.length}';
  }

  Future<void> _more() async {
    if (moreLoading || next == null) return;
    setState(() => moreLoading = true);
    try {
      final p = await ext.trendingPage(next);
      final have = items.map((v) => v.id).toSet();
      items.addAll(p.items.where((v) => !have.contains(v.id)));
      next = p.next;
    } catch (_) {}
    if (mounted) setState(() => moreLoading = false);
  }

  String _sub(VideoItem v) {
    final parts = <String>[v.channel];
    if (v.views != null) parts.add(fmtViews(v.views));
    if (v.date.isNotEmpty) parts.add(fmtDate(v.date));
    return parts.join(' • ');
  }

  Widget _avatar(VideoItem v) => v.avatar.isEmpty
      ? const CircleAvatar(child: Icon(Icons.person))
      : CircleAvatar(
          backgroundImage: NetworkImage(v.avatar),
          onBackgroundImageError: (_, __) {},
          child: const Icon(Icons.person),
        );

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Повторить')),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        itemCount: items.length + 1,
        itemBuilder: (_, i) {
          if (i == items.length) {
            if (next == null) return const SizedBox(height: 24);
            if (!moreLoading) _more();
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (i == 0 && feedNote.isNotEmpty) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Row(
                    children: [
                      const Icon(Icons.auto_awesome, size: 16),
                      const SizedBox(width: 6),
                      Text(feedNote,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                _card(items[i]),
              ],
            );
          }
          return _card(items[i]);
        },
      ),
    );
  }

  Widget _card(VideoItem v) {
    final watched = seen.contains(v.id);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => PlayerScreen(videoUrl: v.url, title: v.title)),
        ).then((_) async {
          seen = await histRepo.recentIds();
          if (mounted) setState(() {});
        }),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  v.thumb.isEmpty
                      ? const ColoredBox(
                          color: Colors.black12,
                          child: Icon(Icons.play_circle, size: 48))
                      : Image.network(v.thumb, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const ColoredBox(
                              color: Colors.black12,
                              child: Icon(Icons.play_circle, size: 48))),
                  if ((v.duration ?? 0) > 0)
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        color: Colors.black87,
                        child: Text(fmtDuration(v.duration),
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12)),
                      ),
                    ),
                  if (watched)
                    const Positioned(
                      left: 8,
                      bottom: 8,
                      child: Icon(Icons.check_circle,
                          color: Colors.white70, size: 20),
                    ),
                ],
              ),
            ),
            ListTile(
              leading: _avatar(v),
              title: Text(v.title,
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(_sub(v)),
            ),
          ],
        ),
      ),
    );
  }
}
