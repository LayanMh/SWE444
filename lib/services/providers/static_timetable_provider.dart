import '../timetable_provider.dart';

/// Simple provider useful for testing without scraping a website.
class StaticTimetableProvider implements TimetableProvider {
  final TimetableResult? result;

  StaticTimetableProvider(this.result);

  @override
  Future<TimetableResult?> fetch({
    String? courseCode,
    required String section,
  }) async {
    return result;
  }
}
