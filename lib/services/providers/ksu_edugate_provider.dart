import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
import 'package:http/http.dart' as http;

import '../timetable_provider.dart';

/// Basic mapping for term strings like "2025-Fall" â†’ a rough date range.
/// Override by parsing exact dates if the portal exposes them.
({DateTime start, DateTime end}) currentTermRange() {
  // Heuristic: choose a reasonable academic window based on current month.
  final now = DateTime.now();
  final y = now.year;
  if (now.month >= 1 && now.month <= 5) {
    return (start: DateTime(y, 1, 1), end: DateTime(y, 5, 31));
  } else if (now.month >= 6 && now.month <= 8) {
    return (start: DateTime(y, 6, 1), end: DateTime(y, 8, 14));
  } else {
    return (start: DateTime(y, 8, 15), end: DateTime(y, 12, 31));
  }
}

/// Scraper for KSU Edugate guest timetable page.
/// Note: The JSF page may require dynamic form state. If the index page
/// does not contain the full table server-rendered, we will need either:
///  - a direct data endpoint (JSON/CSV), or
///  - to simulate the JSF form post sequence with hidden fields.
class KsuEdugateProvider implements TimetableProvider {
  final Uri baseUrl;
  final bool enableLogging;

  KsuEdugateProvider({Uri? baseUrl, this.enableLogging = false})
      : baseUrl = baseUrl ??
            Uri(
              scheme: 'https',
              host: 'edugate.ksu.edu.sa',
              path:
                  '/ksu/ui/guest/timetable/index/mainScheduleTreeCoursesIndex.faces',
            );

  void _log(String msg) {
    if (enableLogging) {
      // ignore: avoid_print
      print('[KSU] ' + msg);
    }
  }

  @override
  Future<TimetableResult?> fetch({
    String? courseCode,
    required String section,
  }) async {
    // Try to fetch results HTML by simulating the Search request.
    final html = await _fetchResultsHtml(section: section);
    final doc = html_parser.parse(html);

    // Heuristic parsing: try to find a table that contains the courseCode
    // and section, then extract weekday, time, classroom, and course name.
    final result = await _parseDocument(
      document: doc,
      courseCode: courseCode,
      section: section,
    );
    return result;
  }

