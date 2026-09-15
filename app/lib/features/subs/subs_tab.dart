import 'package:flutter/material.dart';
import '../../core/extractor/extractor_service.dart';
import '../../core/subs/subscriptions_repository.dart';
import '../../core/widgets/app_states.dart';
import '../../core/widgets/channel_avatar.dart';
import '../player/player_screen.dart';

// Подписки v1: stories-полоса каналов, параллельная лента,
// отписка долгим нажатием, человеческие пустые состояния.
class SubsTab extends StatefulWidget {
  const SubsTab({super.key});
  @override
  State<SubsTab> createState() => _SubsTabState();
}

class _SubsTabState extends State<SubsTab> {
  final repo = SubscriptionsRepository();
  final ext = ExtractorService();
  List<Sub> subs = [];
  List<VideoItem> feed = [];
  bool loading = true;
  bool feedLoading = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final all = await repo.load();
      if (!mounted) return;
      setState(() {
        subs = all;
        loading = false;
      });
      await _loadFeed(all);
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = e.toString();
        });
      }
    }
  }

  Future<void> _loadFeed(List<Sub> all) async {
    if (all.isEmpty) {
      if (mounted) setState(() => feed = []);
      return;
    }
    if (mounted) setState(() => feedLoading = true);
    try {
      final futures = all.take(15).map((s) => ext
          .channelUploads(s.channelUrl, limit: 3)
          .timeout(const Duration(seconds: 12),
              onTimeout: () => <VideoItem>[]));
      final chunks = await Future.wait(futures);
      if (mounted) {
        setState(() {
          feed = chunks.expand((e) => e).toList();
          feedLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => feedLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Лента не обновилась: $e')),
        );
      }
    }
  }

  Future<void> _addDialog() async {
    final ctl = TextEditingController();
    bool busy = false;
    String? err;
    await showDialog(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setD) => AlertDialog(
          title: const Text('Добавить канал'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctl,
                decoration: const InputDecoration(
                  labelText: 'Ссылка, UC-id, @handle или название',
                  hintText: 'https://www.youtube.com/@...\nМожно вставить NewPipe / Takeout / CSV',
                ),
                minLines: 1,
                maxLines: 6,
              ),
              if (err != null) ...[
                const SizedBox(height: 8),
                Text(err!,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(d),
                child: const Text('Отмена')),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final dialogNav = Navigator.of(d);
                      setD(() {
                        busy = true;
                        err = null;
                      });
                      try {
                        final text = ctl.text.trim();
                        if (text.isEmpty) throw ExtractorFailure('Вставь ссылку или название');
                        if (text.startsWith('[') ||
                            text.startsWith('{') ||
                            (text.contains('http') && text.contains('\n')) ||
                            text.startsWith('Channel Id')) {
                          final (count, format) =
                              await repo.importSmart(text);
                          dialogNav.pop();
                          messenger.showSnackBar(SnackBar(
                              content: Text(
                                  'Импортировано ($format): $count')));
                          _reload();
                          return;
                        }
                        final ch = await ext.resolveChannel(text);
                        if (ch.id.isEmpty) {
                          throw ExtractorFailure('Канал не распознан');
                        }
                        await repo.subscribe(ch.id, ch.name, ch.url);
                        dialogNav.pop();
                        messenger.showSnackBar(
                            SnackBar(content: Text('Подписался: ${ch.name}')));
                        _reload();
                      } catch (e) {
                        setD(() {
                          busy = false;
                          err = e.toString();
                        });
                      }
                    },
              child: busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Добавить'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmUnsub(Sub s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(s.name),
        content: const Text('Отписаться от канала?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Нет')),
          FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Да')),
        ],
      ),
    );
    if (ok == true) {
      await repo.unsubscribe(s.id);
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const VideoListSkeleton(count: 3);
    if (error != null) {
      return AppErrorView(message: error!, onRetry: _reload);
    }
    return Column(
      children: [
        SizedBox(
          height: 104,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: subs.length + 1,
            itemBuilder: (_, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    children: [
                      IconButton.filledTonal(
                        tooltip: 'Добавить канал',
                        icon: const Icon(Icons.add),
                        onPressed: _addDialog,
                      ),
                      const SizedBox(height: 4),
                      const Text('Добавить',
                          style: TextStyle(fontSize: 12)),
                    ],
                  ),
                );
              }
              final s = subs[i - 1];
              return InkWell(
                onLongPress: () => _confirmUnsub(s),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(children: [
                    ChannelAvatar(name: s.name),
                    const SizedBox(height: 4),
                    SizedBox(
                        width: 72,
                        child: Text(s.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style:
                                const TextStyle(fontSize: 12))),
                  ]),
                ),
              );
            },
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: subs.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.subscriptions_outlined,
                            size: 48,
                            color: Theme.of(context)
                                .colorScheme
                                .outline),
                        const SizedBox(height: 12),
                        const Text(
                          'Нет подписок.\nНажми «+» сверху: ссылка, название или вставка NewPipe / Takeout / CSV.\nВсё хранится локально, без Google-входа.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        FilledButton.tonal(
                          onPressed: _addDialog,
                          child: const Text('Добавить канал'),
                        ),
                      ],
                    ),
                  ),
                )
              : feedLoading
                  ? const VideoListSkeleton(count: 4)
                  : feed.isEmpty
                      ? const Center(
                          child: Text('Лента пуста — потяни вниз'))
                      : RefreshIndicator(
                          onRefresh: () => _loadFeed(subs),
                          child: ListView.builder(
                            itemCount: feed.length,
                            itemBuilder: (_, i) {
                              final v = feed[i];
                              return ListTile(
                                leading: _thumb(v.thumb),
                                title: Text(v.title,
                                    maxLines: 2,
                                    overflow:
                                        TextOverflow.ellipsis),
                                subtitle: Text(
                                    '${v.channel}${v.views != null ? ' • ${fmtViews(v.views)}' : ''}${v.date.isNotEmpty ? ' • ${fmtDate(v.date)}' : ''}',
                                    maxLines: 1,
                                    overflow:
                                        TextOverflow.ellipsis),
                                trailing: v.isShort
                                    ? const Icon(Icons.bolt,
                                        size: 16)
                                    : null,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          PlayerScreen(
                                              videoUrl: v.url,
                                              title: v.title)),
                                ),
                              );
                            },
                          ),
                        ),
        ),
      ],
    );
  }

  Widget _thumb(String url) => SizedBox(
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
