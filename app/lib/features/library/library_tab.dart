import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/history/history_repository.dart';
import '../../core/settings/app_settings.dart';
import '../../core/subs/subscriptions_repository.dart';
import '../../core/extractor/extractor_service.dart';
import '../../core/widgets/app_states.dart';
import '../player/player_screen.dart';
import '../settings/settings_screen.dart';

// Библиотека: история просмотров + быстрые действия.
// История хранит только videoId, поэтому показываем компактный список
// с переходом в плеер (название подтянется там).
class LibraryTab extends StatefulWidget {
  const LibraryTab({super.key});
  @override
  State<LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends State<LibraryTab> {
  final histRepo = HistoryRepository();
  final subsRepo = SubscriptionsRepository();
  List<String> recent = [];
  int subsCount = 0;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    final ids = await histRepo.recentIds();
    final subs = await subsRepo.load();
    if (!mounted) return;
    setState(() {
      recent = ids.toList().reversed.toList();
      subsCount = subs.length;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const VideoListSkeleton(count: 3);
    final s = context.watch<AppSettings>();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Библиотека',
                style: Theme.of(context).textTheme.headlineSmall),
          ),
          ListTile(
            leading: const Icon(Icons.subscriptions_outlined),
            title: const Text('Подписки'),
            subtitle: Text('$subsCount каналов'),
          ),
          ListTile(
            leading: const Icon(Icons.dark_mode_outlined),
            title: const Text('AMOLED-чёрный'),
            subtitle: Text(s.amoled ? 'Включён' : 'Выключен'),
            trailing: Switch(
              value: s.amoled,
              onChanged: (v) =>
                  context.read<AppSettings>().setAmoled(v),
            ),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Text('История (${recent.length})',
                    style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                if (recent.isNotEmpty)
                  TextButton(
                    onPressed: () async {
                      await histRepo.clear();
                      _load();
                    },
                    child: const Text('Очистить'),
                  ),
              ],
            ),
          ),
          if (recent.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Пока пусто. Открой любое видео — оно появится здесь.',
                textAlign: TextAlign.center,
              ),
            )
          else
            ...recent.take(50).map(
              (id) => ListTile(
                leading: const Icon(Icons.history),
                title: Text(id,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.play_arrow),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PlayerScreen(
                        videoUrl: watchUrl(id), title: id),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