  Future<TimetableResult?> _parseDocument({
    required dom.Document document,
    String? courseCode,
    required String section,
  }) async {
    // Normalize text matching by collapsing whitespace.
    String norm(String s) => s.replaceAll(RegExp(r"\s+"), ' ').trim();

    // Try candidate tables
    final tables = document.querySelectorAll('table');
    dom.Element? containingTable;
    final normalizedSection = _normalizeDigits(section).toUpperCase();
    for (final t in tables) {
      final text = norm(t.text);
      final normalizedText = _normalizeDigits(text).toUpperCase();
      if ((courseCode == null || courseCode.isEmpty ||
              normalizedText.contains(courseCode.toUpperCase())) &&
          normalizedText.contains(normalizedSection)) {
        containingTable = t;
        break;
      }
    }
    if (containingTable == null) {
      // Fallback: scan all rows for an exact section match anywhere in the page.
      _log('No containing table matched; scanning all rows for section');
      final allRows = document.querySelectorAll('tr');
      for (final tr in allRows) {
        final cells = tr.querySelectorAll('td');
        if (cells.isEmpty) continue;
        final cellValues = cells.map((c) => norm(c.text)).toList();
        final normCells = cellValues.map(_normalizeDigits).map((s) => s.toUpperCase()).toList();
        final hasExactSection = normCells.any((c) => c.trim() == normalizedSection);
        if (!hasExactSection) continue;
        if (courseCode != null && courseCode.isNotEmpty) {
          final hasCourse = normCells.any((c) => c.contains(courseCode.toUpperCase()));
          if (!hasCourse) continue;
        }
        containingTable = dom.Element.tag('table');
        containingTable.append(tr);
        break;
      }
      if (containingTable == null) {
        _log('No row with exact section match found');
        return null;
      }
    }

    // Extract rows which include our section and course code.
    final rows = containingTable.querySelectorAll('tr');
    final meetings = <MeetingPattern>[];
    String? foundCourseCode = courseCode;
    String courseName = courseCode ?? '';

    // 1) Identify the exact row whose section (الشعبة) equals the input.
    dom.Element? matchedRow;
    for (final tr in rows) {
      final cells = tr.querySelectorAll('td');
      if (cells.isEmpty) continue;
      final cellValues = cells.map((c) => norm(c.text)).toList();
      final normCells = cellValues.map(_normalizeDigits).map((s) => s.toUpperCase()).toList();
      final hasExactSection = normCells.any((c) => c.trim() == normalizedSection);
      if (!hasExactSection) continue;
      if (courseCode != null && courseCode.isNotEmpty) {
        final hasCourse = normCells.any((c) => c.contains(courseCode.toUpperCase()));
        if (!hasCourse) continue;
      }
      matchedRow = tr;
      break;
    }

    if (matchedRow != null) {
      final cells = matchedRow.querySelectorAll('td');
      final cellTexts = cells.map((c) => norm(c.text)).toList();
      foundCourseCode ??= _guessCourseCode2(cellTexts) ?? _guessCourseCode(cellTexts);
      courseName = _guessCourseName(cellTexts, fallback: foundCourseCode ?? '');

      // 2) Prefer parsing the details page linked in the row ("التفاصيل").
      final detailLink = matchedRow.querySelector('a[href]');
      bool detailsParsed = false;
      if (detailLink != null) {
        final href = detailLink.attributes['href'] ?? '';
        if (href.isNotEmpty && href != '#' && href != 'javascript:void(0)') {
          final detailsUri = baseUrl.resolve(href);
          try {
            final detailsRes = await http.get(detailsUri);
            if (detailsRes.statusCode == 200) {
              final detailsDoc = html_parser.parse(utf8.decode(detailsRes.bodyBytes));
              final fromDetails = _parseMeetingsFromDetails(detailsDoc);
              if (fromDetails.isNotEmpty) {
                meetings.addAll(fromDetails);
                detailsParsed = true;
              }
            }
          } catch (_) {}
        }
      }

      // 3) Fallback: parse the row itself if details absent or empty.
      if (!detailsParsed) {
        final weekday = _weekdayFromCells2(cellTexts) ?? _guessWeekday(cellTexts);
        final times = _timesFromCells(cellTexts) ?? _guessStartEnd(cellTexts);
        final classroom = _guessClassroom(cellTexts);
        if (weekday != null && times != null) {
          meetings.add(MeetingPattern(
            weekday: weekday,
            startHHmm: times.$1,
            endHHmm: times.$2,
            classroom: classroom,
          ));
        }
      }
    }

    // If still not found, try simple pagination by following numeric page links.
    if (matchedRow == null) {
      final pageLinks = <String>{};
      for (final a in document.querySelectorAll('a[href]')) {
        final txt = norm(a.text);
        if (RegExp(r'^\d+$').hasMatch(txt)) {
          final href = a.attributes['href'] ?? '';
          if (href.isNotEmpty && href != '#' && href != 'javascript:void(0)') {
            pageLinks.add(href);
          }
        }
      }
      int tries = 0;
      for (final href in pageLinks) {
        if (tries++ >= 12) break; // safety cap on pages
        final uri = baseUrl.resolve(href);
        try {
          final res = await http.get(uri);
          if (res.statusCode != 200) continue;
          final html = utf8.decode(res.bodyBytes);
          final doc2 = html_parser.parse(html);

          // Recompute table + rows for this page
          final tables2 = doc2.querySelectorAll('table');
          dom.Element? table2;
          for (final t in tables2) {
            final normalizedText = _normalizeDigits(norm(t.text)).toUpperCase();
            if ((courseCode == null || courseCode.isEmpty ||
                    normalizedText.contains(courseCode.toUpperCase())) &&
                normalizedText.contains(normalizedSection)) {
              table2 = t;
              break;
            }
          }
          if (table2 == null) continue;
          for (final tr in table2.querySelectorAll('tr')) {
            final cells = tr.querySelectorAll('td');
            if (cells.isEmpty) continue;
            final cellValues = cells.map((c) => norm(c.text)).toList();
            final normCells = cellValues.map(_normalizeDigits).map((s) => s.toUpperCase()).toList();
            final hasExactSection = normCells.any((c) => c.trim() == normalizedSection);
            if (!hasExactSection) continue;
            if (courseCode != null && courseCode.isNotEmpty) {
              final hasCourse = normCells.any((c) => c.contains(courseCode.toUpperCase()));
              if (!hasCourse) continue;
            }
            matchedRow = tr;
            final cellTexts = cells.map((c) => norm(c.text)).toList();
            foundCourseCode ??= _guessCourseCode2(cellTexts) ?? _guessCourseCode(cellTexts);
            courseName = _guessCourseName(cellTexts, fallback: foundCourseCode ?? '');

            // Try details page first
            final detailLink = tr.querySelector('a[href]');
            bool detailsParsed = false;
            if (detailLink != null) {
              final href2 = detailLink.attributes['href'] ?? '';
              if (href2.isNotEmpty && href2 != '#' && href2 != 'javascript:void(0)') {
                final detailsUri = baseUrl.resolve(href2);
                final r = await http.get(detailsUri);
                if (r.statusCode == 200) {
                  final detailsDoc = html_parser.parse(utf8.decode(r.bodyBytes));
                  final fromDetails = _parseMeetingsFromDetails(detailsDoc);
                  if (fromDetails.isNotEmpty) {
                    meetings.addAll(fromDetails);
                    detailsParsed = true;
                  }
                }
              }
            }
            if (!detailsParsed) {
              final weekday = _weekdayFromCells2(cellTexts) ?? _guessWeekday(cellTexts);
              final times = _timesFromCells(cellTexts) ?? _guessStartEnd(cellTexts);
              final classroom = _guessClassroom(cellTexts);
              if (weekday != null && times != null) {
                meetings.add(MeetingPattern(
                  weekday: weekday,
                  startHHmm: times.$1,
                  endHHmm: times.$2,
                  classroom: classroom,
                ));
              }
            }
            break;
          }
          if (meetings.isNotEmpty) break; // found on this page
        } catch (_) {
          continue;
        }
      }
    }

    if (meetings.isEmpty) {
      return null; // Not enough info to proceed
    }
    if (foundCourseCode == null || foundCourseCode.trim().isEmpty) {
      return null; // Need course code to build deterministic IDs
    }

    // Rolling window: today through +120 days (no semester assumption)
    final today = DateTime.now();
    final windowStart = DateTime(today.year, today.month, today.day);
    final windowEnd = windowStart.add(const Duration(days: 120));
    return TimetableResult(
      courseCode: foundCourseCode.replaceAll(' ', '').toUpperCase(),
      courseName: courseName,
      section: section,
      termStart: windowStart,
      termEnd: windowEnd,
      meetings: meetings,
    );
  }

