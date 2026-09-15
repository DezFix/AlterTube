import 'package:flutter/material.dart';
import '../../core/extractor/extractor_service.dart';
import '../player/player_screen.dart';

// Отдельная вкладка Shorts: вертикальный PageView 9:16, свайп вверх/вниз.
// Источник — поиск #shorts с фильтром isShort от экстрактора.

class ShortsTab extends StatefulWidget {
  const ShortsTab({super.key});
  @override
  State<ShortsTab> createState() => _ShortsTabState();
}

class _ShortsTabState extends State<ShortsTab> {
  final ext = ExtractorService();
  List<VideoItem>? items;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await ext.shortsFeed();
      if (mounted) setState(() => items = list);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                  onPressed: () {
                    setState(() => error = null);
                    _load();
                  },
                  child: const Text('Повторить')),
            ],
          ),
        ),
      );
    }
    if (items == null) return const Center(child: CircularProgressIndicator());
    if (items!.isEmpty) return const Center(child: Text('Shorts не нашлись'));
    return PageView.builder(
      scrollDirection: Axis.vertical,
      itemCount: items!.length,
      itemBuilder: (_, i) {
        final v = items![i];
        return InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => PlayerScreen(videoUrl: v.url, title: v.title)),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              v.thumb.isEmpty
                  ? Container(color: Colors.black)
                  : Image.network(v.thumb, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(color: Colors.black)),
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black87],
                    stops: [0.5, 1.0],
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 24,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(v.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(v.channel, style: const TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
              const Positioned(
                right: 12,
                bottom: 24,
                child: Icon(Icons.play_circle, color: Colors.white, size: 48),
              ),
            ],
          ),
        );
      },
    );
  }
}
