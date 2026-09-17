import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../../core/settings/app_settings.dart';
// Welcome при первом запуске: кто мы, что умеем, какие доступы нужны.
// Всё необязательно — дальше пускаем в любом случае.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});
  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final pager = PageController();
  int page = 0;
  PermissionStatus notif = PermissionStatus.denied;
  PermissionStatus videos = PermissionStatus.denied;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    pager.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final n = await Permission.notification.status;
    final v = await Permission.videos.status;
    if (!mounted) return;
    setState(() {
      notif = n;
      videos = v;
    });
  }

  Future<void> _finish() async {
    await context.read<AppSettings>().setWelcomeDone();
  }

  String _label(PermissionStatus s) => switch (s) {
        PermissionStatus.granted || PermissionStatus.limited => 'Разрешено ✓',
        PermissionStatus.permanentlyDenied => 'Запрещено в системе',
        _ => 'Не запрошено',
      };

  @override
  Widget build(BuildContext context) {
    final last = page == 2;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _finish,
                child: const Text('Пропустить'),
              ),
            ),
            Expanded(
              child: PageView(
                controller: pager,
                onPageChanged: (i) => setState(() => page = i),
                children: [
                  const _Page(
                    icon: Icons.play_circle_filled,
                    title: 'AlterTube',
                    text:
                        'Лёгкие видео без Google-входа и рекламы.\nПодписки и история живут только на телефоне.',
                  ),
                  const _Page(
                    icon: Icons.bolt,
                    title: 'Видео и Shorts',
                    text:
                        'Лента трендов, вертикальные Shorts с автопрокруткой,\nплеер с качеством, скоростью и пропуском спонсорки.',
                  ),
                  _AccessPage(
                    notif: _label(notif),
                    videos: _label(videos),
                    onNotif: () async {
                      await Permission.notification.request();
                      _refresh();
                    },
                    onVideos: () async {
                      await Permission.videos.request();
                      _refresh();
                    },
                  ),
                ],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                3,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.all(4),
                  width: page == i ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: page == i
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: FilledButton(
                onPressed: last
                    ? _finish
                    : () => pager.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut),
                child: Text(last ? 'Начать смотреть' : 'Далее'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  const _Page(
      {required this.icon, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon,
              size: 96, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 24),
          Text(title,
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text(text,
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _AccessPage extends StatelessWidget {
  final String notif;
  final String videos;
  final VoidCallback onNotif;
  final VoidCallback onVideos;
  const _AccessPage({
    required this.notif,
    required this.videos,
    required this.onNotif,
    required this.onVideos,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Доступы',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text('Нужны для будущих функций —\nфон и загрузки. Можно позже.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center),
          const SizedBox(height: 24),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Уведомления'),
            subtitle: Text(notif),
            trailing: const Icon(Icons.chevron_right),
            onTap: onNotif,
          ),
          ListTile(
            leading: const Icon(Icons.video_library_outlined),
            title: const Text('Видео и файлы'),
            subtitle: Text(videos),
            trailing: const Icon(Icons.chevron_right),
            onTap: onVideos,
          ),
        ],
      ),
    );
  }
}
