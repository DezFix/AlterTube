import 'package:flutter/material.dart';
import '../../core/extractor/extractor_service.dart';
import '../../core/subs/subscriptions_repository.dart';
import '../player/player_screen.dart';

// Подписки без Google-входа: локальное хранение + лента из загрузок каналов.
// Добавление: ссылка/UC-id/@handle/название или вставка Takeout-JSON.

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
  bool feedLoading = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final all = await repo.load();
    if (mounted) setState(() => subs = all);
    _loadFeed(all);
  }

  Future<void> _loadFeed(List<Sub> all) async {
    if (all.isEmpty) {
      if (mounted) setState(() => feed = []);
      return;
    }
    setState(() => feedLoading = true);
    final out = <VideoItem>[];
    for (final s in all.take(15)) {
      final up = await ext.channelUploads(s.channelUrl, limit: 3);
      for (final v in up) {
        out.add(v);
      }
      await Future.delayed(const Duration(milliseconds: 400)); // вежливо к YouTube
    }
    if (mounted) {
      setState(() {
        feed = out;
        feedLoading = false;
      });
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
                  hintText: 'https://www.youtube.com/@...',
                ),
                minLines: 1,
                maxLines: 4,
              ),
              if (err != null) ...[
                const SizedBox(height: 8),
                Text(err!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
          actions: [
            TextButton(
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
                        if (text.startsWith('[') || text.startsWith('{')) {
                          final n = await repo.importTakeoutJson(text);
                          dialogNav.pop();
                          messenger.showSnackBar(
                              SnackBar(content: Text('Импортировано: $n')));
                          _reload();
                          return;
                        }
                        final ch = await ext.resolveChannel(text);
                        if (ch.id.isEmpty) throw ExtractorFailure('Канал не распознан');
                        await repo.subscribe(ch.id, ch.name, ch.url);
                        dialogNav.pop();
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
                      width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Добавить'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 96,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: subs.length + 1,
            itemBuilder: (_, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.all(8),
                  child: ActionChip(label: const Text('+ Добавить'), onPressed: _addDialog),
                );
              }
              final s = subs[i - 1];
              return InkWell(
                onLongPress: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (d) => AlertDialog(
                      title: Text(s.name),
                      content: const Text('Отписаться?'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(d, false),
                            child: const Text('Нет')),
                        TextButton(
                            onPressed: () => Navigator.pop(d, true),
                            child: const Text('Да')),
                      ],
                    ),
                  );
                  if (ok == true) {
                    await repo.unsubscribe(s.id);
                    _reload();
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(children: [
                    CircleAvatar(child: Text(s.name.isNotEmpty ? s.name[0] : '?')),
                    const SizedBox(height: 4),
                    SizedBox(
                        width: 72,
                        child: Text(s.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center)),
                  ]),
                ),
              );
            },
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: subs.isEmpty
              ? const Center(
                  child: Text(
                      'Нет подписок.\nНажми «+ Добавить» или вставь Takeout-JSON.\nОтписка — долгим нажатием на аватар.'))
              : feedLoading
                  ? const Center(child: CircularProgressIndicator())
                  : feed.isEmpty
                      ? const Center(child: Text('Лента пуста'))
                      : RefreshIndicator(
                          onRefresh: () => _loadFeed(subs),
                          child: ListView.builder(
                            itemCount: feed.length,
                            itemBuilder: (_, i) {
                              final v = feed[i];
                              return ListTile(
                                leading: v.thumb.isEmpty
                                    ? const Icon(Icons.play_circle)
                                    : Image.network(v.thumb,
                                        width: 96, height: 54, fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            const Icon(Icons.play_circle)),
                                title: Text(v.title,
                                    maxLines: 2, overflow: TextOverflow.ellipsis),
                                subtitle: Text(
                                    '${v.channel}${v.views != null ? ' • ${fmtViews(v.views)}' : ''}'),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          PlayerScreen(videoUrl: v.url, title: v.title)),
                                ),
                              );
                            },
                          ),
                        ),
        ),
      ],
    );
  }
}