  // Extract meetings from a details page by scanning tables for weekday/time/classroom.
  List<MeetingPattern> _parseMeetingsFromDetails(dom.Document doc) {
    final meetings = <MeetingPattern>[];
    String norm(String s) => s.replaceAll(RegExp(r"\s+"), ' ').trim();
    for (final table in doc.querySelectorAll('table')) {
      for (final tr in table.querySelectorAll('tr')) {
        final cells = tr.querySelectorAll('td');
        if (cells.isEmpty) continue;
        final texts = cells.map((c) => norm(c.text)).toList();
        final weekday = _weekdayFromCells2(texts) ?? _guessWeekday(texts);
        final times = _timesFromCells(texts) ?? _guessStartEnd(texts);
        final classroom = _guessClassroom(texts);
        if (weekday != null && times != null) {
          meetings.add(MeetingPattern(
            weekday: weekday,
            startHHmm: times.$1,
            endHHmm: times.$2,
            classroom: classroom,
          ));
        }
      }
    }
    return meetings;
  }

  String _guessCourseName(List<String> cells, {required String fallback}) {
    // Pick first long-ish text that includes letters and spaces.
    for (final c in cells) {
      if (RegExp(r'[A-Za-z\p{L}]{3,}', unicode: true).hasMatch(c) && c.length >= 4) {
        return c;
      }
    }
    return fallback;
  }

