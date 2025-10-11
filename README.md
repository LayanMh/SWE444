# absherk

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Timetable Scraper (Users/{uid}/schedule)

This app includes a scraper service to fetch an official timetable for a given course/section and save every lecture occurrence under `users/{uid}/schedule/{eventId}` with idempotent writes.

- Entry points:
  - Service: `lib/services/schedule_scraper.dart` → `scrapeAndSave(...)`
  - Provider API: `lib/services/timetable_provider.dart` (implement `TimetableProvider`)
- Deterministic document ID per occurrence: `{courseCode}:{section}:{YYYY-MM-DD}:{HHmm}` (e.g., `CS101:201:2025-10-06:0800`).
- Saved fields per occurrence:
  - `courseCode` (normalized, uppercase, no spaces)
  - `courseName`, `section`, `classroom`
  - `start`/`end` (Firestore `Timestamp`), `weekday` (1..7)
  - `source` = `scraper`, `createdAt`, `updatedAt` (server timestamps)

Implement a provider

Create a provider under `lib/services/providers/` which implements `TimetableProvider.fetch({ String? courseCode, required String section })` and returns `TimetableResult` with:

- `termStart`/`termEnd` (inclusive local dates for the current term; infer or hardcode ranges as needed)
- `meetings` (weekly patterns with weekday, HHmm start/end, classroom)

You can start from the skeleton `HtmlTimetableProvider` and plug a `UrlBuilder` and parse callback for your target URL/format.

Example usage

```
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'services/schedule_scraper.dart';
import 'services/timetable_provider.dart';

Future<void> runScrape() async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final inputs = ScrapeInputs(
    uid: '<USER_UID>',
    // courseCode is optional; provider can infer from section
    section: '201',
  );

  // TODO: supply a real provider for your timetable website
  final provider = MyHtmlProvider();

  final summary = await scrapeAndSave(inputs: inputs, provider: provider);
  print(summary);
}
```

Notes

- Re-running with the same inputs does not create duplicates (same IDs are upserted).
- The scraper writes only under `users/{uid}/schedule/*` and no other collections.
- If no timetable is found, the function returns `{ totalSaved: 0, meetings: [] }`.
