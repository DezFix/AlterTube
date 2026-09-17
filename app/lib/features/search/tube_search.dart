import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/extractor/extractor_service.dart';
import '../../core/widgets/app_states.dart';
import '../../core/widgets/player_route.dart';

// Поиск v1: история запросов + подсказки + результаты.
// Ошибки — через AppErrorView, Shorts помечаются бейджем.
class TubeSearch extends SearchDelegate<VideoItem?> {
  final ExtractorService ext = ExtractorService();
  static const _histKey = 'altertube_search_hist_v1';

  Future<List<String>> _history() async {
    final p = await SharedPreferences.getInstance();
    return p.getStringList(_histKey) ?? [];
  }

  Future<void> _saveQuery(String q) async {
    q = q.trim();
    if (q.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    final cur =
        (p.getStringList(_histKey) ?? []).where((e) => e != q).toList()
          ..insert(0, q);
    while (cur.length > 20) {
      cur.removeLast();
    }
    await p.setStringList(_histKey, cur);
  }

  @override
  List<Widget>? buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
              icon: const Icon(Icons.clear),
              tooltip: 'Очистить',
              onPressed: () => query = ''),
      ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: 'Назад',
        onPressed: () => close(context, null),
      );

  @override
  Widget buildSuggestions(BuildContext context) {
    if (query.trim().isEmpty) {
      return FutureBuilder<List<String>>(
        future: _history(),
        builder: (c, s) {
          final hist = s.data ?? [];
          if (hist.isEmpty) {
            return const Center(
                child: Text('Введи запрос — подсказки появятся здесь'));
          }
          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text('Недавнее',
                    style: Theme.of(context).textTheme.titleSmall),
              ),
              ...hist.map((h) => ListTile(
                    leading: const Icon(Icons.history),
                    title: Text(h),
                    trailing: const Icon(Icons.north_west, size: 16),
                    onTap: () {
                      query = h;
                      showResults(context);
                    },
                  )),
            ],
          );
        },
      );
    }
    return FutureBuilder<List<String>>(
      future: ext.suggestions(query),
      builder: (c, s) {
        if (!s.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = s.data!;
        if (data.isEmpty) {
          return Center(
            child: ListTile(
              leading: const Icon(Icons.search),
              title: Text('Искать «$query»'),
              onTap: () => showResults(context),
            ),
          );
        }
        return ListView(
          children: data
              .map((w) => ListTile(
                    leading: const Icon(Icons.search),
                    title: Text(w),
                    onTap: () {
                      query = w;
                      showResults(context);
                    },
                  ))
              .toList(),
        );
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    final q = query.trim();
    if (q.isEmpty) return const Center(child: Text('Введи запрос'));
    _saveQuery(q);
    return FutureBuilder<List<VideoItem>>(
      future: ext.search(q),
      builder: (c, s) {
        if (s.connectionState == ConnectionState.waiting) {
          return const VideoListSkeleton();
        }
        if (s.hasError) {
          return AppErrorView(
              message: s.error.toString(),
              onRetry: () => showResults(context));
        }
        final items = s.data!;
        if (items.isEmpty) {
          return const Center(child: Text('Ничего не найдено'));
        }
        return ListView.builder(
          itemCount: items.length,
          itemBuilder: (_, i) {
            final v = items[i];
            return ListTile(
              leading: _thumb(context, v.thumb),
              title: Text(v.title,
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                  '${v.channel}${v.views != null ? ' • ${fmtViews(v.views)}' : ''}${v.date.isNotEmpty ? ' • ${fmtDate(v.date)}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              trailing: v.isShort
                  ? const Icon(Icons.bolt, size: 16)
                  : null,
              onTap: () {
                close(context, v);
                pushPlayer(context, videoUrl: v.url, title: v.title);
              },
            );
          },
        );
      },
    );
  }

  Widget _thumb(BuildContext context, String url) => SizedBox(
        width: 96,
        height: 54,
        child: url.isEmpty
            ? ColoredBox(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest,
                child: const Icon(Icons.play_circle))
            : Image.network(url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => ColoredBox(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    child: const Icon(Icons.play_circle))),
      );
}
