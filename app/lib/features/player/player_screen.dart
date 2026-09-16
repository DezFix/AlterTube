import 'dart:async';
import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/extractor/extractor_service.dart';
import '../../core/history/history_repository.dart';
import '../../core/sponsorblock/sponsorblock_service.dart';
import '../../core/settings/app_settings.dart';
import '../../core/subs/subscriptions_repository.dart';
import '../../core/widgets/app_states.dart';
import '../../core/widgets/channel_avatar.dart';

// Экран видео: готовый плеер (пауза/плей, перемотка, скорость,
// качество, фулскрин с поворотом) + описание со ссылками,
// «Поделиться», главы, комментарии, похожие.
class PlayerScreen extends StatefulWidget {
  final String videoUrl;
  final String title;
  const PlayerScreen({super.key, required this.videoUrl, required this.title});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  BetterPlayerController? _bp;
  SponsorBlockService sb = SponsorBlockService();
  ResolvedStream? res;
  List<SbSegment> segs = [];
  List<VideoItem> related = [];
  List<Chapter> chapters = [];
  List<YtComment> comments = [];
  Timer? _sbTimer;
  String? error;
  String info = '';
  bool loading = true;
  bool commentsLoading = false;
  bool commentsDone = false;
  bool descOpen = false;
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
      if (!mounted) return;
      // ВАЖНО: у URL YouTube нет расширения файла, а нативка better_player
      // при formatHint==null гадает формат по расширению и падает
      // (IndexOutOfBounds). Поэтому формат указываем явно.
      final isHls = r.isLive || r.streamUrl.contains('m3u8');
      final format = isHls
          ? BetterPlayerVideoFormat.hls
          : (r.resolution == 'DASH'
              ? BetterPlayerVideoFormat.dash
              : BetterPlayerVideoFormat.other);
      final ds = BetterPlayerDataSource(
        BetterPlayerDataSourceType.network,
        r.streamUrl,
        resolutions: _resolutions(r),
        videoFormat: format,
      );
      final ctl = BetterPlayerController(
        const BetterPlayerConfiguration(
          autoPlay: true,
          aspectRatio: 16 / 9,
          allowedScreenSleep: false,
          handleLifecycle: true,
          fullScreenByDefault: false,
          deviceOrientationsOnFullScreen: [
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ],
          deviceOrientationsAfterFullScreen: [
            DeviceOrientation.portraitUp,
          ],
        ),
        betterPlayerDataSource: ds,
      );
      setState(() {
        res = r;
        _bp = ctl;
        info =
            '${r.uploader}${r.views != null ? ' • ${fmtViews(r.views)}' : ''}${r.likes != null && r.likes! > 0 ? ' • ♥ ${fmtViews(r.likes)}' : ''}';
        loading = false;
      });
      HistoryRepository().recordWatch(idFromUrl(widget.videoUrl), r.uploaderUrl);
      _refreshSub(r.uploaderUrl);
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
      _sbTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
        final vc = _bp?.videoPlayerController;
        if (vc == null || !st.sbEnabled || segs.isEmpty) return;
        final pos = await vc.position;
        if (pos == null) return;
        final skipTo = sb.shouldSkip(pos.inMilliseconds / 1000.0, segs);
        if (skipTo != null && mounted) {
          await _bp?.seekTo(Duration(milliseconds: (skipTo * 1000).toInt()));
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('SponsorBlock: пропуск'),
                duration: Duration(seconds: 1)));
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

  /// Качество из мукседов: {label: url}. Дубли меток склеиваем (первый wins).
  Map<String, String> _resolutions(ResolvedStream r) {
    final out = <String, String>{r.resolution: r.streamUrl};
    for (final q in r.muxed) {
      out.putIfAbsent(q.label, () => q.url);
    }
    return out;
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
        await repo.subscribe(
            ch.id, ch.name.isEmpty ? r.uploader : ch.name, ch.url);
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

  Future<void> _share() async {
    await SharePlus.instance.share(
      ShareParams(text: widget.videoUrl, subject: widget.title),
    );
  }

  Future<void> _linkMenu(String url) async {
    final link = url.startsWith('http') ? url : 'https://$url';
    await showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.link),
              title: Text(link, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('Открыть'),
              onTap: () async {
                Navigator.pop(c);
                final uri = Uri.tryParse(link);
                if (uri != null) {
                  await launchUrl(uri,
                      mode: LaunchMode.externalApplication);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Копировать ссылку'),
              onTap: () async {
                Navigator.pop(c);
                await Clipboard.setData(ClipboardData(text: link));
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Ссылка скопирована')));
                }
              },
            ),
          ],
        ),
      ),
    );
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

  @override
  void dispose() {
    _sbTimer?.cancel();
    _bp?.dispose();
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
                        child: _bp == null
                            ? const Center(
                                child: CircularProgressIndicator())
                            : BetterPlayer(controller: _bp!),
                      ),
                    ),
                    Padding(
                      padding:
                          const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Text(widget.title,
                          style:
                              Theme.of(context).textTheme.titleMedium),
                    ),
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
                      ),
                    // Действия: поделиться + описание
                    Padding(
                      padding:
                          const EdgeInsets.fromLTRB(8, 4, 8, 0),
                      child: Row(
                        children: [
                          TextButton.icon(
                            icon: const Icon(Icons.share_outlined),
                            label: const Text('Поделиться'),
                            onPressed: _share,
                          ),
                          if ((res?.description ?? '').isNotEmpty)
                            TextButton.icon(
                              icon: Icon(descOpen
                                  ? Icons.expand_less
                                  : Icons.expand_more),
                              label: const Text('Описание'),
                              onPressed: () => setState(
                                  () => descOpen = !descOpen),
                            ),
                          const Spacer(),
                          if (segs.isNotEmpty)
                            Text('SB: ${segs.length}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall),
                        ],
                      ),
                    ),
                    // Описание: раскрывается, текст выделяется, ссылки тапаются
                    if (descOpen &&
                        (res?.description ?? '').isNotEmpty)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.fromLTRB(
                            16, 4, 16, 0),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          borderRadius:
                              BorderRadius.circular(12),
                        ),
                        child: SelectableText.rich(
                          TextSpan(children: _descSpans(context)),
                          style:
                              Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    // Главы
                    if (chapters.isNotEmpty) ...[
                      const Divider(),
                      SizedBox(
                        height: 40,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding:
                              const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: chapters.length,
                          itemBuilder: (_, i) {
                            final c = chapters[i];
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4),
                              child: ActionChip(
                                label: Text(
                                    '${fmtDuration(c.start)} ${c.title}',
                                    maxLines: 1,
                                    overflow:
                                        TextOverflow.ellipsis),
                                onPressed: () => _bp?.seekTo(
                                    Duration(seconds: c.start)),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                    const Divider(),
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                          'Комментарии (${comments.length})',
                          style:
                              Theme.of(context).textTheme.titleSmall),
                    ),
                    ...comments.map(
                      (c) => ListTile(
                        leading: c.avatar.isEmpty
                            ? const CircleAvatar(
                                child: Icon(Icons.person, size: 16))
                            : CircleAvatar(
                                backgroundImage:
                                    NetworkImage(c.avatar)),
                        title: Text(c.author,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall),
                        subtitle: Text(c.text,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis),
                        trailing: c.likes > 0
                            ? Text('♥ ${fmtViews(c.likes)}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall)
                            : null,
                      ),
                    ),
                    if (!commentsDone)
                      Center(
                        child: TextButton(
                          onPressed: commentsLoading
                              ? null
                              : _loadComments,
                          child: commentsLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))
                              : const Text('Показать комментарии'),
                        ),
                      ),
                    if (commentsDone && comments.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        child: Text('Комментарии недоступны',
                            style: TextStyle(color: Colors.grey)),
                      ),
                    const Divider(),
                    ...related.map(
                      (v) => ListTile(
                        leading: v.thumb.isEmpty
                            ? const Icon(Icons.play_circle)
                            : Image.network(v.thumb,
                                width: 112,
                                height: 63,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    const Icon(Icons.play_circle)),
                        title: Text(v.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        subtitle: Text(v.channel),
                        onTap: () => Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                              builder: (_) => PlayerScreen(
                                  videoUrl: v.url,
                                  title: v.title)),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  /// Описание -> спаны: обычный текст + кликабельные ссылки
  /// (тап открывает меню «Открыть / Копировать»).
  List<InlineSpan> _descSpans(BuildContext context) {
    final text = res?.description ?? '';
    final linkColor = Theme.of(context).colorScheme.primary;
    final re =
        RegExp(r'(https?://\S+|www\.\S+)', caseSensitive: false);
    final out = <InlineSpan>[];
    var last = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > last) {
        out.add(TextSpan(text: text.substring(last, m.start)));
      }
      final url = m.group(0)!;
      out.add(TextSpan(
        text: url,
        style: TextStyle(color: linkColor),
        recognizer: TapGestureRecognizer()
          ..onTap = () => _linkMenu(url),
      ));
      last = m.end;
    }
    if (last < text.length) {
      out.add(TextSpan(text: text.substring(last)));
    }
    if (out.isEmpty) out.add(TextSpan(text: text));
    return out;
  }
}