  String _guessClassroom(List<String> cells) {
    // Try to find tokens that look like building-room (e.g., B12-123) or room numbers.
    for (final c in cells) {
      final m = RegExp(r'(?:[A-Za-z]{1,3}\d{1,3}-\d{2,4}|Room\s*\w+-?\w+|\b\w{1,3}-?\d{2,4}\b)')
          .firstMatch(c);
      if (m != null) return m.group(0) ?? c;
    }
    return '';
  }

  String? _guessCourseCode(List<String> cells) {
    // Look for patterns like CS 101, CS101, SWE 201, IS 123, IT 456
    final re = RegExp(r'\b([A-Za-z]{2,4})\s*([0-9]{2,3})\b');
    for (final c in cells) {
      final m = re.firstMatch(c);
      if (m != null) {
        return '${m.group(1)}${m.group(2)}';
      }
    }
    return null;
  }

  // More permissive course code pattern (allows 4-digit numbers)
  String? _guessCourseCode2(List<String> cells) {
    final re = RegExp(r'\b([A-Za-z]{2,4})\s*([0-9]{2,4})\b');
    for (final c in cells) {
      final m = re.firstMatch(c);
      if (m != null) return '${m.group(1)}${m.group(2)}';
    }
    return null;
  }

  // Normalize Arabic-Indic/Persian digits and Arabic AM/PM markers to ASCII
  String _normalizeDigitsAndMarkers(String s) {
    final StringBuffer out = StringBuffer();
    for (final rune in s.runes) {
      if (rune >= 0x0660 && rune <= 0x0669) {
        out.write(String.fromCharCode('0'.codeUnitAt(0) + (rune - 0x0660)));
      } else if (rune >= 0x06F0 && rune <= 0x06F9) {
        out.write(String.fromCharCode('0'.codeUnitAt(0) + (rune - 0x06F0)));
      } else {
        out.writeCharCode(rune);
      }
    }
    var x = out.toString();
    x = x.replaceAll('ص', 'AM').replaceAll('م', 'PM');
    return x;
  }

  // Additional normalizer: digits + Arabic AM/PM and cleanup
  String _normalizeDigitsAndMarkers2(String s) {
    final StringBuffer out = StringBuffer();
    for (final rune in s.runes) {
      if (rune >= 0x0660 && rune <= 0x0669) {
        out.write(String.fromCharCode('0'.codeUnitAt(0) + (rune - 0x0660)));
      } else if (rune >= 0x06F0 && rune <= 0x06F9) {
        out.write(String.fromCharCode('0'.codeUnitAt(0) + (rune - 0x06F0)));
      } else if (rune == 0x0640) {
        // Tatweel
        continue;
      } else {
        out.writeCharCode(rune);
      }
    }
    var x = out.toString();
    x = x
        .replaceAll('ص', 'AM')
        .replaceAll('م', 'PM')
        .replaceAll('صباحًا', 'AM')
        .replaceAll('مساءً', 'PM')
        .replaceAll('صباحا', 'AM')
        .replaceAll('مساء', 'PM');
    return x;
  }

  // Improved weekday extraction with Arabic support
  int? _weekdayFromCells2(List<String> cells) {
    const en = {
      'MON': 1,
      'TUE': 2,
      'WED': 3,
      'THU': 4,
      'FRI': 5,
      'SAT': 6,
      'SUN': 7,
    };
    const ar = {
      'الاثنين': 1,
      'الإثنين': 1,
      'الثلاثاء': 2,
      'الاربعاء': 3,
      'الأربعاء': 3,
      'الخميس': 4,
      'الجمعة': 5,
      'السبت': 6,
      'الاحد': 7,
      'الأحد': 7,
    };
    String normAr(String s) {
      final diacritics = RegExp('[\u064B-\u0652]');
      var t = s.replaceAll(diacritics, '');
      t = t
          .replaceAll('أ', 'ا')
          .replaceAll('إ', 'ا')
          .replaceAll('آ', 'ا')
          .replaceAll('ة', 'ه');
      return t;
    }
    for (final c in cells) {
      final up = c.toUpperCase();
      for (final e in en.entries) {
        if (up.contains(e.key)) return e.value;
      }
      final ca = normAr(c);
      for (final a in ar.entries) {
        if (ca.contains(a.key)) return a.value;
      }
    }
    return null;
  }

