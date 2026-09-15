import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import '../../core/extractor/extractor_service.dart';
import '../../core/history/history_repository.dart';
import '../../core/sponsorblock/sponsorblock_service.dart';
import '../../core/settings/app_settings.dart';
import '../../core/subs/subscriptions_repository.dart';
import '../../core/widgets/app_states.dart';
import '../../core/widgets/channel_avatar.dart';

// Нормальный плеер на ExoPlayer (media_kit): прямые потоки, DASH и HLS,
// fullscreen/скорость/качество, главы, комменты, похожие, SponsorBlock.

class PlayerScreen extends StatefulWidget {
  final String videoUrl;
  final String title;
  const PlayerScreen({super.key, required this.videoUrl, required this.title});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  Player? player;
  VideoController? vctl;
  SponsorBlockService sb = SponsorBlockService();
  ResolvedStream? res;
  List<SbSegment> segs = [];
  List<VideoItem> related = [];
  List<Chapter> chapters = [];
  List<YtComment> comments = [];
  StreamSubscription<Duration>? _posSub;
  String? error;
  String info = '';
  bool loading = true;
  bool commentsLoading = false;
  bool commentsDone = false;
  double rate = 1.0;
  bool isSub = false;
  bool subBusy = false;

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
      final p = Player();
      final vc = VideoController(p);
      if (!mounted) {
        await p.dispose();
        return;
      }
      setState(() {
        player = p;
        vctl = vc;
        res = r;
        info =
            '${r.uploader}${r.views != null ? ' • ${fmtViews(r.views)}' : ''}${r.resolution.isNotEmpty ? ' • ${r.resolution}' : ''}';
        loading = false;
      });
      await p.open(Media(r.streamUrl), play: true);
      await p.setRate(rate);
      // История для индексации ленты (fire-and-forget)
      HistoryRepository().recordWatch(idFromUrl(widget.videoUrl), r.uploaderUrl);
      // Статус подписки
      _refreshSub(r.uploaderUrl);
      // Похожие + главы + комменты фоном
      ExtractorService().related(widget.videoUrl).then((v) {
        if (mounted) setState(() => related = v);
      });
      ExtractorService().chapters(widget.videoUrl).then((v) {
        if (mounted) setState(() => chapters = v);
      });
      _loadComments();
      if (st.sbEnabled) {
        final id = idFromUrl(widget.videoUrl);
        sb.fetch(id).then((v) {
          if (mounted) setState(() => segs = v);
        });
      }
      _posSub = p.stream.position.listen((pos) async {
        if (!st.sbEnabled || segs.isEmpty) return;
        final skipTo = sb.shouldSkip(pos.inMilliseconds / 1000.0, segs);
        if (skipTo != null) {
          await p.seek(Duration(milliseconds: (skipTo * 1000).toInt()));
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

  Future<void> _refreshSub(String channelUrl) async {
    if (channelUrl.isEmpty) return;
    try {
      final ch = await ExtractorService().resolveChannel(channelUrl);
      if (!mounted || ch.id.isEmpty) return;
      final sub = await SubscriptionsRepository().isSub(ch.id);
      if (mounted) setState(() => isSub = sub);
    } catch (_) {}
  }

  Future<void> _toggleSub() async {
    final r = res;
    if (r == null || r.uploaderUrl.isEmpty || subBusy) return;
    setState(() => subBusy = true);
    try {
      final ch = await ExtractorService().resolveChannel(r.uploaderUrl);
      if (ch.id.isEmpty) throw ExtractorFailure('Канал не распознан');
      final repo = SubscriptionsRepository();
      if (isSub) {
        await repo.unsubscribe(ch.id);
      } else {
        await repo.subscribe(ch.id, ch.name.isEmpty ? r.uploader : ch.name, ch.url);
      }
      if (mounted) {
        setState(() {
          isSub = !isSub;
          subBusy = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(isSub ? 'Подписался: ${ch.name}' : 'Отписался')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => subBusy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Не вышло: $e')));
      }
    }
  }

  Future<void> _loadComments() async {
    if (commentsLoading || commentsDone) return;
    setState(() => commentsLoading = true);
    try {
      final first = comments.isEmpty;
      final list = first
          ? await ExtractorService().comments(widget.videoUrl)
          : await ExtractorService().moreComments();
      if (!mounted) return;
      setState(() {
        commentsLoading = false;
        if (list.isEmpty) {
          commentsDone = true;
        } else {
          comments.addAll(list);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => commentsLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Комменты не загрузились: $e')),
      );
    }
  }

  Future<void> _switchQuality(StreamOption q) async {
    final p = player;
    if (p == null || res == null) return;
    final pos = await p.stream.position.first;
    final wasPlaying = await p.stream.playing.first;
    await p.open(Media(q.url), play: true);
    await p.seek(pos);
    await p.setRate(rate);
    if (!wasPlaying) await p.pause();
    setState(() {
      res = ResolvedStream(
        title: res!.title,
        uploader: res!.uploader,
        uploaderUrl: res!.uploaderUrl,
        streamUrl: q.url,
        resolution: q.label,
        views: res!.views,
        duration: res!.duration,
        muxed: res!.muxed,
        dashUrl: res!.dashUrl,
        hlsUrl: res!.hlsUrl,
        isLive: res!.isLive,
      );
    });
  }

  Future<void> _setRate(double v) async {
    await player?.setRate(v);
    setState(() => rate = v);
  }

  @override
  void dispose() {
    _posSub?.cancel();
    player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title, maxLines: 1)),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? AppErrorView(
                  message: error!,
                  onRetry: () {
                    setState(() {
                      loading = true;
                      error = null;
                    });
                    _init();
                  },
                )
              : ListView(
                  children: [
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Container(
                        color: Colors.black,
                        child: Video(
                          controller: vctl!,
                          controls: MaterialVideoControls,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Text(widget.title,
                          style: Theme.of(context).textTheme.titleMedium),
                    ),
                    // Канал + подписка
                    if (res != null)
                      Padding(
                        padding:
                            const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Row(
                          children: [
                            ChannelAvatar(name: res!.uploader),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(res!.uploader,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium),
                                  Text(info,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.tonal(
                              onPressed:
                                  subBusy ? null : _toggleSub,
                              child: Text(isSub
                                  ? 'Вы подписаны'
                                  : 'Подписаться'),
                            ),
                          ],
                        ),
                      )
                    else
                      Padding(
                        padding:
                            const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Row(
                          children: [
                            Expanded(
                                child: Text(info,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall)),
                            if (segs.isNotEmpty)
                              Text('SB: ${segs.length}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall),
                          ],
                        ),
                      ),
                    if (res != null && segs.isNotEmpty)
                      Padding(
                        padding:
                            const EdgeInsets.fromLTRB(16, 4, 16, 0),
                        child: Text('SB: пропущено сегментов: ${segs.length}',
                            style:
                                Theme.of(context).textTheme.bodySmall),
                      ),
                    // Качество + скорость
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          if (res != null && res!.muxed.length > 1)
                            PopupMenuButton<StreamOption>(
                              icon: const Icon(Icons.hd_outlined),
                              tooltip: 'Качество',
                              onSelected: _switchQuality,
                              itemBuilder: (_) => res!.muxed
                                  .map((q) => PopupMenuItem(
                                      value: q, child: Text(q.label)))
                                  .toList(),
                            ),
                          PopupMenuButton<double>(
                            icon: const Icon(Icons.speed_outlined),
                            tooltip: 'Скорость',
                            onSelected: _setRate,
                            itemBuilder: (_) => [0.5, 1.0, 1.25, 1.5, 2.0]
                                .map((v) => PopupMenuItem(
                                      value: v,
                                      child: Text('${v}x${v == rate ? ' ✓' : ''}'),
                                    ))
                                .toList(),
                          ),
                        ],
                      ),
                    ),
                    // Главы
                    if (chapters.isNotEmpty) ...[
                      const Divider(),
                      SizedBox(
                        height: 40,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: chapters.length,
                          itemBuilder: (_, i) {
                            final c = chapters[i];
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: ActionChip(
                                label: Text(
                                    '${fmtDuration(c.start)} ${c.title}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                onPressed: () => player
                                    ?.seek(Duration(seconds: c.start)),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                    const Divider(),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text('Комментарии (${comments.length})',
                          style: Theme.of(context).textTheme.titleSmall),
                    ),
                    ...comments.map(
                      (c) => ListTile(
                        leading: c.avatar.isEmpty
                            ? const CircleAvatar(child: Icon(Icons.person, size: 16))
                            : CircleAvatar(
                                backgroundImage: NetworkImage(c.avatar)),
                        title: Text(c.author,
                            style: Theme.of(context).textTheme.bodySmall),
                        subtitle: Text(c.text,
                            maxLines: 4, overflow: TextOverflow.ellipsis),
                        trailing: c.likes > 0
                            ? Text('♥ ${fmtViews(c.likes)}',
                                style: Theme.of(context).textTheme.bodySmall)
                            : null,
                      ),
                    ),
                    if (!commentsDone)
                      Center(
                        child: TextButton(
                          onPressed:
                              commentsLoading ? null : _loadComments,
                          child: commentsLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Text('Показать комментарии'),
                        ),
                      ),
                    if (commentsDone && comments.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: Text('Комментарии недоступны',
                            style: TextStyle(color: Colors.grey)),
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
                        title: Text(v.title,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(v.channel),
                        onTap: () => Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                              builder: (_) => PlayerScreen(
                                  videoUrl: v.url, title: v.title)),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
