import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../../core/extractor/extractor_service.dart';
import '../../core/sponsorblock/sponsorblock_service.dart';
import '../../core/settings/app_settings.dart';

// Свой плеер вместо официального YouTube-плеера.
// Рекламы нет по дизайну (прямые муксированные потоки), SponsorBlock — auto-skip
// с категориями из настроек. Под видео — похожие.

class PlayerScreen extends StatefulWidget {
  final String videoUrl;
  final String title;
  const PlayerScreen({super.key, required this.videoUrl, required this.title});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  VideoPlayerController? ctl;
  SponsorBlockService sb = SponsorBlockService();
  List<SbSegment> segs = [];
  List<VideoItem> related = [];
  Timer? poll;
  String? error;
  String info = '';
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final st = context.read<AppSettings>();
    sb = SponsorBlockService(
      base: st.backendUrl.isEmpty ? 'https://sponsor.ajay.app' : st.backendUrl,
      enabledCategories: st.sbCategories,
      useProxy: st.backendUrl.isNotEmpty,
    );
    try {
      final r = await ExtractorService().resolveStream(widget.videoUrl);
      ctl = VideoPlayerController.networkUrl(Uri.parse(r.streamUrl));
      await ctl!.initialize();
      await ctl!.play();
      if (mounted) {
        setState(() {
          info =
              '${r.uploader}${r.views != null ? ' • ${fmtViews(r.views)}' : ''}${r.resolution.isNotEmpty ? ' • ${r.resolution}' : ''}';
          loading = false;
        });
      }
      related = await ExtractorService().related(widget.videoUrl);
      if (mounted) setState(() {});
      if (st.sbEnabled) {
        final id = idFromUrl(widget.videoUrl);
        segs = await sb.fetch(id);
        if (mounted) setState(() {});
      }
      poll = Timer.periodic(const Duration(milliseconds: 500), (_) async {
        final cur = ctl;
        if (!st.sbEnabled || cur == null || !cur.value.isInitialized) return;
        final pos = (await cur.position)?.inMilliseconds ?? 0;
        final skipTo = sb.shouldSkip(pos / 1000.0, segs);
        if (skipTo != null) {
          await cur.seekTo(Duration(milliseconds: (skipTo * 1000).toInt()));
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('SponsorBlock: пропуск'), duration: Duration(seconds: 1)));
          }
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    poll?.cancel();
    ctl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title, maxLines: 1)),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                            onPressed: () {
                              setState(() {
                                loading = true;
                                error = null;
                              });
                              _init();
                            },
                            child: const Text('Повторить')),
                      ],
                    ),
                  ),
                )
              : ListView(
                  children: [
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Container(
                        color: Colors.black,
                        child: Stack(
                          alignment: Alignment.bottomCenter,
                          children: [
                            VideoPlayer(ctl!),
                            VideoProgressIndicator(ctl!, allowScrubbing: true),
                          ],
                        ),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                            icon: const Icon(Icons.replay_10),
                            onPressed: () => ctl?.seekTo(Duration(
                                seconds: ctl!.value.position.inSeconds - 10))),
                        IconButton(
                            icon: Icon(ctl?.value.isPlaying == true
                                ? Icons.pause
                                : Icons.play_arrow),
                            iconSize: 40,
                            onPressed: () => setState(() => ctl?.value.isPlaying == true
                                ? ctl?.pause()
                                : ctl?.play())),
                        IconButton(
                            icon: const Icon(Icons.forward_10),
                            onPressed: () => ctl?.seekTo(Duration(
                                seconds: ctl!.value.position.inSeconds + 10))),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(info, style: Theme.of(context).textTheme.bodySmall),
                    ),
                    if (segs.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: Text('SponsorBlock: сегментов ${segs.length}',
                            style: Theme.of(context).textTheme.bodySmall),
                      ),
                    const Divider(),
                    ...related.map(
                      (v) => ListTile(
                        leading: v.thumb.isEmpty
                            ? const Icon(Icons.play_circle)
                            : Image.network(v.thumb,
                                width: 112, height: 63, fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    const Icon(Icons.play_circle)),
                        title: Text(v.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(v.channel),
                        onTap: () => Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  PlayerScreen(videoUrl: v.url, title: v.title)),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
