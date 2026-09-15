import 'package:flutter/material.dart';
import '../../core/extractor/extractor_service.dart';
import '../player/player_screen.dart';

class VideosTab extends StatefulWidget {
  const VideosTab({super.key});
  @override
  State<VideosTab> createState() => _VideosTabState();
}

class _VideosTabState extends State<VideosTab> {
  final ext = ExtractorService();
  final List<VideoItem> items = [];
  dynamic next;
  bool loading = true;
  bool moreLoading = false;
  String? error;

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
      final p = await ext.trendingPage(null);
      items
        ..clear()
        ..addAll(p.items);
      next = p.next;
    } catch (e) {
      error = e.toString();
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _more() async {
    if (moreLoading || next == null) return;
    setState(() => moreLoading = true);
    try {
      final p = await ext.trendingPage(next);
      items.addAll(p.items);
      next = p.next;
    } catch (_) {}
    if (mounted) setState(() => moreLoading = false);
  }

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
            if (!moreLoading) {
              _more();
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final v = items[i];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => PlayerScreen(videoUrl: v.url, title: v.title)),
              ),
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
                                color: Colors.black12, child: Icon(Icons.play_circle, size: 48))
                            : Image.network(v.thumb, fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const ColoredBox(
                                    color: Colors.black12,
                                    child: Icon(Icons.play_circle, size: 48))),
                        if ((v.duration ?? 0) > 0)
                          Positioned(
                            right: 8,
                            bottom: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              color: Colors.black87,
                              child: Text(fmtDuration(v.duration),
                                  style: const TextStyle(color: Colors.white, fontSize: 12)),
                            ),
                          ),
                      ],
                    ),
                  ),
                  ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(v.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                        '${v.channel}${v.views != null ? ' • ${fmtViews(v.views)}' : ''}'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
