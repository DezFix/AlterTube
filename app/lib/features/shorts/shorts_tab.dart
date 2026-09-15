import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../core/extractor/extractor_service.dart';
import '../player/player_screen.dart';

// Доделанные Shorts: вертикальный PageView, текущее видео играет само,
// соседние предзагружаются (PageView держит ±1), остальные на паузе.
// Тап — пауза/плей, иконка — mute, снизу прогресс.

class ShortsTab extends StatefulWidget {
  const ShortsTab({super.key});
  @override
  State<ShortsTab> createState() => _ShortsTabState();
}

class _ShortsTabState extends State<ShortsTab> {
  final ext = ExtractorService();
  List<VideoItem>? items;
  String? error;
  int current = 0;
  bool muted = false;

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
    return Stack(
      children: [
        PageView.builder(
          scrollDirection: Axis.vertical,
          itemCount: items!.length,
          onPageChanged: (i) => setState(() => current = i),
          itemBuilder: (_, i) => _ShortsPage(
            key: ValueKey(items![i].id),
            video: items![i],
            active: i == current,
            muted: muted,
          ),
        ),
        Positioned(
          right: 8,
          top: 8,
          child: IconButton.filledTonal(
            tooltip: muted ? 'Включить звук' : 'Выключить звук',
            icon: Icon(muted ? Icons.volume_off : Icons.volume_up),
            onPressed: () => setState(() => muted = !muted),
          ),
        ),
      ],
    );
  }
}

class _ShortsPage extends StatefulWidget {
  final VideoItem video;
  final bool active;
  final bool muted;
  const _ShortsPage(
      {super.key, required this.video, required this.active, required this.muted});

  @override
  State<_ShortsPage> createState() => _ShortsPageState();
}

class _ShortsPageState extends State<_ShortsPage> {
  Player? player;
  VideoController? vctl;
  String? error;
  bool paused = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void didUpdateWidget(covariant _ShortsPage old) {
    super.didUpdateWidget(old);
    if (widget.muted != old.muted) {
      player?.setVolume(widget.muted ? 0 : 100);
    }
    if (widget.active != old.active) {
      if (widget.active) {
        if (paused) {
          player?.play();
          setState(() => paused = false);
        }
      } else {
        player?.pause();
      }
    }
  }

  Future<void> _open() async {
    try {
      final r = await ExtractorService().resolveStream(widget.video.url);
      final p = Player();
      final vc = VideoController(p);
      if (!mounted) {
        await p.dispose();
        return;
      }
      setState(() {
        player = p;
        vctl = vc;
      });
      await p.setVolume(widget.muted ? 0 : 100);
      await p.open(Media(r.streamUrl), play: widget.active);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  void dispose() {
    player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.video;
    return GestureDetector(
      onTap: () async {
        final p = player;
        if (p == null) return;
        if (paused) {
          await p.play();
        } else {
          await p.pause();
        }
        setState(() => paused = !paused);
      },
      onDoubleTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => PlayerScreen(videoUrl: v.url, title: v.title)),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: Colors.black),
          if (vctl != null)
            Video(controller: vctl!, controls: NoVideoControls),
          if (player == null && error == null)
            const Center(child: CircularProgressIndicator()),
          if (error != null)
            Center(
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70)))),
          if (paused && error == null)
            const Center(
                child: Icon(Icons.play_circle, color: Colors.white70, size: 72)),
          // Прогресс
          if (player != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: StreamBuilder<Duration>(
                stream: player!.stream.position,
                builder: (c, pos) => StreamBuilder<Duration>(
                  stream: player!.stream.duration,
                  builder: (c, dur) {
                    final p = pos.data?.inMilliseconds ?? 0;
                    final d = dur.data?.inMilliseconds ?? 1;
                    return LinearProgressIndicator(
                        value: (p / d).clamp(0.0, 1.0),
                        minHeight: 3,
                        backgroundColor: Colors.white24);
                  },
                ),
              ),
            ),
          Positioned(
            left: 12,
            right: 72,
            bottom: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(v.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 15)),
                const SizedBox(height: 4),
                Text(v.channel,
                    style: const TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 2),
                const Text('Двойной тап — открыть как видео',
                    style: TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
