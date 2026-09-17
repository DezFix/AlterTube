import 'package:flutter/material.dart';
import '../../core/extractor/extractor_service.dart';
import 'channel_avatar.dart';

// Плотная карточка видео в стиле YouTube: превью на всю ширину,
// бейдж длительности, аватар + название + канал • просмотры • дата.
// Просмотренное — тонкий прогресс + приглушённый заголовок вместо галочки.
// Первое появление — мягкий fade+подъём (один раз на видео, дальше без анимаций).
class VideoCard extends StatelessWidget {
  static final Set<String> _shown = {};

  final VideoItem video;
  final bool watched;
  final VoidCallback onTap;
  const VideoCard({
    super.key,
    required this.video,
    this.watched = false,
    required this.onTap,
  });

  String _sub() {
    final parts = <String>[video.channel];
    if (video.views != null) parts.add(fmtViews(video.views));
    if (video.date.isNotEmpty) parts.add(fmtDate(video.date));
    return parts.where((e) => e.isNotEmpty).join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_shown.length > 500) _shown.clear();
    final fresh = _shown.add(video.id);
    final card = InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                video.thumb.isEmpty
                    ? ColoredBox(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.play_circle, size: 48),
                      )
                    : Image.network(
                        video.thumb,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => ColoredBox(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.play_circle, size: 48),
                        ),
                      ),
                if ((video.duration ?? 0) > 0)
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        fmtDuration(video.duration),
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ),
                if (video.isShort)
                  const Positioned(
                    left: 8,
                    bottom: 8,
                    child: _ShortsBadge(),
                  ),
              ],
            ),
          ),
          if (watched)
            LinearProgressIndicator(
              value: 1.0,
              minHeight: 2,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(
                  theme.colorScheme.outline),
            ),
          ListTile(
            leading: ChannelAvatar(
                name: video.channel, avatarUrl: video.avatar),
            title: Text(
              video.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: watched
                  ? theme.textTheme.titleMedium
                      ?.copyWith(color: theme.colorScheme.outline)
                  : theme.textTheme.titleMedium,
            ),
            subtitle: Text(_sub(),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
    if (!fresh) return card;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 280),
      builder: (_, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - v)),
          child: child,
        ),
      ),
      child: card,
    );
  }
}

class _ShortsBadge extends StatelessWidget {
  const _ShortsBadge();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt, color: Colors.white, size: 12),
          SizedBox(width: 2),
          Text('Shorts',
              style: TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ),
    );
  }
}