  // Robust weekday extraction with proper Arabic names
  int? _weekdayFromCells(List<String> cells) {
    const en = {
      'MON': 1,
      'TUE': 2,
      'WED': 3,
      'THU': 4,
      'FRI': 5,
      'SAT': 6,
      'SUN': 7,
    };
    const ar = {
      'الاثنين': 1,
      'الإثنين': 1,
      'الثلاثاء': 2,
      'الاربعاء': 3,
      'الأربعاء': 3,
      'الخميس': 4,
      'الجمعة': 5,
      'السبت': 6,
      'الأحد': 7,
      'الاحد': 7,
    };
    for (final c in cells) {
      final up = c.toUpperCase();
      for (final e in en.entries) {
        if (up.contains(e.key)) return e.value;
      }
      for (final a in ar.entries) {
        if (c.contains(a.key)) return a.value;
      }
    }
    return null;
  }

  // Robust time extraction: supports 24h and 12h with Arabic markers and en dash
  (String, String)? _timesFromCells(List<String> cells) {
    final timeRe = RegExp(
      r'(\d{1,2})[:\.]?(\d{2})\s*(AM|PM)?\s*[-–—]\s*(\d{1,2})[:\.]?(\d{2})\s*(AM|PM)?',
      caseSensitive: false,
    );
    for (final raw in cells) {
      final c = _normalizeDigitsAndMarkers2(raw);
      final m = timeRe.firstMatch(c);
      if (m != null) {
        String toHHmm(String h, String mm, String? meridian) {
          var hour = int.parse(h);
          final minute = int.parse(mm);
          if (meridian != null) {
            final isPM = meridian.toUpperCase() == 'PM';
            if (hour == 12 && !isPM) hour = 0;
            if (hour < 12 && isPM) hour += 12;
          }
          return '${hour.toString().padLeft(2, '0')}${minute.toString().padLeft(2, '0')}';
        }
        final s = toHHmm(m.group(1)!, m.group(2)!, m.group(3));
        final e = toHHmm(m.group(4)!, m.group(5)!, m.group(6));
        return (s, e);
      }

      final compact = RegExp(r'(\d{3,4})\s*[-–—]\s*(\d{3,4})');
      final mc = compact.firstMatch(c);
      if (mc != null) {
        String norm4(String t) => t.length == 3 ? t.padLeft(4, '0') : t.substring(0, 4);
        return (norm4(mc.group(1)!), norm4(mc.group(2)!));
      }
    }
    return null;
  }

  int? _guessWeekday(List<String> cells) {
    const en = {
      'MON': 1,
      'TUE': 2,
      'WED': 3,
      'THU': 4,
      'FRI': 5,
      'SAT': 6,
      'SUN': 7,
    };
    const ar = {
      'Ø§Ù„Ø§Ø«Ù†ÙŠÙ†': 1,
      'Ø§Ù„Ø«Ù„Ø§Ø«Ø§Ø¡': 2,
      'Ø§Ù„Ø£Ø±Ø¨Ø¹Ø§Ø¡': 3,
      'Ø§Ù„Ø§Ø±Ø¨Ø¹Ø§Ø¡': 3,
      'Ø§Ù„Ø®Ù…ÙŠØ³': 4,
      'Ø§Ù„Ø¬Ù…Ø¹Ø©': 5,
      'Ø§Ù„Ø³Ø¨Øª': 6,
      'Ø§Ù„Ø£Ø­Ø¯': 7,
      'Ø§Ù„Ø§Ø­Ø¯': 7,
    };
    for (final c in cells) {
      final up = c.toUpperCase();
      for (final e in en.entries) {
        if (up.contains(e.key)) return e.value;
      }
      for (final a in ar.entries) {
        if (c.contains(a.key)) return a.value;
      }
    }
    return null;
  }

