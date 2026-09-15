import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/extractor/extractor_service.dart';
import '../../core/history/history_repository.dart';
import '../../core/settings/app_settings.dart';
import '../../core/subs/subscriptions_repository.dart';
import '../../core/widgets/app_states.dart';
import '../../core/widgets/video_card.dart';
import '../player/player_screen.dart';

// Лента Видео v1: плотные карточки YouTube-стиля, фильтр-чипы,
// скелетон при загрузке, человеческие ошибки, FAB «наверх».
// Персонализация: свежее с подписок (параллельно, с таймаутом) +
// тренды без дублей. Просмотренное приглушается.

enum _Filter { all, unwatched, subsOnly }

class VideosTab extends StatefulWidget {
  const VideosTab({super.key});
  @override
  State<VideosTab> createState() => _VideosTabState();
}

class _VideosTabState extends State<VideosTab> {
  final ext = ExtractorService();
  final subsRepo = SubscriptionsRepository();
  final histRepo = HistoryRepository();
  final scrollCtl = ScrollController();
  final List<VideoItem> items = [];
  dynamic next;
  bool loading = true;
  bool moreLoading = false;
  String? error;
  String feedNote = '';
  Set<String> seen = {};
  _Filter filter = _Filter.all;
  bool showTopBtn = false;

  @override
  void initState() {
    super.initState();
    scrollCtl.addListener(() {
      final show = scrollCtl.hasClients && scrollCtl.offset > 1200;
      if (show != showTopBtn && mounted) setState(() => showTopBtn = show);
    });
    _load();
  }

  @override
  void dispose() {
    scrollCtl.dispose();
    super.dispose();
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
        final p = await ext.trendingPage(null).timeout(
            const Duration(seconds: 20));
        items
          ..clear()
          ..addAll(p.items);
        next = p.next;
        feedNote = '';
      }
      seen = await histRepo.recentIds();
    } on TimeoutException {
      error = 'YouTube долго не отвечает. Проверь сеть и обнови.';
    } catch (e) {
      error = e.toString();
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _loadPersonalized(List<Sub> subs) async {
    final aff = await histRepo.affinity();
    // Параллельно по 8 каналам, каждый с таймаутом — вместо последовательных delay.
    final futures = subs.take(8).map((s) => ext
        .channelUploads(s.channelUrl, limit: 3)
        .timeout(const Duration(seconds: 12), onTimeout: () => <VideoItem>[]));
    final chunks = await Future.wait(futures);
    final fromSubs = chunks.expand((e) => e).toList();
    fromSubs.sort((a, b) =>
        (aff[b.channelUrl] ?? 0).compareTo(aff[a.channelUrl] ?? 0));
    final p = await ext.trendingPage(null).timeout(
        const Duration(seconds: 20));
    final have = fromSubs.map((v) => v.id).toSet();
    final trend = p.items.where((v) => !have.contains(v.id)).toList();
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
      final p = await ext.trendingPage(next).timeout(
          const Duration(seconds: 20));
      final have = items.map((v) => v.id).toSet();
      items.addAll(p.items.where((v) => !have.contains(v.id)));
      next = p.next;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не догрузилось: $e')),
        );
      }
    }
    if (mounted) setState(() => moreLoading = false);
  }

  List<VideoItem> get visible {
    switch (filter) {
      case _Filter.unwatched:
        return items.where((v) => !seen.contains(v.id)).toList();
      case _Filter.subsOnly:
        return items.where((v) => v.channelUrl.isNotEmpty).toList();
      case _Filter.all:
        return items;
    }
  }

  Future<void> _open(VideoItem v) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => PlayerScreen(videoUrl: v.url, title: v.title)),
    );
    seen = await histRepo.recentIds();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const VideoListSkeleton();
    if (error != null) {
      return AppErrorView(message: error!, onRetry: _load);
    }
    final list = visible;
    return Scaffold(
      floatingActionButton: showTopBtn
          ? FloatingActionButton.small(
              tooltip: 'Наверх',
              onPressed: () => scrollCtl.animateTo(0,
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOut),
              child: const Icon(Icons.arrow_upward),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          controller: scrollCtl,
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _FilterRow(
                    filter: filter,
                    onChanged: (f) => setState(() => filter = f),
                  ),
                  if (feedNote.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: Row(
                        children: [
                          const Icon(Icons.auto_awesome, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(feedNote,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (list.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                    child: Text('Всё просмотрено. Так держать!')),
              )
            else
              SliverList.builder(
                itemCount: list.length + 1,
                itemBuilder: (_, i) {
                  if (i == list.length) {
                    if (next == null) {
                      return const SizedBox(height: 24);
                    }
                    if (!moreLoading) _more();
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final v = list[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: VideoCard(
                      video: v,
                      watched: seen.contains(v.id),
                      onTap: () => _open(v),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  final _Filter filter;
  final ValueChanged<_Filter> onChanged;
  const _FilterRow({required this.filter, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, _Filter f) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: FilterChip(
            label: Text(label),
            selected: filter == f,
            onSelected: (_) => onChanged(f),
          ),
        );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          chip('Все', _Filter.all),
          chip('Непросмотренные', _Filter.unwatched),
          chip('С подписок', _Filter.subsOnly),
        ],
      ),
    );
  }
}
