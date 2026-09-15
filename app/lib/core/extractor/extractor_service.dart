import 'package:newpipeextractor_dart/newpipeextractor_dart.dart';

// Единая точка доступа к NewPipe Extractor.
// Все методы кидают ExtractorFailure с человеческим текстом — UI показывает retry.

class ExtractorFailure implements Exception {
  final String message;
  ExtractorFailure(this.message);
  @override
  String toString() => message;
}

String _msg(Object e) {
  final s = e.toString();
  if (s.contains('429') || s.toLowerCase().contains('rate')) {
    return 'YouTube ограничил запросы (429). Подожди минуту и обнови.';
  }
  if (s.toLowerCase().contains('network') ||
      s.toLowerCase().contains('socket') ||
      s.toLowerCase().contains('host')) {
    return 'Нет сети. Проверь интернет в эмуляторе.';
  }
  return 'Экстрактор сломался (YouTube что-то поменял): $s';
}

class VideoItem {
  final String id;
  final String url;
  final String title;
  final String channel;
  final String channelUrl;
  final String thumb;
  final String avatar;
  final String date;
  final bool isShort;
  final int? duration;
  final int? views;
  const VideoItem({
    required this.id,
    required this.url,
    required this.title,
    required this.channel,
    required this.channelUrl,
    required this.thumb,
    this.avatar = '',
    this.date = '',
    this.isShort = false,
    this.duration,
    this.views,
  });
}

class StreamOption {
  final String label;
  final String url;
  const StreamOption({required this.label, required this.url});
}

class ResolvedStream {
  final String title;
  final String uploader;
  final String uploaderUrl;
  final String streamUrl;
  final String resolution;
  final int? views;
  final int? duration;
  final List<StreamOption> muxed;
  final String? dashUrl;
  final String? hlsUrl;
  final bool isLive;
  const ResolvedStream({
    required this.title,
    required this.uploader,
    this.uploaderUrl = '',
    required this.streamUrl,
    required this.resolution,
    required this.muxed,
    this.views,
    this.duration,
    this.dashUrl,
    this.hlsUrl,
    this.isLive = false,
  });
}

class Chapter {
  final String title;
  final int start;
  const Chapter({required this.title, required this.start});
}

class YtComment {
  final String author;
  final String text;
  final int likes;
  final String avatar;
  final int replies;
  const YtComment({
    required this.author,
    required this.text,
    required this.likes,
    required this.avatar,
    required this.replies,
  });
}

String watchUrl(String id) => 'https://www.youtube.com/watch?v=$id';

String idFromUrl(String url) {
  for (final re in [
    RegExp(r'[?&]v=([\w-]{6,})'),
    RegExp(r'youtu\.be/([\w-]{6,})'),
    RegExp(r'shorts/([\w-]{6,})'),
    RegExp(r'live/([\w-]{6,})'),
  ]) {
    final m = re.firstMatch(url);
    if (m != null) return m.group(1)!;
  }
  return url;
}

String fmtDuration(int? s) {
  if (s == null) return '';
  final m = s ~/ 60;
  final sec = (s % 60).toString().padLeft(2, '0');
  if (m >= 60) return '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}:$sec';
  return '$m:$sec';
}

String fmtViews(int? v) {
  if (v == null) return '';
  if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
  if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
  return '$v';
}

/// "2026-09-15T01:30:10+00:00" -> "5 мин назад", "вчера", "12.09.2026".
/// Нераспознанное возвращает как есть.
String fmtDate(String raw) {
  if (raw.isEmpty) return '';
  final dt = DateTime.tryParse(raw);
  if (dt == null) return raw;
  final diff = DateTime.now().difference(dt.toLocal());
  if (diff.isNegative || diff.inSeconds < 30) return 'только что';
  if (diff.inMinutes < 60) return '${diff.inMinutes} ${_plural(diff.inMinutes, 'минуту', 'минуты', 'минут')} назад';
  if (diff.inHours < 24) {
    return '${diff.inHours} ${_plural(diff.inHours, 'час', 'часа', 'часов')} назад';
  }
  if (diff.inDays == 1) return 'вчера';
  if (diff.inDays < 7) {
    return '${diff.inDays} ${_plural(diff.inDays, 'день', 'дня', 'дней')} назад';
  }
  final l = dt.toLocal();
  return '${l.day.toString().padLeft(2, '0')}.${l.month.toString().padLeft(2, '0')}.${l.year}';
}

