import 'dart:convert';
import 'package:http/http.dart' as http;

import '../timetable_provider.dart';

// Represents one node from `tree.add(id, pid, 'label', 'link')`.
class _TreeNode {
  final int id;
  final int pid;
  final String name; // label right side (course/track name)
  final String? code; // normalized like SWE444 (if present on left)
  final String? indexPath; // value inside setIndex('...') if present

  _TreeNode({
    required this.id,
    required this.pid,
    required this.name,
    required this.code,
    required this.indexPath,
  });
}

/// Extract `tree.add(...)` nodes from the page HTML.
/// Mirrors the Python approach: robust label/link capture and index path parse.
List<_TreeNode> parseTreeAddNodes(String html) {
  // tree.add(id, pid, 'label'[, 'link' or "link"]) ; possibly across lines
  final treeRe = RegExp(
    r'tree\.add\('
    r"\s*(-?\d+)\s*,\s*(-?\d+)\s*,\s*"
    r"'((?:\\'|[^'])+?)'"
    r"(?:,\s*(?:"
    r"'([^']*)'"
    r'|"([^"]*)"))?\s*\);',
    dotAll: true,
  );
  final indexRe = RegExp(r"setIndex\('([^']+)'\)");

  final nodes = <_TreeNode>[];
  for (final m in treeRe.allMatches(html)) {
    final id = int.parse(m.group(1)!);
    final pid = int.parse(m.group(2)!);
    final rawLabel = (m.group(3) ?? '').replaceAll("\\'", "'").trim();
    final link = (m.group(4) ?? m.group(5) ?? '').trim();
    final idxm = indexRe.firstMatch(link);
    final indexPath = idxm != null ? idxm.group(1) : null;

    String? code;
    String name = rawLabel;
    final dash = rawLabel.indexOf('-');
    if (dash > 0) {
      final left = rawLabel.substring(0, dash).trim();
      final right = rawLabel.substring(dash + 1).trim();
      // Accept forms like SWE444 or SWE 444 (2-4 letters + 2-4 digits)
      final cm = RegExp(r'^[A-Za-z]{2,4}\s?\d{2,4}$').firstMatch(left);
      if (cm != null) {
        code = left.replaceAll(' ', '').toUpperCase();
        name = right;
      }
    }

    nodes.add(_TreeNode(id: id, pid: pid, name: name, code: code, indexPath: indexPath));
  }
  return nodes;
}

/// Build quick parent->children index and ensure every id key exists.
Map<int, List<int>> buildChildren(List<_TreeNode> nodes) {
  final kids = <int, List<int>>{};
  for (final n in nodes) {
    kids.putIfAbsent(n.pid, () => <int>[]).add(n.id);
    kids.putIfAbsent(n.id, () => <int>[]);
  }
  return kids;
}

/// Flatten leaf rows in the same shape as the CSV in the Python script.
/// campus/degree are placeholders (page-scoped), but college/major/track are derived.
List<Map<String, String?>> extractProgramIndexRows(String html) {
  final nodes = parseTreeAddNodes(html);
  if (nodes.isEmpty) return const [];
  final byId = {for (final n in nodes) n.id: n};
  final kids = buildChildren(nodes);

  final rows = <Map<String, String?>>[];
  for (final collegeId in kids[0] ?? const <int>[]) {
    final college = byId[collegeId]?.name ?? '';
    for (final majorId in kids[collegeId] ?? const <int>[]) {
      final major = byId[majorId]?.name;
      final majorKids = kids[majorId] ?? const <int>[];
      if (majorKids.isEmpty) {
        final n = byId[majorId]!;
        rows.add({
          'campus': '(current campus)',
          'degree': '(current degree)',
          'college': college,
          'major': null,
          'track_name': n.name,
          'program_code': n.code,
          'index_path': n.indexPath,
        });
      } else {
        for (final trackId in majorKids) {
          final n = byId[trackId]!;
          rows.add({
            'campus': '(current campus)',
            'degree': '(current degree)',
            'college': college,
            'major': major,
            'track_name': n.name,
            'program_code': n.code,
            'index_path': n.indexPath,
          });
        }
      }
    }
  }
  return rows;
}

typedef UrlBuilder = Uri Function({
  String? courseCode,
  required String section,
});

/// Skeleton provider for scraping a timetable HTML/JSON endpoint.
/// Configure with a [UrlBuilder] and parsing callback.
class HtmlTimetableProvider implements TimetableProvider {
  final UrlBuilder urlBuilder;
  /// If the endpoint returns JSON, supply a parser. If HTML, adapt accordingly.
  final TimetableResult? Function(String body, Map<String, String> ctx) parse;
  final Map<String, String> defaultHeaders;

  HtmlTimetableProvider({
    required this.urlBuilder,
    required this.parse,
    this.defaultHeaders = const {},
  });

  @override
  Future<TimetableResult?> fetch({
    String? courseCode,
    required String section,
  }) async {
    final uri = urlBuilder(
      courseCode: courseCode,
      section: section,
    );

    final res = await http.get(uri, headers: defaultHeaders);
    if (res.statusCode != 200) {
      throw Exception('FETCH_FAILED ${res.statusCode}');
    }
    final body = utf8.decode(res.bodyBytes);
    return parse(body, {
      'courseCode': courseCode ?? '',
      'section': section,
      'url': uri.toString(),
    });
  }
}

