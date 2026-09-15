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
  if (s.toLowerCase().contains('network') || s.toLowerCase().contains('socket') || s.toLowerCase().contains('host')) {
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
    this.isShort = false,
    this.duration,
    this.views,
  });
}

class ResolvedStream {
  final String title;
  final String uploader;
  final String streamUrl;
  final String resolution;
  final int? views;
  final int? duration;
  const ResolvedStream({
    required this.title,
    required this.uploader,
    required this.streamUrl,
    required this.resolution,
    this.views,
    this.duration,
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

class ExtractorService {
  List<VideoItem> _map(List<StreamInfoItem> items) => items
      .map((e) {
        final url = e.url ?? '';
        final id = (e.id?.isNotEmpty == true) ? e.id! : idFromUrl(url);
        return VideoItem(
          id: id,
          url: url.isEmpty ? watchUrl(id) : url,
          title: (e.name?.isNotEmpty == true) ? e.name! : 'Без названия',
          channel: e.uploaderName ?? '',
          channelUrl: e.uploaderUrl ?? '',
          thumb: e.thumbnails.isNotEmpty ? e.thumbnails.last : '',
          isShort: e.isShort,
          duration: e.duration,
          views: e.viewCount,
        );
      })
      .where((v) => v.id.isNotEmpty)
      .toList();

  Future<List<VideoItem>> trending() async {
    try {
      final page = await TrendingExtractor.getTrendingVideos();
      return _map(page.items).where((v) => !v.isShort).toList();
    } catch (e) {
      throw ExtractorFailure(_msg(e));
    }
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

  /// Лента Shorts: поиск #shorts, только isShort.
  Future<List<VideoItem>> shortsFeed() async {
    try {
      var page = await SearchExtractor.searchYoutube('#shorts', [SearchFilter.videos.value]);
      var items = _map(page.result.videos).where((v) => v.isShort).toList();
      if (items.isEmpty) {
        page = await SearchExtractor.searchYoutube('shorts', [SearchFilter.videos.value]);
        items = _map(page.result.videos).where((v) => v.isShort).toList();
      }
      return items;
    } catch (e) {
      throw ExtractorFailure(_msg(e));
    }
  }

  /// Прямой муксированный mp4-поток для video_player.
  Future<ResolvedStream> resolveStream(String videoUrl) async {
    try {
      final v = await VideoExtractor.getStream(videoUrl);
      final info = v.videoInfo;
      final muxed = v.videoStreams;
      if (muxed.isEmpty) {
        throw ExtractorFailure('Нет прямого потока (live/DASH beta не умеет)');
      }
      VideoStream? pick;
      final mp4 = muxed.where((s) =>
          (s.formatSuffix?.toLowerCase().contains('mp4') ?? false) ||
          (s.formatMimeType?.toLowerCase().contains('mp4') ?? false)).toList();
      final pool = mp4.isNotEmpty ? mp4 : muxed;
      for (final want in ['720', '480', '360']) {
        for (final s in pool) {
          if ((s.resolution ?? '').contains(want)) {
            pick = s;
            break;
          }
        }
        if (pick != null) break;
      }
      pick ??= pool.first;
      final url = pick.url;
      if (url == null || url.isEmpty) throw ExtractorFailure('Поток без URL');
      return ResolvedStream(
        title: info.name ?? '',
        uploader: info.uploaderName ?? '',
        streamUrl: url,
        resolution: pick.resolution ?? '',
        views: info.viewCount,
        duration: info.length,
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