  (String, String)? _guessStartEnd(List<String> cells) {
    // Match times like 08:00-09:20 or 0800-0920
    final timeRe = RegExp(r'(\d{1,2}[:\.]?\d{2})\s*[-â€“]\s*(\d{1,2}[:\.]?\d{2})');
    for (final c in cells) {
      final m = timeRe.firstMatch(c);
      if (m != null) {
        String toHHmm(String s) {
          final t = s.replaceAll(RegExp(r'\D'), '');
          if (t.length == 3) {
            // e.g., 800 â†’ 0800
            return t.padLeft(4, '0');
          }
          if (t.length == 4) return t;
          if (t.length == 1) return '0${t}00';
          if (t.length == 2) return '${t}00';
          return t.substring(0, 4);
        }
        return (toHHmm(m.group(1)!), toHHmm(m.group(2)!));
      }
    }
    return null;
  }

  // Attempt to submit the page form similarly to pressing Search.
  Future<String> _fetchResultsHtml({required String section}) async {
    _log('GET ' + baseUrl.toString());
    final res = await http.get(baseUrl);
    if (res.statusCode != 200) {
      throw Exception('FETCH_FAILED ${res.statusCode}');
    }
    final body = utf8.decode(res.bodyBytes);
    final doc = html_parser.parse(body);

    final form = doc.querySelector('form');
    if (form == null) {
      _log('No form found; using initial page');
      return body;
    }

    final Map<String, String> payload = {};
    final inputs = form.querySelectorAll('input');
    for (final inp in inputs) {
      final name = inp.attributes['name'];
      if (name == null) continue;
      final value = inp.attributes['value'] ?? '';
      payload[name] = value;
    }

    // Do NOT set any search inputs: per site behavior, clicking Search with
    // no inputs loads the full list; we'll filter by section locally.

    // JSF/PrimeFaces partial AJAX flags (harmless if unused)
    payload.putIfAbsent('javax.faces.partial.ajax', () => 'true');
    final src = _firstButtonName(form);
    if (src != null) payload['javax.faces.source'] = src;
    payload.putIfAbsent('javax.faces.partial.execute', () => '@all');
    payload.putIfAbsent('javax.faces.partial.render', () => '@all');

    final action = form.attributes['action'] ?? baseUrl.toString();
    final postUrl = baseUrl.resolve(action);
    _log('POST ' + postUrl.toString());
    final postRes = await http.post(
      postUrl,
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        'Accept': 'text/html,application/xhtml+xml,application/xml',
      },
      body: payload,
    );
    if (postRes.statusCode != 200) {
      _log('POST failed ${postRes.statusCode}; falling back to initial HTML');
      return body;
    }
    var html = utf8.decode(postRes.bodyBytes);
    if (html.contains('<partial-response')) {
      final updates = RegExp(r'<update[^>]*>([\s\S]*?)<\/update>', multiLine: true)
          .allMatches(html)
          .map((m) => m.group(1) ?? '')
          .join('\n');
      if (updates.isNotEmpty) {
        _log('Parsed JSF partial-response with updates');
        html = updates;
      }
    }
    return html;
  }

  String? _firstButtonName(dom.Element form) {
    final btn = form.querySelector('button[name], input[type="submit"][name], input[type="image"][name]');
    return btn?.attributes['name'];
  }

  String _normalizeDigits(String s) {
    final StringBuffer out = StringBuffer();
    for (final rune in s.runes) {
      if (rune >= 0x0660 && rune <= 0x0669) {
        out.write(String.fromCharCode('0'.codeUnitAt(0) + (rune - 0x0660)));
      } else if (rune >= 0x06F0 && rune <= 0x06F9) {
        out.write(String.fromCharCode('0'.codeUnitAt(0) + (rune - 0x06F0)));
      } else {
        out.writeCharCode(rune);
      }
    }
    return out.toString();
  }
}

