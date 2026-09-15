import 'package:flutter/material.dart';

// Человеческое состояние ошибки: иконка + текст + кнопка повтора.
// Заменяет разрозненные Center(Text(error)) по всем табам.
class AppErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final IconData icon;
  const AppErrorView({
    super.key,
    required this.message,
    required this.onRetry,
    this.icon = Icons.cloud_off_outlined,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Повторить')),
          ],
        ),
      ),
    );
  }
}

// Статичный скелетон ленты: 6 серых карточек без анимации.
// Без новых зависимостей (без shimmer-пакета) — просто плейсхолдеры.
class VideoListSkeleton extends StatelessWidget {
  final int count;
  const VideoListSkeleton({super.key, this.count = 6});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.surfaceContainerHighest;
    return ListView.builder(
      itemCount: count,
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ColoredBox(color: c),
            ),
            ListTile(
              leading: CircleAvatar(backgroundColor: c),
              title: Container(height: 14, color: c),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Container(height: 12, color: c),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
