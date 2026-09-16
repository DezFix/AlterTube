import 'dart:async';
import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/extractor/extractor_service.dart';
import '../../core/settings/app_settings.dart';
import '../../core/widgets/app_states.dart';
import '../player/player_screen.dart';

// Shorts: вертикальный слайдер как в TikTok.
// Один общий плеер на всех страницах: при свайпе подменяем источник —
// дешево и без пачки живых плееров. Финал видео -> автопрокрутка дальше
// (тумблер в настройках). Тап — пауза/плей.
class ShortsTab extends StatefulWidget {
  const ShortsTab({super.key});
  @override
  State<ShortsTab> createState() => _ShortsTabState();
}

class _ShortsTabState extends State<ShortsTab> {
  final ext = ExtractorService();
  final pager = PageController();
  final progress = ValueNotifier<double>(0);

  List<VideoItem>? items;
  String? error;
  int current = 0;
  bool muted = false;
  bool paused = false;
  bool videoLoading = false;
  String? videoError;
  BetterPlayerController? ctl;
  Timer? _ticker;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    progress.dispose();
    pager.dispose();
    ctl?.removeEventsListener(_onEvent);
    ctl?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await ext.shortsFeed();
      if (!mounted) return;
      setState(() => items = list);
      if (list.isNotEmpty) _open(0);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  BetterPlayerDataSource _ds(String url, bool isLive) =>
      BetterPlayerDataSource(
        BetterPlayerDataSourceType.network,
        url,
        videoFormat: isLive
            ? BetterPlayerVideoFormat.hls
            : BetterPlayerVideoFormat.other,
      );

  void _onEvent(BetterPlayerEvent e) {
    if (!mounted) return;
    switch (e.betterPlayerEventType) {
      case BetterPlayerEventType.finished:
        if (context.read<AppSettings>().shortsAutoplay) _next();
      case BetterPlayerEventType.play:
        if (paused) setState(() => paused = false);
      case BetterPlayerEventType.pause:
        if (!paused) setState(() => paused = true);
      case BetterPlayerEventType.exception:
        setState(() => videoError = 'Не загрузилось');
      default:
        break;
    }
  }

  Future<void> _open(int i) async {
    final list = items;
    if (list == null || i < 0 || i >= list.length) return;
    final my = ++_token;
    setState(() {
      videoLoading = true;
      videoError = null;
      paused = false;
    });
    try {
      final r = await ExtractorService().resolveStream(list[i].url);
      if (!mounted || my != _token) return;
      if (ctl == null) {
        final c = BetterPlayerController(
          const BetterPlayerConfiguration(
            autoPlay: true,
            looping: false,
            aspectRatio: 9 / 16,
            allowedScreenSleep: false,
            handleLifecycle: true,
            fullScreenByDefault: false,
            controlsConfiguration: BetterPlayerControlsConfiguration(
              showControls: false,
            ),
          ),
          betterPlayerDataSource: _ds(r.streamUrl, r.isLive),
        );
        c.addEventsListener(_onEvent);
        await c.setVolume(muted ? 0 : 1);
        if (!mounted || my != _token) {
          c.removeEventsListener(_onEvent);
          c.dispose();
          return;
        }
        setState(() {
          ctl = c;
          videoLoading = false;
        });
        _startTicker();
      } else {
        await ctl!.setupDataSource(_ds(r.streamUrl, r.isLive));
        await ctl!.setVolume(muted ? 0 : 1);
        if (!mounted || my != _token) return;
        setState(() => videoLoading = false);
      }
    } catch (e) {
      if (!mounted || my != _token) return;
      setState(() {
        videoLoading = false;
        videoError = e.toString();
      });
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      final vc = ctl?.videoPlayerController;
      if (vc == null) return;
      final pos = await vc.position;
      final dur = vc.value.duration;
      if (pos == null || dur == null || dur.inMilliseconds <= 0) return;
      progress.value =
          (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
    });
  }

  void _next() {
    final list = items;
    if (list == null || current + 1 >= list.length) return;
    pager.nextPage(
        duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
  }

  Future<void> _togglePlay() async {
    final c = ctl;
    if (c == null || videoLoading) return;
    if (paused) {
      await c.play();
    } else {
      await c.pause();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return AppErrorView(
        message: error!,
        onRetry: () {
          setState(() {
            error = null;
            items = null;
          });
          _load();
        },
      );
    }
    final list = items;
    if (list == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bolt_outlined,
                  size: 48,
                  color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 12),
              const Text('Shorts не нашлись. Попробуй обновить.',
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: () {
                  setState(() => items = null);
                  _load();
                },
                child: const Text('Обновить'),
              ),
            ],
          ),
        ),
      );
    }
    final v = list[current];
    return Stack(
      fit: StackFit.expand,
      children: [
        // Видео-слой (один плеер на всех)
        GestureDetector(
          onTap: _togglePlay,
          child: Container(
            color: Colors.black,
            child: ctl == null
                ? const Center(child: CircularProgressIndicator())
                : BetterPlayer(controller: ctl!),
          ),
        ),
        if (videoLoading)
          const Center(child: CircularProgressIndicator()),
        if (videoError != null && !videoLoading)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(videoError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: () => _open(current),
                    child: const Text('Повторить'),
                  ),
                ],
              ),
            ),
          ),
        if (paused && videoError == null)
          const Center(
              child: Icon(Icons.play_circle,
                  color: Colors.white70, size: 72)),
        // Свайп-слой поверх (пейджер невидимый, ловит жесты)
        PageView.builder(
          controller: pager,
          scrollDirection: Axis.vertical,
          itemCount: list.length,
          onPageChanged: (i) {
            setState(() => current = i);
            progress.value = 0;
            _open(i);
          },
          itemBuilder: (_, i) => const SizedBox.expand(),
        ),
        // Прогресс
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: ValueListenableBuilder<double>(
            valueListenable: progress,
            builder: (_, p, __) => LinearProgressIndicator(
                value: p.clamp(0.0, 1.0),
                minHeight: 3,
                backgroundColor: Colors.white24),
          ),
        ),
        // Текст снизу слева
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
                  style: const TextStyle(
                      color: Colors.white, fontSize: 15)),
              const SizedBox(height: 4),
              Text(v.channel,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 13)),
            ],
          ),
        ),
        // Правая панель действий
        Positioned(
          right: 8,
          bottom: 56,
          child: Column(
            children: [
              IconButton.filledTonal(
                tooltip: muted ? 'Включить звук' : 'Выключить звук',
                icon: Icon(
                    muted ? Icons.volume_off : Icons.volume_up),
                onPressed: () async {
                  setState(() => muted = !muted);
                  await ctl?.setVolume(muted ? 0 : 1);
                },
              ),
              const SizedBox(height: 8),
              IconButton.filledTonal(
                tooltip: 'Поделиться',
                icon: const Icon(Icons.share_outlined),
                onPressed: () => SharePlus.instance.share(
                  ShareParams(text: v.url, subject: v.title),
                ),
              ),
              const SizedBox(height: 8),
              IconButton.filledTonal(
                tooltip: 'Открыть как видео',
                icon: const Icon(Icons.open_in_full),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => PlayerScreen(
                          videoUrl: v.url, title: v.title)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
