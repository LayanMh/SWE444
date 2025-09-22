import 'package:flutter/material.dart';
import '../models/lecture.dart';

class LectureTile extends StatelessWidget {
  final Lecture lecture;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const LectureTile({
    super.key,
    required this.lecture,
    this.onEdit,
    this.onDelete,
  });

  String _dayLabel(int dayOfWeek) {
    const days = [
      'Sunday',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
    ];
    return days[dayOfWeek % 7];
  }

  String _formatTime(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    final suffix = h >= 12 ? 'PM' : 'AM';
    final hour12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    final mm = m.toString().padLeft(2, '0');
    return '$hour12:$mm $suffix';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      child: ListTile(
        title: Text(
          '${lecture.courseCode} - ${lecture.courseName}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Section: ${lecture.section}'),
            Text('Classroom: ${lecture.classroom}'),
            Text(
              '${_dayLabel(lecture.dayOfWeek)}, '
              '${_formatTime(lecture.startTime)} - ${_formatTime(lecture.endTime)}',
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onEdit != null)
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: onEdit,
                tooltip: 'Edit',
              ),
            if (onDelete != null)
              IconButton(
                icon: const Icon(Icons.delete),
                onPressed: onDelete,
                tooltip: 'Delete',
              ),
          ],
        ),
      ),
    );
  }
}
