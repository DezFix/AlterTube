import 'dart:convert';
import 'package:http/http.dart' as http;

// Минимальный клиент SponsorBlock.
// API: GET https://sponsor.ajay.app/api/skipSegments?videoID=xxx&categories=[sponsor]&actionTypes=[skip]
// Док: https://wiki.sponsor.ajay.app/w/API_Docs
// Upstream: PipePipe делает то же самое.

class SbSegment {
  final double start;
  final double end;
  final String category;
  const SbSegment({required this.start, required this.end, required this.category});
}

class SponsorBlockService {
  final String base;
  final Set<String> enabledCategories;
  final bool useProxy; // true = Flask-компаньон ($base/sb/skipSegments), false = напрямую
  SponsorBlockService({
    this.base = 'https://sponsor.ajay.app',
    this.enabledCategories = const {'sponsor', 'selfpromo', 'intro', 'outro', 'interaction'},
    this.useProxy = false,
  });

  Future<List<SbSegment>> fetch(String videoId) async {
    final cats = Uri.encodeComponent(enabledCategories.map((c) => '"$c"').join(','));
    final uri = useProxy
        ? Uri.parse('$base/sb/skipSegments?videoID=$videoId&categories=[$cats]')
        : Uri.parse(
            '$base/api/skipSegments?videoID=$videoId&categories=[$cats]&actionTypes=["skip"]');
    final r = await http.get(uri);
    if (r.statusCode == 404) return []; // сегментов нет — норма
    if (r.statusCode != 200) return [];
    final List data = jsonDecode(r.body) as List;
    return data.map((e) {
      final seg = (e['segment'] as List).map((x) => (x as num).toDouble()).toList();
      return SbSegment(start: seg[0], end: seg[1], category: e['category'] as String? ?? 'sponsor');
    }).toList();
  }

  /// Если позиция внутри сегмента — вернуть конец для seek, иначе null.
  double? shouldSkip(double pos, List<SbSegment> segs) {
    for (final s in segs) {
      if (pos >= s.start && pos < s.end - 0.3) return s.end;
    }
    return null;
  }
}
