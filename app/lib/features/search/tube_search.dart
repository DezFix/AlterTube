import 'package:flutter/material.dart';
import '../../core/extractor/extractor_service.dart';
import '../player/player_screen.dart';

// Живой поиск через SearchExtractor: подсказки + результаты.
// Ошибки (сеть, 429, поломка экстрактора) показываем текстом с повтором.

class TubeSearch extends SearchDelegate<VideoItem?> {
  final ExtractorService ext = ExtractorService();

  @override
  List<Widget>? buildActions(BuildContext context) => [
        IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
      ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => close(context, null),
      );

  @override
  Widget buildSuggestions(BuildContext context) {
    if (query.isEmpty) return const Center(child: Text('Введи запрос'));
    return FutureBuilder<List<String>>(
      future: ext.suggestions(query),
      builder: (c, s) {
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        return ListView(
          children: s.data!
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
    return FutureBuilder<List<VideoItem>>(
      future: ext.search(query),
      builder: (c, s) {
        if (s.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (s.hasError) return _err(s.error.toString(), () => showResults(context));
        final items = s.data!;
        if (items.isEmpty) return const Center(child: Text('Ничего не найдено'));
        return ListView.builder(
          itemCount: items.length,
          itemBuilder: (_, i) {
            final v = items[i];
            return ListTile(
              leading: _thumb(v.thumb),
              title: Text(v.title, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(v.channel),
              trailing: v.isShort ? const Icon(Icons.bolt, size: 16) : null,
              onTap: () {
                close(context, v);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PlayerScreen(videoUrl: v.url, title: v.title),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _err(String msg, VoidCallback retry) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(msg, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: retry, child: const Text('Повторить')),
            ],
          ),
        ),
      );

  Widget _thumb(String url) => SizedBox(
        width: 96,
        height: 54,
        child: url.isEmpty
            ? const ColoredBox(color: Colors.black12, child: Icon(Icons.play_circle))
            : Image.network(url, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const ColoredBox(color: Colors.black12, child: Icon(Icons.play_circle))),
      );
}
