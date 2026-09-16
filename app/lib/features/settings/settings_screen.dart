import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/history/history_repository.dart';
import '../../core/settings/app_settings.dart';
import '../../core/extractor/extractor_service.dart';
import '../../core/subs/subscriptions_repository.dart';

// Настройки beta: тема, регион, SponsorBlock, backend, данные.

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSettings>();
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        children: [
          const _Header('Внешний вид'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('Система')),
                ButtonSegment(value: ThemeMode.light, label: Text('Светлая')),
                ButtonSegment(value: ThemeMode.dark, label: Text('Тёмная')),
              ],
              selected: {s.themeMode},
              onSelectionChanged: (v) =>
                  context.read<AppSettings>().setTheme(v.first),
            ),
          ),
          SwitchListTile(
            title: const Text('AMOLED-чёрный'),
            subtitle: const Text('Чисто чёрный фон в тёмной теме'),
            value: s.amoled,
            onChanged: (v) =>
                context.read<AppSettings>().setAmoled(v),
          ),
          const _Header('Контент'),
          ListTile(
            title: const Text('Регион'),
            subtitle: const Text('Влияет на тренды и поиск'),
            trailing: DropdownButton<String>(
              value: s.region,
              items: AppSettings.regions
                  .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                  .toList(),
              onChanged: (v) async {
                if (v == null) return;
                await context.read<AppSettings>().setRegion(v);
                await ExtractorService().applyRegion(v);
              },
            ),
          ),
          const _Header('Лента'),
          SwitchListTile(
            title: const Text('Лента под подписки'),
            subtitle: const Text('Видео подстраиваются под подписки и просмотры'),
            value: s.personalizedFeed,
            onChanged: (v) =>
                context.read<AppSettings>().setPersonalizedFeed(v),
          ),
          const _Header('SponsorBlock'),
          SwitchListTile(
            title: const Text('Пропускать сегменты'),
            value: s.sbEnabled,
            onChanged: (v) => context.read<AppSettings>().setSb(v),
          ),
          ...AppSettings.allCategories.map(
            (c) => CheckboxListTile(
              title: Text(c),
              value: s.sbCategories.contains(c),
              enabled: s.sbEnabled,
              onChanged: (v) => context.read<AppSettings>().toggleCategory(c, v ?? false),
            ),
          ),
          const _Header('Backend (необязательно)'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextFormField(
              initialValue: s.backendUrl,
              decoration: const InputDecoration(
                labelText: 'URL Flask-компаньона',
                hintText: 'http://192.168.1.5:5000',
                helperText: 'Пусто = запросы идут напрямую к sponsor.ajay.app',
              ),
              onChanged: (v) => context.read<AppSettings>().setBackend(v),
              onFieldSubmitted: (v) =>
                  context.read<AppSettings>().setBackend(v),
            ),
          ),
          const _Header('Данные'),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Удалить все подписки'),
            onTap: () async {
              await SubscriptionsRepository().clear();
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Подписки удалены')));
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.history_toggle_off),
            title: const Text('Очистить историю и индекс'),
            subtitle: const Text('Сбросит подборку ленты под тебя'),
            onTap: () async {
              await HistoryRepository().clear();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('История очищена')));
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.restart_alt),
            title: const Text('Сбросить настройки'),
            onTap: () => context.read<AppSettings>().resetAll(),
          ),
          const _Header('О проекте'),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'AlterTube 0.4.0 beta, GPL-3.0.\n'
              'Ядро извлечения: NewPipe Extractor (TeamNewPipe) через newpipeextractor_dart.\n'
              'Пропуск сегментов: SponsorBlock. Без Google-входа и без официальной рекламы.',
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );
}