String _plural(int n, String one, String few, String many) {
  final m10 = n % 10;
  final m100 = n % 100;
  if (m10 == 1 && m100 != 11) return one;
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return few;
  return many;
}

class ExtractorService {
  List<VideoItem> _map(List<StreamInfoItem> items) => items
      .map((e) {
        final url = e.url ?? '';
        final id = (e.id?.isNotEmpty == true) ? e.id! : idFromUrl(url);
        final thumbs = e.thumbnails;
        final avatars = e.uploaderAvatars;
        return VideoItem(
          id: id,
          url: url.isEmpty ? watchUrl(id) : url,
          title: (e.name?.isNotEmpty == true) ? e.name! : 'Без названия',
          channel: e.uploaderName ?? '',
          channelUrl: e.uploaderUrl ?? '',
          thumb: thumbs.isNotEmpty ? thumbs.last : '',
          avatar: avatars.isNotEmpty ? avatars.last : '',
          date: e.uploadDate ?? '',
          isShort: e.isShort,
          duration: e.duration,
          views: e.viewCount,
        );
      })
      .where((v) => v.id.isNotEmpty)
      .toList();

  Future<List<VideoItem>> trending() async {
    final p = await trendingPage(null);
    return p.items;
  }

  Future<({List<VideoItem> items, dynamic next})> trendingPage(dynamic next) async {
    try {
      final page = next == null
          ? await TrendingExtractor.getTrendingVideos()
          : await TrendingExtractor.getTrendingNextPage(next);
      return (items: _map(page.items).where((v) => !v.isShort).toList(), next: page.next);
    } catch (e) {
      throw ExtractorFailure(_msg(e));
    }
  }

  Future<List<VideoItem>> search(String q) async {
    try {
      final page = await SearchExtractor.searchYoutube(q, [SearchFilter.videos.value]);
      return _map(page.result.videos);
    } catch (e) {
      throw ExtractorFailure(_msg(e));
    }
  }

  Future<List<String>> suggestions(String q) async {
    try {
      return await SearchExtractor.getSearchSuggestions(q);
    } catch (_) {
      return [];
    }
  }

  /// Лента Shorts: несколько стратегий по порядку, первая непустая побеждает.
  /// 1) киоск Shorts (если есть), 2) поиск + isShort, 3) поиск + длительность <=65с.
  Future<List<VideoItem>> shortsFeed() async {
    try {
      // 1) киоски
      try {
        final kiosks = await TrendingExtractor.listKiosks();
        for (final k in kiosks) {
          if (k.toLowerCase().contains('short')) {
            final page = await TrendingExtractor.getKioskContent(k);
            final items = _map(page.items).where((v) => v.isShort || _likelyShort(v)).toList();
            if (items.isNotEmpty) return items;
          }
        }
      } catch (_) {}
      // 2) поиск с флагом isShort
      for (final q in ['#shorts', 'shorts']) {
        final page = await SearchExtractor.searchYoutube(q, [SearchFilter.videos.value]);
        final items = _map(page.result.videos).where((v) => v.isShort).toList();
        if (items.isNotEmpty) return items;
        // 3) тот же поиск, но эвристика по длительности
        final approx = _map(page.result.videos).where(_likelyShort).toList();
        if (approx.isNotEmpty) return approx;
      }
      return [];
    } catch (e) {
      throw ExtractorFailure(_msg(e));
    }
  }

  bool _likelyShort(VideoItem v) => (v.duration ?? 9999) <= 65;

