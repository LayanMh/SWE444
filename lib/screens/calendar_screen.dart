import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/microsoft_auth_service.dart';
import '../services/microsoft_calendar_service.dart';
import 'add_lecture_screen.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  MicrosoftAccount? _account;
  List<MicrosoftCalendarEvent> _events = <MicrosoftCalendarEvent>[];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCalendar(interactive: false);
  }

  Future<void> _loadCalendar({
    bool interactive = false,
    bool showSpinner = true,
  }) async {
    if (showSpinner) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    } else {
      setState(() {
        _error = null;
      });
    }

    try {
      final account = await MicrosoftAuthService.ensureSignedIn(
        interactive: interactive,
      );

      if (!mounted) {
        return;
      }

      if (account == null) {
        setState(() {
          _account = null;
          _events = <MicrosoftCalendarEvent>[];
          _isLoading = false;
        });
        return;
      }

      final events = await MicrosoftCalendarService.fetchUpcomingEvents(
        account,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _account = account;
        _events = events;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
      // ✅ Use existing session
  final account = MicrosoftAuthService.currentAccount ??
      await MicrosoftAuthService.ensureSignedIn(interactive: interactive);
  
  if (account == null) {
    setState(() {
      _account = null;
      _events = <MicrosoftCalendarEvent>[];
      _isLoading = false;
    });
    return;
  }
  }

  Future<void> _handleRefresh() {
    return _loadCalendar(interactive: false, showSpinner: false);
  }

  Future<void> _handleSignOut() async {
    await MicrosoftAuthService.signOut();
    if (!mounted) {
      return;
    }
    setState(() {
      _account = null;
      _events = <MicrosoftCalendarEvent>[];
    });
  }

  Future<void> _openAddLecture() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddLectureScreen()),
    );
    if (!mounted) {
      return;
    }
    await _loadCalendar(interactive: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Microsoft Calendar'),
        actions: [
          if (_account != null && !_isLoading)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => _loadCalendar(interactive: false),
              tooltip: 'Refresh events',
            ),
          if (_account != null)
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: _handleSignOut,
              tooltip: 'Sign out',
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddLecture,
        icon: const Icon(Icons.school),
        label: const Text('Add Section'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return _ErrorView(
        message: _error!,
        onRetry: () => _loadCalendar(interactive: false),
      );
    }

    if (_account == null) {
      return _SignInPrompt(onPressed: () => _loadCalendar(interactive: true));
    }

    if (_events.isEmpty) {
      return RefreshIndicator(
        onRefresh: _handleRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Text(
                'Go ahead and build your calendar 🎉\nTap "Add Section" to start adding your class schedule.',
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _handleRefresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: _events.length,
        itemBuilder: (context, index) {
          final event = _events[index];
          final start = event.start;
          final previousStart = index > 0 ? _events[index - 1].start : null;
          final showHeader = !_isSameDay(start, previousStart);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showHeader)
                Padding(
                  padding: const EdgeInsets.only(top: 16, bottom: 8),
                  child: Text(
                    _formatHeader(start),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
             Card(
  child: ListTile(
    title: Text(
      event.subject.isNotEmpty ? event.subject : 'Untitled event',
    ),
    subtitle: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_formatEventTime(event)),
        if ((event.location ?? '').isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(event.location!),
        ],
      ],
    ),
    trailing: IconButton(
      icon: const Icon(Icons.delete, color: Colors.red),
      tooltip: 'Delete',
      onPressed: () => _confirmDelete(event), // ✅ call delete function
    ),
  ),
),

            ],
          );
        },
      ),
    );
  }

  bool _isSameDay(DateTime? a, DateTime? b) {
    if (a == null || b == null) {
      return false;
    }
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _formatHeader(DateTime? date) {
    if (date == null) {
      return 'Unknown date';
    }
    return DateFormat('EEEE, MMM d').format(date);
  }

  String _formatEventTime(MicrosoftCalendarEvent event) {
    if (event.isAllDay) {
      return 'All day';
    }

    final start = event.start;
    final end = event.end;

    if (start == null) {
      return 'Time not specified';
    }

    final formatter = DateFormat('hh:mm a');
    final startLabel = formatter.format(start);

    if (end == null || start.isAtSameMomentAs(end)) {
      return startLabel;
    }

    return '$startLabel - ${formatter.format(end)}';
  }

  Future<void> _confirmDelete(MicrosoftCalendarEvent event) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Lecture'),
        content: Text('Are you sure you want to delete "${event.subject}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final messenger = ScaffoldMessenger.of(context);

    try {
      if (_account == null) return;

      // Delete from Microsoft Calendar
      await MicrosoftCalendarService.deleteLecture(
        account: _account!,
        eventId: event.id,
      );

      // Update local UI (remove event)
      setState(() {
        _events.removeWhere((e) => e.id == event.id);
      });

      messenger.showSnackBar(
        SnackBar(content: Text('${event.subject} deleted successfully.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Error deleting event: $e')),
      );
    }
  }
}

class _SignInPrompt extends StatelessWidget {
  const _SignInPrompt({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Sign in with your Microsoft account to view your calendar.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: onPressed,
            child: const Text('Sign in with Microsoft'),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Something went wrong:\n$message',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
