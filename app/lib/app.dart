import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/settings/app_settings.dart';
import 'core/theme/app_theme.dart';
import 'features/videos/videos_tab.dart';
import 'features/shorts/shorts_tab.dart';
import 'features/subs/subs_tab.dart';
import 'features/welcome/welcome_screen.dart';
import 'features/search/tube_search.dart';
import 'features/settings/settings_screen.dart';
import 'core/extractor/extractor_service.dart';

class AlterTubeApp extends StatelessWidget {
  const AlterTubeApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppSettings>();
    return MaterialApp(
      title: 'AlterTube',
      themeMode: theme.themeMode,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(amoled: theme.amoled),
      home: const _Root(),
    );
  }
}

/// Первый запуск — Welcome, дальше сразу контент.
class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final done = context.watch<AppSettings>().welcomeDone;
    return done ? const HomeShell() : const WelcomeScreen();
  }
}

// Три экрана: видео, Shorts, подписки. Остальное вернётся по одной функции.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;

  @override
  void initState() {
    super.initState();
    // Применяем регион контента один раз при старте.
    final region = context.read<AppSettings>().region;
    ExtractorService().applyRegion(region);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AlterTube'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Поиск',
            onPressed: () =>
                showSearch(context: context, delegate: TubeSearch()),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Меню',
            onSelected: (v) {
              if (v == 'settings') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const SettingsScreen()),
                );
              } else if (v == 'about') {
                showAboutDialog(
                  context: context,
                  applicationName: 'AlterTube',
                  applicationVersion: '0.4.0 beta',
                  applicationLegalese:
                      'GPL-3.0. Форк-подход: NewPipe/PipePipe + SponsorBlock.',
                );
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'settings', child: Text('Настройки')),
              PopupMenuItem(value: 'about', child: Text('О приложении')),
            ],
          ),
        ],
      ),
      body: IndexedStack(
        index: index,
        children: const [VideosTab(), ShortsTab(), SubsTab()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.play_arrow_outlined),
              selectedIcon: Icon(Icons.play_arrow),
              label: 'Видео'),
          NavigationDestination(
              icon: Icon(Icons.bolt_outlined),
              selectedIcon: Icon(Icons.bolt),
              label: 'Shorts'),
          NavigationDestination(
              icon: Icon(Icons.subscriptions_outlined),
              selectedIcon: Icon(Icons.subscriptions),
              label: 'Подписки'),
        ],
      ),
    );
  }
}