  /// Потоки для media_kit: сначала муксированный mp4, иначе DASH, иначе HLS (live).
  Future<ResolvedStream> resolveStream(String videoUrl) async {
    try {
      final v = await VideoExtractor.getStream(videoUrl);
      final info = v.videoInfo;
      final muxed = v.videoStreams
          .where((s) => (s.url?.isNotEmpty ?? false))
          .map((s) => StreamOption(label: s.resolution ?? '?', url: s.url!))
          .toList();
      // Предпочитаем mp4
      final mp4 = v.videoStreams
          .where((s) =>
              (s.url?.isNotEmpty ?? false) &&
              ((s.formatSuffix?.toLowerCase().contains('mp4') ?? false) ||
                  (s.formatMimeType?.toLowerCase().contains('mp4') ?? false)))
          .map((s) => StreamOption(label: s.resolution ?? '?', url: s.url!))
          .toList();
      final pool = mp4.isNotEmpty ? mp4 : muxed;
      String? pickUrl;
      String pickRes = '';
      for (final want in ['720', '480', '360']) {
        for (final s in pool) {
          if (s.label.contains(want)) {
            pickUrl = s.url;
            pickRes = s.label;
            break;
          }
        }
        if (pickUrl != null) break;
      }
      if (pickUrl == null && pool.isNotEmpty) {
        pickUrl = pool.first.url;
        pickRes = pool.first.label;
      }
      final dash = info.dashMpdUrl;
      final hls = info.hlsUrl;
      pickUrl ??= dash ?? hls;
      if (pickUrl == null || pickUrl.isEmpty) {
        throw ExtractorFailure('Нет потока для этого видео');
      }
      final live = info.streamType == StreamType.liveStream ||
          info.streamType == StreamType.audioLiveStream;
      return ResolvedStream(
        title: info.name ?? '',
        uploader: info.uploaderName ?? '',
        uploaderUrl: info.uploaderUrl ?? '',
        streamUrl: pickUrl,
        resolution: pickRes.isNotEmpty ? pickRes : (dash != null ? 'DASH' : 'LIVE'),
        views: info.viewCount,
        duration: info.length,
        muxed: pool,
        dashUrl: dash,
        hlsUrl: hls,
        isLive: live,
      );
    } on ExtractorFailure {
      rethrow;
    } catch (e) {
      throw ExtractorFailure(_msg(e));
    }
  }

  Future<List<VideoItem>> related(String videoUrl) async {
    try {
      final r = await VideoExtractor.getRelatedStreams(videoUrl);
      return _map(r.videos);
    } catch (_) {
      return [];
    }
  }

  Future<List<Chapter>> chapters(String videoUrl) async {
    try {
      final segs = await VideoExtractor.getVideoSegments(videoUrl);
      return segs
          .map((s) => Chapter(title: s.title ?? '', start: s.startTimeSeconds))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<YtComment>> comments(String videoUrl) async {
    try {
      final page = await CommentsExtractor.getComments(videoUrl);
      return _mapComments(page);
    } catch (_) {
      return [];
    }
  }

  Future<List<YtComment>> moreComments() async {
    try {
      final page = await CommentsExtractor.getNextCommentsPage();
      if (!page.hasNextPage && page.comments.isEmpty) return [];
      return _mapComments(page);
    } catch (_) {
      return [];
    }
  }

  List<YtComment> _mapComments(CommentsPage page) => page.comments
      .map((c) => YtComment(
            author: c.author ?? '',
            text: c.commentText ?? '',
            likes: c.likeCount ?? 0,
            avatar: c.uploaderAvatars.isNotEmpty ? c.uploaderAvatars.first : '',
            replies: c.replyCount,
          ))
      .toList();

  /// Принимает UC-id, @handle, ссылку или название → возвращает id|name|url.
  Future<({String id, String name, String url})> resolveChannel(String input) async {
    final q = input.trim();
    try {
      if (!q.startsWith('http') && !q.startsWith('UC') && !q.startsWith('@')) {
        final page = await SearchExtractor.searchYoutube(q, [SearchFilter.channels.value]);
        if (page.result.channels.isEmpty) throw ExtractorFailure('Канал не найден');
        final c = page.result.channels.first;
        return (id: c.url?.split('/').last ?? '', name: c.name ?? q, url: c.url ?? '');
      }
      final url = q.startsWith('http')
          ? q
          : q.startsWith('UC')
              ? 'https://www.youtube.com/channel/$q'
              : 'https://www.youtube.com/$q';
      final ch = await ChannelExtractor.getChannelInfo(url);
      return (id: ch.id ?? '', name: ch.name ?? q, url: ch.url ?? url);
    } on ExtractorFailure {
      rethrow;
    } catch (e) {
      throw ExtractorFailure(_msg(e));
    }
  }

  Future<List<VideoItem>> channelUploads(String channelUrl, {int limit = 5}) async {
    try {
      final page = await ChannelExtractor.getChannelUploads(channelUrl);
      return _map(page.items).take(limit).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> applyRegion(String region) async {
    // region: auto|RU|UA|US|DE
    try {
      switch (region) {
        case 'RU':
          await LocalizationExtractor.setLocalization('ru', 'RU');
        case 'UA':
          await LocalizationExtractor.setLocalization('uk', 'UA');
        case 'US':
          await LocalizationExtractor.setLocalization('en', 'US');
        case 'DE':
          await LocalizationExtractor.setLocalization('de', 'DE');
        default:
          break; // auto — системная локаль устройства
      }
    } catch (_) {}
  }
}
