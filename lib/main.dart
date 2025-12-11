import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;


import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum EventType { event, task, note }

extension EventTypeExtension on EventType {
  String get label {
    switch (this) {
      case EventType.event:
        return 'Event';
      case EventType.task:
        return 'Task';
      case EventType.note:
        return 'Note';
    }
  }
}

enum RepeatFrequency { none, daily, weekly, monthly }

extension RepeatFrequencyExtension on RepeatFrequency {
  String get label {
    switch (this) {
      case RepeatFrequency.none:
        return 'Does not repeat';
      case RepeatFrequency.daily:
        return 'Daily';
      case RepeatFrequency.weekly:
        return 'Weekly';
      case RepeatFrequency.monthly:
        return 'Monthly';
    }
  }
}

enum HomeTab { calendar, notes, daily }

const Map<String, Duration?> kReminderOptions = <String, Duration?>{
  'No reminder': null,
  '5 minutes before': Duration(minutes: 5),
  '15 minutes before': Duration(minutes: 15),
  '30 minutes before': Duration(minutes: 30),
  '1 hour before': Duration(hours: 1),
  '1 day before': Duration(days: 1),
  '2 days before': Duration(days: 2),
  '1 week before': Duration(days: 7),
};

const List<String> kEventCategories = <String>[
  'General',
  'Work',
  'Personal',
  'Health',
  'Education',
  'Travel',
  'Entertainment',
];

String reminderLabelFromDuration(Duration? duration) {
  for (final entry in kReminderOptions.entries) {
    final option = entry.value;
    if (option == null && duration == null) {
      return entry.key;
    }
    if (option != null && duration != null &&
        option.inMinutes == duration.inMinutes) {
      return entry.key;
    }
  }
  return kReminderOptions.keys.first;
}


void main() {
  runApp(const CalendarApp());
}

class CalendarApp extends StatelessWidget {
  const CalendarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Calendar Planner',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const CalendarScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
// Tiny Change
class Event {
  final String title;
  final String description;
  final DateTime date;
  final TimeOfDay? startTime;
  final TimeOfDay? endTime;
  final String category;
  final EventType type;
  final Duration? reminder;
  final RepeatFrequency repeatFrequency;
  final bool isCompleted;


  const Event({
    required this.title,
    required this.description,
    required this.date,
    this.startTime,
    this.endTime,
    this.category = 'General',
    this.type = EventType.event,
    this.reminder,
    this.repeatFrequency = RepeatFrequency.none,
    this.isCompleted = false,
  });

  bool get hasTimeRange => startTime != null && endTime != null;

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'date': date.toIso8601String(),
      'startTime': startTime != null ? _timeOfDayToMap(startTime!) : null,
      'endTime': endTime != null ? _timeOfDayToMap(endTime!) : null,
      'category': category,
      'type': type.name,
      'reminderMinutes': reminder?.inMinutes,
      'repeatFrequency': repeatFrequency.name,
      'isCompleted': isCompleted,
    };
  }

  factory Event.fromMap(Map<String, dynamic> map) {
    final dateString = map['date'] as String?;
    DateTime parsedDate;
    try {
      parsedDate = dateString != null ? DateTime.parse(dateString) : DateTime.now();
    } catch (_) {
      parsedDate = DateTime.now();
    }

    return Event(
      title: (map['title'] as String?) ?? '',
      description: (map['description'] as String?) ?? '',
      date: parsedDate,
      startTime: _timeOfDayFromMap(map['startTime']),
      endTime: _timeOfDayFromMap(map['endTime']),
      category: (map['category'] as String?) ?? 'General',
      type: _eventTypeFromString(map['type'] as String?) ?? EventType.event,
      reminder: _durationFromMinutes(map['reminderMinutes']),
      repeatFrequency:
          _repeatFrequencyFromString(map['repeatFrequency'] as String?) ??
              RepeatFrequency.none,
      isCompleted: _boolFromAny(map['isCompleted']),
    );
  }

  Event copyWith({
    String? title,
    String? description,
    DateTime? date,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
    String? category,
    EventType? type,
    Duration? reminder,
    RepeatFrequency? repeatFrequency,
    bool? isCompleted,
  }) {
    return Event(
      title: title ?? this.title,
      description: description ?? this.description,
      date: date ?? this.date,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      category: category ?? this.category,
      type: type ?? this.type,
      reminder: reminder ?? this.reminder,
      repeatFrequency: repeatFrequency ?? this.repeatFrequency,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }

  static Map<String, int> _timeOfDayToMap(TimeOfDay time) {
    return {'hour': time.hour, 'minute': time.minute};
  }

  static Duration? _durationFromMinutes(dynamic minutes) {
    if (minutes == null) return null;
    if (minutes is num) {
      return Duration(minutes: minutes.round());
    }
    return null;
  }

  static EventType? _eventTypeFromString(String? value) {
    if (value == null) return null;
    return EventType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => EventType.event,
    );
  }

  static RepeatFrequency? _repeatFrequencyFromString(String? value) {
    if (value == null) return null;
    return RepeatFrequency.values.firstWhere(
      (freq) => freq.name == value,
      orElse: () => RepeatFrequency.none,
    );
  }

  static TimeOfDay? _timeOfDayFromMap(dynamic data) {
    if (data is Map<String, dynamic>) {
      final hourValue = data['hour'];
      final minuteValue = data['minute'];

      if (hourValue is num && minuteValue is num) {
        final hour = hourValue.toInt();
        final minute = minuteValue.toInt();
        if (hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59) {
          return TimeOfDay(hour: hour, minute: minute);
        }
      }
    }
    return null;
  }

  static bool _boolFromAny(dynamic value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      final lower = value.toLowerCase();
      if (lower == 'true') return true;
      if (lower == 'false') return false;
    }
    return false;
  }
}

class NoteEntry {
  final String title;
  final String description;
  final String category;
  final DateTime? date;
  final DateTime createdAt;
  final bool addedToCalendar;

  const NoteEntry({
    required this.title,
    required this.description,
    required this.category,
    this.date,
    required this.createdAt,
    this.addedToCalendar = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'category': category,
      'date': date?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'addedToCalendar': addedToCalendar,
    };
  }

  factory NoteEntry.fromMap(Map<String, dynamic> map) {
    DateTime? parsedDate;
    final dateValue = map['date'];
    if (dateValue is String && dateValue.isNotEmpty) {
      try {
        parsedDate = DateTime.parse(dateValue);
      } catch (_) {
        parsedDate = null;
      }
    }

    DateTime createdAt;
    final createdAtValue = map['createdAt'];
    if (createdAtValue is String) {
      try {
        createdAt = DateTime.parse(createdAtValue);
      } catch (_) {
        createdAt = DateTime.now();
      }
    } else {
      createdAt = DateTime.now();
    }

    final addedToCalendarValue = map['addedToCalendar'];

    return NoteEntry(
      title: (map['title'] as String?) ?? '',
      description: (map['description'] as String?) ?? '',
      category: (map['category'] as String?) ?? 'General',
      date: parsedDate,
      createdAt: createdAt,
      addedToCalendar: addedToCalendarValue is bool
          ? addedToCalendarValue
          : Event._boolFromAny(addedToCalendarValue),
    );
  }

  NoteEntry copyWith({
    String? title,
    String? description,
    String? category,
    DateTime? date,
    DateTime? createdAt,
    bool? addedToCalendar,
  }) {
    return NoteEntry(
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      date: date ?? this.date,
      createdAt: createdAt ?? this.createdAt,
      addedToCalendar: addedToCalendar ?? this.addedToCalendar,
    );
  }
}

class NoteResult {
  final NoteEntry note;
  final Event? calendarEvent;

  const NoteResult({required this.note, this.calendarEvent});
}


class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _selectedDate = DateTime.now();
  DateTime _currentMonth = DateTime(DateTime.now().year, DateTime.now().month);
  final List<Event> _events = [];
  final List<NoteEntry> _notes = [];
  bool _showIntroCard = true;
  HomeTab _currentTab = HomeTab.calendar;


  SharedPreferences? _cachedPrefs;
  static const String _eventsStorageKey = 'calendar_events';
  static const String _introCardStorageKey = 'calendar_intro_card';
  static const String _notesStorageKey = 'calendar_notes';

  static const int _dayStartHour = 8;
  static const int _dayEndHour = 20;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPersistedState());
  }

  Future<SharedPreferences> _getPrefs() async {
    return _cachedPrefs ??= await SharedPreferences.getInstance();
  }

  Future<void> _loadPersistedState() async {
    final prefs = await _getPrefs();
    final storedEvents = prefs.getStringList(_eventsStorageKey) ?? [];
    final loadedEvents = <Event>[];

    for (final jsonString in storedEvents) {
      try {
        final decoded = jsonDecode(jsonString);
        if (decoded is Map<String, dynamic>) {
          loadedEvents.add(Event.fromMap(decoded));
        }
      } catch (_) {
        // Ignore malformed entries.
      }
    }

    final storedNotes = prefs.getStringList(_notesStorageKey) ?? [];
    final loadedNotes = <NoteEntry>[];
    for (final jsonString in storedNotes) {
      try {
        final decoded = jsonDecode(jsonString);
        if (decoded is Map<String, dynamic>) {
          loadedNotes.add(NoteEntry.fromMap(decoded));
        }
      } catch (_) {
        // Ignore malformed entries.
      }
    }

    final showIntroPref = prefs.getBool(_introCardStorageKey);

    if (!mounted) return;
    setState(() {
      _events
        ..clear()
        ..addAll(loadedEvents);
      _notes
        ..clear()
        ..addAll(loadedNotes);
      _showIntroCard = showIntroPref ?? _events.isEmpty;
    });
  }

  Future<void> _persistEvents() async {
    final prefs = await _getPrefs();
    final encoded = _events.map((event) => jsonEncode(event.toMap())).toList();
    await prefs.setStringList(_eventsStorageKey, encoded);
  }

  Future<void> _persistNotes() async {
    final prefs = await _getPrefs();
    final encoded = _notes.map((note) => jsonEncode(note.toMap())).toList();
    await prefs.setStringList(_notesStorageKey, encoded);
  }

  Future<void> _persistIntroCard(bool value) async {
    final prefs = await _getPrefs();
    await prefs.setBool(_introCardStorageKey, value);
  }

  void _handleEventAdded(Event event) {
    setState(() {
      _events.add(event);
    });
    unawaited(_persistEvents());
  }

  void _handleNoteAdded(NoteEntry note, {Event? linkedEvent}) {
    setState(() {
      _notes.add(note);
    });
    unawaited(_persistNotes());

    if (linkedEvent != null) {
      _handleEventAdded(linkedEvent);
    }
  }

  @override
  Widget build(BuildContext context) {
    final eventsForSelectedDate = _getEventsForDate(_selectedDate);
    final freeSlots = _calculateFreeTimeSlots(eventsForSelectedDate);

    return Scaffold(
      backgroundColor:
          _currentTab == HomeTab.daily ? Colors.white : const Color(0xFFF5F7FB),      body: SafeArea(
        child: switch (_currentTab) {
          HomeTab.calendar => _buildCalendarBody(eventsForSelectedDate, freeSlots),
          HomeTab.notes => _buildNotesBody(),
          HomeTab.daily => _buildDailyBody(eventsForSelectedDate),
        },
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  Widget _buildCalendarBody(
      List<Event> eventsForSelectedDate, List<_TimeSlot> freeSlots) {
    return Column(
      children: [
        _buildTopBar(),
        _buildMonthHeader(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              children: [
                const SizedBox(height: 16),
                _buildCalendarCard(eventsForSelectedDate),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                  child: _buildFreeTimeOverview(freeSlots, eventsForSelectedDate),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                  child: _buildDateOverview(eventsForSelectedDate),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDailyBody(List<Event> eventsForSelectedDate) {
    final sortedEvents = List<Event>.from(eventsForSelectedDate)
      ..sort((a, b) {
        final aStart = a.startTime ?? const TimeOfDay(hour: 0, minute: 0);
        final bStart = b.startTime ?? const TimeOfDay(hour: 0, minute: 0);
        final hourComparison = aStart.hour.compareTo(bStart.hour);
        if (hourComparison != 0) return hourComparison;
        return aStart.minute.compareTo(bStart.minute);
      });

    final isToday = DateUtils.isSameDay(_selectedDate, DateTime.now());


    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Row(
            children: [
              _buildCircularIconButton(Icons.arrow_back_ios_new, () {
                setState(() {
                  _selectedDate = _selectedDate.subtract(const Duration(days: 1));
                });
              }),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('MMMM d, yyyy').format(_selectedDate),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat('EEEE').format(_selectedDate),
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.blueGrey[500],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              _buildCircularIconButton(Icons.arrow_forward_ios_rounded, () {
                setState(() {
                  _selectedDate = _selectedDate.add(const Duration(days: 1));
                });
              }),
              const SizedBox(width: 12),
              CircleAvatar(
                radius: 18,
                backgroundColor: Colors.blue[50],
                child: Icon(Icons.person, color: Colors.blue[700]),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(
              children: [
                _buildDailySummary(sortedEvents, isToday),
                const SizedBox(height: 12),
                _buildDailyTimeline(sortedEvents, isToday),              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDailySummary(List<Event> eventsForSelectedDate, bool isToday) {
    final eventCount = eventsForSelectedDate.length;
    final scheduledHours = eventsForSelectedDate.fold<double>(0, (sum, event) {
      if (event.startTime == null || event.endTime == null) return sum + 1;
      final startMinutes = (event.startTime!.hour * 60) + event.startTime!.minute;
      final endMinutes = (event.endTime!.hour * 60) + event.endTime!.minute;
      final durationMinutes = (endMinutes - startMinutes).clamp(30, 180);
      return sum + (durationMinutes / 60).toDouble();
    });

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFEDF3FF), Color(0xFFE4ECFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD8E3FF)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1A2C3A4B),
                  blurRadius: 12,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Icon(
              isToday ? Icons.wb_sunny_rounded : Icons.calendar_today_rounded,
              color: Colors.blue[700],
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      isToday ? 'Today' : DateFormat('EEEE').format(_selectedDate),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.blueGrey[900],
                      ),
                    ),
                    if (isToday) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.red[50],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Live',
                          style: TextStyle(
                            color: Colors.red[700],
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${DateFormat('MMMM d, yyyy').format(_selectedDate)} • $eventCount item${eventCount == 1 ? '' : 's'}',
                  style: TextStyle(
                    color: Colors.blueGrey[500],
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildSummaryChip(Icons.schedule, '${scheduledHours.toStringAsFixed(1)} hrs'),
                    const SizedBox(width: 8),
                    _buildSummaryChip(Icons.check_circle_outline, '$eventCount scheduled'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDCE6F6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.blueGrey[600]),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Colors.blueGrey[700],
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyTimeline(List<Event> events, bool isToday) {    const startHour = 5;
    const endHour = 23;
    const hourHeight = 72.0;
    final totalHours = endHour - startHour + 1;
    final timelineHeight = totalHours * hourHeight;

    final now = DateTime.now();
    final totalMinutes = (endHour - startHour + 1) * 60;
    final nowMinutes = ((now.hour - startHour) * 60) + now.minute;
    final showNowLine =
        isToday && nowMinutes >= 0 && nowMinutes <= totalMinutes && totalMinutes > 0;
    final nowTop = ((nowMinutes.clamp(0, totalMinutes)) / 60) * hourHeight;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A2C3A4B),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: SizedBox(
          height: timelineHeight,
          child: Stack(
            children: [
              Column(
                children: List.generate(totalHours, (index) {
                  final hour = startHour + index;
                  return SizedBox(
                    height: hourHeight,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 70,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _formatHourLabel(hour),
                                  style: TextStyle(
                                    color: Colors.blueGrey[400],
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                if (isToday && hour == now.hour)
                                  Container(
                                    margin: const EdgeInsets.only(top: 6),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.red[50],
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      'Current hour',
                                      style: TextStyle(
                                        color: Colors.red[700],
                                        fontWeight: FontWeight.w800,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              const SizedBox(height: 12),
                              Container(
                                height: 1,
                                color: const Color(0xFFE8EEF6),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ),
              if (showNowLine)
                Positioned(
                  top: nowTop,
                  left: 70,
                  right: 0,
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: Colors.red[600],
                          shape: BoxShape.circle,
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x1AF44336),
                              blurRadius: 8,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          height: 2,
                          color: Colors.red[400],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x142C3A4B),
                              blurRadius: 10,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Text(
                          DateFormat.jm().format(now),
                          style: TextStyle(
                            color: Colors.red[600],
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                    ],
                  ),
                ),
              ...events.map((event) {
                final start = event.startTime ?? const TimeOfDay(hour: startHour, minute: 0);
                final end = event.endTime ??
                    TimeOfDay(
                      hour: math.min(start.hour + 1, endHour),
                      minute: start.minute,
                    );

                final startMinutes = ((start.hour - startHour) * 60) + start.minute;
                final endMinutes = ((end.hour - startHour) * 60) + end.minute;
                final clampedStart = math.max(0, startMinutes);
                final clampedEnd = math.max(clampedStart + 45, math.min(endMinutes, (endHour - startHour + 1) * 60));

                final top = (clampedStart / 60) * hourHeight;
                final height = ((clampedEnd - clampedStart) / 60) * hourHeight;

                return Positioned(
                  top: top,
                  left: 78,
                  right: 16,
                  child: Container(
                    height: height,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFE8F0FF), Color(0xFFDCE7FF)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFD0E0FF)),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                event.category,
                                style: TextStyle(
                                  color: Colors.blue[800],
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                switch (event.type) {
                                  EventType.task => Icons.checklist_rounded,
                                  EventType.note => Icons.sticky_note_2_outlined,
                                  _ => Icons.event,
                                },
                                size: 16,
                                color: Colors.blue[700],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          event.title,
                          style: TextStyle(
                            color: Colors.blueGrey[900],
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _formatEventTimeRange(start, end),
                          style: TextStyle(
                            color: Colors.blueGrey[600],
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ],
          ),
        ),
      ),
    );
  }

  String _formatHourLabel(int hour) {
    final time = TimeOfDay(hour: hour, minute: 0);
    return time.format(context).toUpperCase();
  }

  String _formatEventTimeRange(TimeOfDay start, TimeOfDay end) {
    final startTime = DateTime(0, 1, 1, start.hour, start.minute);
    final endTime = DateTime(0, 1, 1, end.hour, end.minute);
    final startLabel = DateFormat.jm().format(startTime);
    final endLabel = DateFormat.jm().format(endTime);
    return '$startLabel - $endLabel';
  }


  Widget _buildNotesBody() {
    final sections = <Widget>[];

    void addCategory(String category) {
      final categoryEvents = _events
          .where((event) => event.category.toLowerCase() == category.toLowerCase())
          .toList()
        ..sort((a, b) {
          final primary = a.date.compareTo(b.date);
          if (primary != 0) return primary;
          final aStart = a.startTime?.hour ?? 0;
          final bStart = b.startTime?.hour ?? 0;
          if (aStart != bStart) return aStart.compareTo(bStart);
          final aMinute = a.startTime?.minute ?? 0;
          final bMinute = b.startTime?.minute ?? 0;
          return aMinute.compareTo(bMinute);
        });

      final categoryNotes = _notes
          .where((note) => note.category.toLowerCase() == category.toLowerCase())
          .toList()
        ..sort((a, b) {
          final aDate = a.date ?? a.createdAt;
          final bDate = b.date ?? b.createdAt;
          return aDate.compareTo(bDate);
        });

      if (categoryEvents.isEmpty && categoryNotes.isEmpty) {
        return;
      }

      sections.add(_buildNotesCategoryCard(category, categoryEvents, categoryNotes));
    }

    for (final category in kEventCategories) {
      addCategory(category);
    }

    final knownCategories =
        kEventCategories.map((category) => category.toLowerCase()).toSet();
    final customCategories = <String>{
      ..._events
          .map((event) => event.category)
          .where((category) =>
              !knownCategories.contains(category.toLowerCase())),
      ..._notes
          .map((note) => note.category)
          .where((category) =>
              !knownCategories.contains(category.toLowerCase())),
    }.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    for (final category in customCategories) {
      addCategory(category);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildNotesTopBar(),
        Expanded(
          child: sections.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      'Add a note, task, or event to see it organized here by category.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: sections,
                ),
        ),
      ],
    );
  }

  Widget _buildNotesTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Text(
            'Notes',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.blueGrey[900],
            ),
          ),
          const Spacer(),
          _buildIconButton(Icons.search, _showEventSearch),
        ],
      ),
    );
  }

  Widget _buildNotesCategoryCard(
    String category,
    List<Event> events,
    List<NoteEntry> notes,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.folder_outlined, color: Colors.blueGrey[500]),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  category,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${events.length + notes.length}',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.blueGrey[400],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (events.isNotEmpty)
            ...[for (final event in events) _buildNotesEventTile(event)],
          if (events.isNotEmpty && notes.isNotEmpty)
            const Divider(height: 24, thickness: 0.6),
          if (notes.isNotEmpty)
            ...[for (final note in notes) _buildNotesNoteTile(note)],
        ],
      ),
    );
  }

  Widget _buildNotesEventTile(Event event) {
    final isTask = event.type == EventType.task;
    final isNote = event.type == EventType.note;
    final icon = isTask
        ? Icons.check_circle_outline
        : isNote
            ? Icons.sticky_note_2_outlined
            : Icons.event_outlined;
    final iconColor = isTask
        ? Colors.deepPurple[300]
        : isNote
            ? Colors.amber[600]
            : Colors.blue[400];

    final subtitleParts = <String>[];
    subtitleParts.add(DateFormat('MMM d, yyyy').format(event.date));
    if (event.hasTimeRange) {
      subtitleParts.add(
          '${_formatTimeOfDay(event.startTime!)} - ${_formatTimeOfDay(event.endTime!)}');
    } else if (!isNote) {
      subtitleParts.add('All day');
    } else {
      subtitleParts.add('Note');
    }
    subtitleParts.add(event.type.label);
    final subtitle = subtitleParts.join(' • ');

    final titleStyle = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w700,
      color: isTask && event.isCompleted
          ? Colors.blueGrey[400]
          : Colors.blueGrey[900],
      decoration:
          isTask && event.isCompleted ? TextDecoration.lineThrough : null,
    );

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _showEditEventDialog(event),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.white,
          border: Border.all(color: Colors.blueGrey[50]!),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor?.withOpacity(0.12) ?? Colors.blue.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(event.title, style: titleStyle),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.blueGrey[500],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (event.description.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      event.description,
                      style: TextStyle(
                        color: Colors.blueGrey[400],
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (isTask)
              Checkbox(
                value: event.isCompleted,
                onChanged: (_) => _toggleTaskCompletion(event),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              )
            else
              Icon(Icons.chevron_right, color: Colors.blueGrey[200]),
          ],
        ),
      ),
    );
  }

  Widget _buildNotesNoteTile(NoteEntry note) {
    final subtitleParts = <String>[];
    if (note.date != null) {
      subtitleParts.add(DateFormat('MMM d, yyyy').format(note.date!));
    }
    subtitleParts.add('Note');
    if (note.addedToCalendar) {
      subtitleParts.add('On calendar');
    }

    final subtitle = subtitleParts.join(' • ');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xFFFFFBF2),
        border: Border.all(color: Colors.amber[100]!),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.amber[200],
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.sticky_note_2, color: Color(0xFF8D6E63), size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  note.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.blueGrey[500],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (note.description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    note.description,
                    style: TextStyle(
                      color: Colors.blueGrey[500],
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }


  Future<void> _showEditEventDialog(Event oldEvent) async {
    final edited = await showDialog<Event>(
      context: context,
      builder: (_) => EditEventDialog(initial: oldEvent),
    );
    if (edited != null) {
      setState(() {
        final i = _events.indexOf(oldEvent);
        if (i != -1) _events[i] = edited;
      });
      unawaited(_persistEvents());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Event updated!')),
      );
    }
  }


  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          _buildIconButton(Icons.search, () {
            _showEventSearch();
          }),
          const Spacer(),
          const Text(
            'Calendar',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          _buildIconButton(Icons.person_outline, () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Profile page coming soon!')),
            );
          }),
        ],
      ),
    );
  }

  Future<void> _showEventSearch() async {
    if (_events.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add an event to search.')),
      );
      return;
    }

    final selectedEvent = await showSearch<Event?>(
      context: context,
      delegate: EventSearchDelegate(events: List<Event>.from(_events)),
    );

    if (selectedEvent != null) {
      setState(() {
        _selectedDate = DateTime(
          selectedEvent.date.year,
          selectedEvent.date.month,
          selectedEvent.date.day,
        );
        _currentMonth = DateTime(
          selectedEvent.date.year,
          selectedEvent.date.month,
        );
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Showing results for "${selectedEvent.title}"')),
      );
    }
  }

  Widget _buildIconButton(IconData icon, VoidCallback onPressed) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, size: 22, color: Colors.blueGrey[700]),
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildCircularIconButton(IconData icon, VoidCallback onPressed) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A2C3A4B),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(10),
        child: Icon(icon, size: 18, color: Colors.blueGrey[800]),
      ),
    );
  }


  Widget _buildMonthHeader() {
    final monthLabel = DateFormat('MMMM yyyy').format(_currentMonth);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _RoundedArrowButton(
            icon: Icons.chevron_left,
            onTap: () {
              setState(() {
                _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1);
                _selectedDate = DateTime(_currentMonth.year, _currentMonth.month, 1);
              });
            },
          ),
          Text(
            monthLabel,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          
          _RoundedArrowButton(
            icon: Icons.chevron_right,
            onTap: () {
              setState(() {
                _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1);
                _selectedDate = DateTime(_currentMonth.year, _currentMonth.month, 1);
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarCard(List<Event> eventsForSelectedDate) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      height: 340,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
            child: Column(
              children: [
                _buildWeekdayHeader(),
                const SizedBox(height: 12),
                Expanded(child: _buildCalendarGrid(eventsForSelectedDate)),
              ],
            ),
          ),
          if (_showIntroCard) _buildIntroOverlay(),
        ],
      ),
    );
  }

  Widget _buildIntroOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: false,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.92),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F4FF),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'This is the Calendar page.\nThis is where you can see your tasks on the calendar and your free time.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _showIntroCard = false;
                      });
                      unawaited(_persistIntroCard(false));
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[600],
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Next'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWeekdayHeader() {
    const weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return Row(
      children: weekdays
          .map(
            (day) => Expanded(
              child: Center(
                child: Text(
                  day,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.blueGrey[400],
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildCalendarGrid(List<Event> eventsForSelectedDate) {
    final daysInMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 0).day;
    final firstDayOfMonth = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final startingWeekday = firstDayOfMonth.weekday % 7; // Sunday = 0

    return GridView.builder(
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: 42,
      itemBuilder: (context, index) {
        final dayIndex = index - startingWeekday + 1;
        if (dayIndex < 1 || dayIndex > daysInMonth) {
          return const SizedBox.shrink();
        }

        final date = DateTime(_currentMonth.year, _currentMonth.month, dayIndex);
        final isSelected = _isSameDay(date, _selectedDate);
        final isToday = _isSameDay(date, DateTime.now());
        final hasEvents = _getEventsForDate(date).isNotEmpty;

        return GestureDetector(
          onTap: () {
            setState(() {
              _selectedDate = date;
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.blue[600]
                  : isToday
                      ? Colors.blue[50]
                      : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected
                    ? Colors.blue[600]!
                    : hasEvents
                        ? Colors.orange[300]!
                        : Colors.blueGrey[50]!,
                width: isSelected ? 2 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: Colors.blue.withOpacity(0.25),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8, right: 10),
                    child: Text(
                      dayIndex.toString(),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isSelected
                            ? Colors.white
                            : isToday
                                ? Colors.blue[700]
                                : Colors.blueGrey[700],
                      ),
                    ),
                  ),
                ),
                if (hasEvents)
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12, bottom: 10),
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.white : Colors.orange[600],
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),

                  ),
              ],
            ),
          ),
        );
      },
    );
  }



  Widget _buildDateOverview(List<Event> events) {
    final selectedDateLabel =
        DateFormat('EEEE, MMM d, yyyy').format(_selectedDate);
    return _OverviewSection(
      title: selectedDateLabel,
      onShare: _shareDaySchedule,
      child: events.isEmpty
          ? const _EmptyOverviewMessage(
              message: 'No tasks yet. Tap + to add your first one!',
            )
          : Column(
              children: [
                for (final event in events) _buildEventTile(event),
              ],
            ),
    );
  }

  Widget _buildFreeTimeOverview(List<_TimeSlot> freeSlots, List<Event> events) {
    final eventsAffectingTime =
        events.where((event) => event.type != EventType.note).toList();
    final hasAllDayEvent =
        eventsAffectingTime.any((event) => !event.hasTimeRange);

    return _OverviewSection(
      title: 'Free time',
      child: eventsAffectingTime.isEmpty
          // No events that block time → say "Free all day"
          ? Row(
              children: [
                Icon(Icons.timer_outlined, size: 18, color: Colors.green[600]),
                const SizedBox(width: 8),
                const Text(
                  'Free all day',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            )
          : hasAllDayEvent
              ? const _EmptyOverviewMessage(
                  message: 'No Free Time',
                )
              // Has events → show calculated free slots (or the existing empty message)
              : (freeSlots.isEmpty
                  ? const _EmptyOverviewMessage(
                      message: 'No free time detected. Try adjusting your schedule.',
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: freeSlots.map((slot) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              Icon(Icons.timer_outlined, size: 18, color: Colors.green[600]),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${_formatTime(slot.start)} - ${_formatTime(slot.end)} (${_formatDuration(slot.duration)})',
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    )),
    );
  }





Widget _buildEventTile(Event event) {
  final categoryColor = _getCategoryColor(event.category);
  final timeLabel = event.hasTimeRange
      ? '${_formatTimeOfDay(event.startTime!)} - ${_formatTimeOfDay(event.endTime!)}'
      : 'All day';

  final isTask = event.type == EventType.task;
  final isNote = event.type == EventType.note;
  final isCompleted = isTask && event.isCompleted;

  final IconData typeIcon;
  final Color typeColor;
  if (isTask) {
    typeIcon = Icons.check_circle_outline;
    typeColor = const Color(0xFFF1E8FF);
  } else if (isNote) {
    typeIcon = Icons.sticky_note_2_outlined;
    typeColor = const Color(0xFFFFF4D9);
  } else {
    typeIcon = Icons.event_available_outlined;
    typeColor = const Color(0xFFE0F2FF);
  }

  final titleStyle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w800,
    color: isCompleted ? Colors.blueGrey[400] : Colors.blueGrey[900],
    decoration: isCompleted ? TextDecoration.lineThrough : null,
  );
  final subtitleStyle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: isCompleted ? Colors.blueGrey[300] : Colors.blueGrey[600],
    decoration: isCompleted ? TextDecoration.lineThrough : null,
  );
  final descriptionStyle = TextStyle(
    fontSize: 13,
    color: isCompleted ? Colors.blueGrey[300] : Colors.blueGrey[600],
    decoration: isCompleted ? TextDecoration.lineThrough : null,
  );

  final chips = <Widget>[
    _buildInfoChip(typeIcon, event.type.label, background: typeColor),
    _buildInfoChip(Icons.folder_outlined, event.category,
        background: const Color(0xFFF1F4FF)),
    if (event.reminder != null)
      _buildInfoChip(
        Icons.notifications_active_outlined,
        reminderLabelFromDuration(event.reminder),
        background: const Color(0xFFFFF1E6),
      ),
    if (event.repeatFrequency != RepeatFrequency.none)
      _buildInfoChip(
        Icons.autorenew_outlined,
        event.repeatFrequency.label,
        background: const Color(0xFFE7F8F2),
      ),
    if (isCompleted)
      _buildInfoChip(
        Icons.check_circle,
        'Completed',
        background: const Color(0xFFE7F8F2),
      ),
  ];

  final iconColor = isCompleted
      ? Colors.green[600]
      : isNote
          ? Colors.amber[700]
          : Colors.blueGrey[300];

  return InkWell(
    borderRadius: BorderRadius.circular(20),
    onTap: () => _showEditEventDialog(event),
    child: Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.blueGrey[50]!),
        color: isCompleted ? const Color(0xFFF8FAFD) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // HEADER: dot + title + time
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(top: 6, right: 10),
                decoration: BoxDecoration(
                  color: categoryColor,
                  shape: BoxShape.circle,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(event.title, style: titleStyle),
                    const SizedBox(height: 2),
                    Text(timeLabel, style: subtitleStyle),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // CHIPS
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: chips,
          ),

          // DESCRIPTION (optional)
          if (event.description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(event.description, style: descriptionStyle),
          ],

          // TASK TOGGLE under description
          if (isTask) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                  splashRadius: 16,
                  visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                  onPressed: () => _toggleTaskCompletion(event),
                  icon: Icon(isCompleted ? Icons.check_circle : Icons.radio_button_unchecked, size: 22),
                  color: iconColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isCompleted ? 'Completed' : 'Mark as complete',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: isCompleted
                          ? Colors.green[700]
                          : Colors.blueGrey[600],
                    ),
                    softWrap: true,
                    overflow: TextOverflow.visible,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    ),
  );
}





  Widget _buildInfoChip(IconData icon, String label, {Color? background}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: background ?? const Color(0xFFF1F4FF),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.blueGrey[600]),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.blueGrey[700],
            ),
            softWrap: true,
            overflow: TextOverflow.visible,
          ),
        ),
      ],
    ),
  );
}




  Widget _buildBottomNavigationBar() {
    final textScaleFactor = MediaQuery.textScaleFactorOf(context);
    final estimatedMinHeight = 24 + 4 + (12 * textScaleFactor) + 16;
    final minHeight = math.max(64.0, estimatedMinHeight);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Row(

              children: [
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _buildBottomNavItem(
                          Icons.calendar_today, 'Calendar', HomeTab.calendar),
                      _buildBottomNavItem(
                          Icons.note_outlined, 'Notes', HomeTab.notes),
                      _buildBottomNavItem(
                          Icons.view_day_outlined, 'Daily', HomeTab.daily),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _buildAddButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNavItem(IconData icon, String label, HomeTab tab) {
    final isActive = _currentTab == tab;
    final color = isActive ? Colors.blue[600] : Colors.blueGrey[300];
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        setState(() => _currentTab = tab);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddButton() {
    return InkWell(
      onTap: _handleAddTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: Colors.blue[600],
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),
    );
  }

  void _handleAddTap() {    switch (_currentTab) {
      case HomeTab.calendar:

      case HomeTab.daily:
        _showAddEventDialog();
        break;
      case HomeTab.notes:
        _showAddNoteDialog();
        break;    }
  }

  void _shareDaySchedule() {
    final events = _getEventsForDate(_selectedDate);
    final formattedDate = DateFormat('EEEE, MMMM d').format(_selectedDate);

    final summary = events.isEmpty
        ? 'No plans scheduled for $formattedDate.'
        : 'Plans for $formattedDate:\n${events.map(_buildShareLine).join('\n')}';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(summary)),
    );
  }

  String _buildShareLine(Event event) {
    final timeSegment = event.hasTimeRange
        ? '${_formatTimeOfDay(event.startTime!)} - ${_formatTimeOfDay(event.endTime!)}'
        : 'All day';
    final buffer = StringBuffer('- ${event.type.label}: ${event.title} ($timeSegment)');

    if (event.repeatFrequency != RepeatFrequency.none) {
      buffer.write(' · repeats ${event.repeatFrequency.label.toLowerCase()}');
    }
    if (event.reminder != null) {
      buffer.write(' · reminder ${reminderLabelFromDuration(event.reminder)}');
    }

    return buffer.toString();
  }



  List<Event> _getEventsForDate(DateTime date) {
    final targetDate = DateTime(date.year, date.month, date.day);
    return _events
        .where((event) => _occursOnDate(event, targetDate))
        .toList()
      ..sort((a, b) {
        if (a.startTime == null && b.startTime == null) return 0;
        if (a.startTime == null) return 1;
        if (b.startTime == null) return -1;
        return a.startTime!.hour.compareTo(b.startTime!.hour) != 0
            ? a.startTime!.hour.compareTo(b.startTime!.hour)
            : a.startTime!.minute.compareTo(b.startTime!.minute);
      });
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  bool _occursOnDate(Event event, DateTime date) {
    final baseDate = DateTime(event.date.year, event.date.month, event.date.day);
    if (_isSameDay(baseDate, date)) {
      return true;
    }

    if (event.repeatFrequency == RepeatFrequency.none || date.isBefore(baseDate)) {
      return false;
    }

    final differenceInDays = date.difference(baseDate).inDays;

    switch (event.repeatFrequency) {
      case RepeatFrequency.daily:
        return differenceInDays >= 0;
      case RepeatFrequency.weekly:
        return differenceInDays >= 0 && differenceInDays % 7 == 0;
      case RepeatFrequency.monthly:
        final monthsApart =
            (date.year - baseDate.year) * 12 + date.month - baseDate.month;
        if (monthsApart < 0) {
          return false;
        }
        if (_isLastDayOfMonth(baseDate)) {
          return _isLastDayOfMonth(date);
        }
        return date.day == baseDate.day;
      case RepeatFrequency.none:
        return _isSameDay(baseDate, date);
    }
    return false;
  }

  bool _isLastDayOfMonth(DateTime date) {
    final firstOfNextMonth = DateTime(date.year, date.month + 1, 1);
    final lastOfMonth = firstOfNextMonth.subtract(const Duration(days: 1));
    return date.day == lastOfMonth.day;
  }


  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'work':
        return Colors.blue;
      case 'personal':
        return Colors.green;
      case 'health':
        return Colors.redAccent;
      case 'education':
        return Colors.deepPurple;
      case 'travel':
        return Colors.orange;
      case 'entertainment':
        return Colors.pinkAccent;
      default:
        return Colors.blueGrey;
    }
  }

  List<_TimeSlot> _calculateFreeTimeSlots(List<Event> events) {
    final blockingEvents =
        events.where((event) => event.type != EventType.note).toList();

    if (blockingEvents.any((event) => !event.hasTimeRange)) {      return [];
    }

    final dayStart = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _dayStartHour,
    );
    final dayEnd = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _dayEndHour,
    );

    final scheduled = blockingEvents
        .where((event) => event.hasTimeRange)
        .map(
          (event) => _TimeSlot(
            start: _dateWithTime(_selectedDate, event.startTime!),
            end: _dateWithTime(_selectedDate, event.endTime!),
          ),
        )
        .where((slot) => slot.end.isAfter(slot.start))
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    if (scheduled.isEmpty) {
      return [];
    }


    final merged = <_TimeSlot>[];
    for (final slot in scheduled) {
      if (merged.isEmpty) {
        merged.add(slot);
      } else {
        final last = merged.last;
        if (slot.start.isBefore(last.end)) {
          merged[merged.length - 1] = _TimeSlot(
            start: last.start,
            end: slot.end.isAfter(last.end) ? slot.end : last.end,
          );
        } else {
          merged.add(slot);
        }
      }
    }

    final freeSlots = <_TimeSlot>[];
    var cursor = dayStart;
    for (final slot in merged) {
      if (slot.start.isAfter(cursor)) {
        freeSlots.add(_TimeSlot(start: cursor, end: slot.start));
      }
      if (slot.end.isAfter(cursor)) {
        cursor = slot.end;
      }
    }
    if (cursor.isBefore(dayEnd)) {
      freeSlots.add(_TimeSlot(start: cursor, end: dayEnd));
    }

    return freeSlots.where((slot) => slot.duration.inMinutes > 0).toList();
  }

  DateTime _dateWithTime(DateTime date, TimeOfDay time) {
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  String _formatTime(DateTime time) {
    return DateFormat('h:mm a').format(time);
  }

  String _formatTimeOfDay(TimeOfDay time) {
    return _formatTime(_dateWithTime(DateTime.now(), time));
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours > 0 && minutes > 0) {
      return '$hours h $minutes m';
    } else if (hours > 0) {
      return '$hours h';
    } else {
      return '$minutes m';
    }
  }

  Future<void> _showAddEventDialog() async {
    await showDialog<Event>(
      context: context,
      builder: (context) => AddEventDialog(
        selectedDate: _selectedDate,
        onEventAdded: (event) {
          _handleEventAdded(event);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Event added successfully!')),
          );
        },
      ),
    );
  }

  Future<void> _showAddNoteDialog() async {
    final result = await showDialog<NoteResult>(
      context: context,
      builder: (context) => AddNoteDialog(
        initialDate: _selectedDate,
      ),
    );

    if (result != null) {
      _handleNoteAdded(result.note, linkedEvent: result.calendarEvent);
      final message = result.calendarEvent != null
          ? 'Note saved and added to your calendar!'
          : 'Note saved.';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    }
  }

  void _toggleTaskCompletion(Event event) {
    if (event.type != EventType.task) {
      return;
    }
    final index = _events.indexOf(event);
    if (index == -1) {
      return;
    }

    final toggled = event.copyWith(isCompleted: !event.isCompleted);
    setState(() {
      _events[index] = toggled;
    });
    unawaited(_persistEvents());

    final message = toggled.isCompleted
        ? 'Task marked as completed!'
        : 'Task marked as incomplete.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _confirmDelete(Event event) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Event'),
        content: Text('Are you sure you want to delete "${event.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _events.remove(event);
              });
              unawaited(_persistEvents());
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Event deleted')),
              );
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }
}

class _OverviewSection extends StatelessWidget {
  const _OverviewSection({
    required this.title,
    required this.child,
    this.onShare,
  });

  final String title;
  final Widget child;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: onShare != null
                ? MainAxisAlignment.spaceBetween
                : MainAxisAlignment.start,            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (onShare != null)
                IconButton(
                  onPressed: onShare,
                  icon: const Icon(Icons.ios_share, size: 20),
                  color: Colors.blueGrey[600],
                ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _EmptyOverviewMessage extends StatelessWidget {
  const _EmptyOverviewMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: TextStyle(
        fontSize: 13,
        color: Colors.blueGrey[400],
        fontStyle: FontStyle.italic,
      ),
    );
  }
}

class _RoundedArrowButton extends StatelessWidget {
  const _RoundedArrowButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(icon, color: Colors.blueGrey[700]),
      ),
    );
  }
}

class _TimeSlot {
  const _TimeSlot({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  Duration get duration => end.difference(start);
}

class AddNoteDialog extends StatefulWidget {
  const AddNoteDialog({this.initialDate, super.key});

  final DateTime? initialDate;

  @override
  State<AddNoteDialog> createState() => _AddNoteDialogState();
}

class _AddNoteDialogState extends State<AddNoteDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  String _selectedCategory = kEventCategories.first;
  DateTime? _selectedDate;
  bool _addToCalendar = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _descriptionController = TextEditingController();
    if (widget.initialDate != null) {
      final d = widget.initialDate!;
      _selectedDate = DateTime(d.year, d.month, d.day);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final dateLabel = _selectedDate != null
        ? DateFormat('EEE, MMM d, yyyy').format(_selectedDate!)
        : 'Choose a date';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFFFF4E5),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  color: const Color(0xFFFFE1BB),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                      const Spacer(),
                      const Text(
                        'New Note',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(20, 24, 20, 24 + viewInsets),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _titleController,
                          decoration: const InputDecoration(
                            labelText: 'Title *',
                            filled: true,
                            prefixIcon: Icon(Icons.short_text),
                          ),
                          autofocus: true,
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedCategory,
                          decoration: const InputDecoration(
                            labelText: 'Category',
                            prefixIcon: Icon(Icons.folder_outlined),
                            filled: true,
                          ),
                          items: kEventCategories
                              .map(
                                (category) => DropdownMenuItem<String>(
                                  value: category,
                                  child: Text(category),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() => _selectedCategory = value);
                          },
                        ),
                        const SizedBox(height: 16),
                        SwitchListTile.adaptive(
                          title: const Text('Add to calendar'),
                          subtitle: const Text(
                              'Adds this note to your schedule as an all-day item.'),
                          value: _addToCalendar,
                          onChanged: (value) {
                            setState(() {
                              _addToCalendar = value;
                              if (value) {
                                final base = _selectedDate ??
                                    widget.initialDate ??
                                    DateTime.now();
                                _selectedDate = DateTime(
                                  base.year,
                                  base.month,
                                  base.day,
                                );
                              } else {
                                _selectedDate = null;
                              }
                            });
                          },
                        ),
                        if (_addToCalendar) ...[
                          const SizedBox(height: 8),
                          _buildDateSelector(dateLabel),
                        ],
                        const SizedBox(height: 16),
                        TextField(
                          controller: _descriptionController,
                          minLines: 3,
                          maxLines: 5,
                          decoration: const InputDecoration(
                            labelText: 'Details',
                            alignLabelWithHint: true,
                            filled: true,
                            prefixIcon: Icon(Icons.notes_outlined),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      bottom: Radius.circular(28),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          icon: const Icon(Icons.check),
                          label: const Text('Save'),
                          onPressed: _save,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDateSelector(String dateLabel) {
    return InkWell(
      onTap: _pickDate,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7EB),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.orange[200]!),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined, color: Colors.orange[600]),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                dateLabel,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.orange[800],
                ),
              ),
            ),
            Icon(Icons.keyboard_arrow_down, color: Colors.orange[400]),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? widget.initialDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (selected != null) {
      setState(() {
        _selectedDate = DateTime(selected.year, selected.month, selected.day);
      });
    }
  }

  void _save() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add a title for this note.')),
      );
      return;
    }

    if (_addToCalendar && _selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a date to add this note to the calendar.')),
      );
      return;
    }

    final note = NoteEntry(
      title: title,
      description: _descriptionController.text.trim(),
      category: _selectedCategory,
      date: _addToCalendar ? _selectedDate : null,
      createdAt: DateTime.now(),
      addedToCalendar: _addToCalendar,
    );

    Event? calendarEvent;
    if (_addToCalendar && _selectedDate != null) {
      calendarEvent = Event(
        title: title,
        description: _descriptionController.text.trim(),
        date: _selectedDate!,
        category: _selectedCategory,
        type: EventType.note,
        reminder: null,
        repeatFrequency: RepeatFrequency.none,
        isCompleted: false,
      );
    }

    Navigator.of(context).pop(NoteResult(note: note, calendarEvent: calendarEvent));
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }
}

class AddEventDialog extends StatefulWidget {
  const AddEventDialog({
    required this.selectedDate,
    required this.onEventAdded,
    super.key,
  });
  
  final DateTime selectedDate;
  final ValueChanged<Event> onEventAdded;

  @override
  State<AddEventDialog> createState() => _AddEventDialogState();
}

class _AddEventDialogState extends State<AddEventDialog> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  EventType _selectedType = EventType.event;
  String _selectedCategory = 'Other';
  String _selectedReminderLabel = kReminderOptions.keys.first;
  RepeatFrequency _repeatFrequency = RepeatFrequency.none;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  bool _isAllDay = true;
  late DateTime _selectedDate;

  static const List<String> _categoryOptions = <String>[
    'Work',
    'School',
    'Sport',
    'Personal',
    'Family',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    final base = widget.selectedDate;
    _selectedDate = DateTime(base.year, base.month, base.day);
  }

  Duration? get _calculatedDuration {
    if (_startTime == null || _endTime == null) {
      return null;
    }
    final startMinutes = _startTime!.hour * 60 + _startTime!.minute;
    final endMinutes = _endTime!.hour * 60 + _endTime!.minute;
    if (endMinutes <= startMinutes) {
      return null;
    }
    return Duration(minutes: endMinutes - startMinutes);
  }

  @override
  Widget build(BuildContext context) {
    final formattedDate =
        DateFormat('EEEE, MMM d, yyyy').format(_selectedDate);
    final durationLabel = _calculatedDuration != null
        ? _formatDuration(_calculatedDuration!)
        : null;

    final viewInsets = MediaQuery.of(context).viewInsets.bottom;


    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(child: _buildTypeSelector()),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _typeLabel(_selectedType),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              Divider(color: Colors.blueGrey.shade100, height: 1),
              Flexible(
                child: SafeArea(
                  top: false,
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      16,
                      20,
                      20 + viewInsets,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _titleController,
                          decoration: _inputDecoration(
                            label: 'Title *',
                            icon: Icons.edit_outlined,
                          ),
                          autofocus: true,
                        ),
                        const SizedBox(height: 16),
                        _buildReminderAndCategoryFields(),
                        const SizedBox(height: 20),
                        _buildSectionLabel('Date'),
                        const SizedBox(height: 8),
                        _buildDatePickerTile(formattedDate),
                        const SizedBox(height: 16),
                        _buildAllDayToggle(),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildTimePickerTile(
                                label: 'Start',
                                time: _startTime,
                                onTap: () => _pickTime(isStart: true),
                                enabled: !_isAllDay,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildTimePickerTile(
                                label: 'End',
                                time: _endTime,
                                onTap: () => _pickTime(isStart: false),
                                enabled: !_isAllDay,
                              ),

                            ),
                          ],
                        ),
                        if (durationLabel != null && !_isAllDay) ...[
                          const SizedBox(height: 10),
                          Text(
                            'Duration: $durationLabel',
                            style: TextStyle(
                              color: Colors.blueGrey.shade600,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),

                        const SizedBox(height: 20),
                        DropdownButtonFormField<RepeatFrequency>(
                          initialValue: _repeatFrequency,
                          decoration: _inputDecoration(
                            label: 'Repeat',
                            icon: Icons.repeat_outlined,
                          ),
                          items: RepeatFrequency.values
                              .map(
                                (freq) => DropdownMenuItem<RepeatFrequency>(
                                  value: freq,
                                  child: Text(freq.label),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() => _repeatFrequency = value);
                          },
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          controller: _descriptionController,
                          minLines: 3,
                          maxLines: 5,
                          decoration: _inputDecoration(
                            label: 'Description',
                            icon: Icons.notes_outlined,
                            alignLabelWithHint: true,
                          ),
                        ),
                        const SizedBox(height: 24),
                        _buildCategoryChips(),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: _saveEvent,
                        child: const Text('Save'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReminderAndCategoryFields() {
    final reminderField = DropdownButtonFormField<String>(
      initialValue: _selectedReminderLabel,
      isExpanded: true,
      decoration: _inputDecoration(
        label: 'Reminder',
        icon: Icons.notifications_outlined,
      ),
      items: kReminderOptions.keys
          .map(
            (label) => DropdownMenuItem<String>(
              value: label,
              child: Text(label),
            ),
          )
          .toList(),
      onChanged: (value) {
        if (value == null) return;
        setState(() => _selectedReminderLabel = value);
      },
    );

    return reminderField;
  }

  Widget _buildAllDayToggle() {
    return InkWell(
      onTap: () => setState(() {
        _isAllDay = !_isAllDay;
        if (_isAllDay) {
          _startTime = null;
          _endTime = null;
        }
      }),
      borderRadius: BorderRadius.circular(12),
      child: Row(
        children: [
          Checkbox(
            value: _isAllDay,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            onChanged: (value) {
              setState(() {
                _isAllDay = value ?? false;
                if (_isAllDay) {
                  _startTime = null;
                  _endTime = null;
                }
              });
            },
          ),
          const SizedBox(width: 8),
          const Text(
            'All-day',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChips() {
    const iconMap = <String, IconData>{
      'Work': Icons.work_outline,
      'School': Icons.school_outlined,
      'Sport': Icons.fitness_center_outlined,
      'Personal': Icons.person_outline,
      'Family': Icons.family_restroom_outlined,
      'Other': Icons.category_outlined,
    };


    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('Category'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _categoryOptions.map((category) {
            final isSelected = category == _selectedCategory;
            return ChoiceChip(
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (iconMap[category] != null) ...[
                    Icon(
                      iconMap[category],
                      size: 18,
                      color: isSelected ? Colors.white : Colors.blueGrey.shade600,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    category,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color:
                          isSelected ? Colors.white : Colors.blueGrey.shade700,
                    ),
                  ),
                ],
              ),
              selected: isSelected,
              selectedColor: Colors.blue,
              showCheckmark: false,
              backgroundColor: const Color(0xFFF5F7FA),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: isSelected
                      ? Colors.blue
                      : Colors.blueGrey.shade200,
                ),
              ),
              onSelected: (_) => setState(() => _selectedCategory = category),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
    );
  }

  String _typeLabel(EventType type) {
    if (type == EventType.note) {
      return 'Time Off';
    }
    return type.label;
  }

  InputDecoration _inputDecoration({
    required String label,
    IconData? icon,
    bool alignLabelWithHint = false,
  }) {
    return InputDecoration(
      labelText: label,
      alignLabelWithHint: alignLabelWithHint,
      filled: true,
      fillColor: const Color(0xFFF5F7FA),
      prefixIcon: icon != null ? Icon(icon) : null,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.blue),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    );
  }

  Widget _buildTypeSelector() {
    final types = EventType.values.where((type) => type != EventType.note).toList()
      ..add(EventType.note);    return Row(
      children: types.map((type) {
        final isSelected = type == _selectedType;
        return Expanded(
          child: InkWell(
            onTap: () => setState(() => _selectedType = type),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _typeLabel(type),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: isSelected
                        ? Colors.blue.shade700
                        : Colors.blueGrey.shade500,
                  ),
                ),
                const SizedBox(height: 8),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 3,
                  width: 48,
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.blue : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDatePickerTile(String formattedDate) {
    return InkWell(
      onTap: _pickDate,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F7FA),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined, color: Colors.blueGrey[400]),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                formattedDate,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.blueGrey[700],
                ),
              ),
            ),
            Icon(Icons.keyboard_arrow_down, color: Colors.blueGrey[300]),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 10),
    );
    if (selected != null) {
      setState(() {
        _selectedDate = DateTime(selected.year, selected.month, selected.day);
      });
    }
  }

  Widget _buildTimePickerTile({
    required String label,
    required TimeOfDay? time,
    required VoidCallback onTap,
    bool enabled = true,

  }) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F8FF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.blueGrey[100]!),
        ),
        child: Row(
          children: [
            Icon(Icons.schedule_outlined, color: Colors.blueGrey[400]),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                time == null ? '$label time' : time.format(context),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: time == null
                      ? Colors.blueGrey[300]
                      : Colors.blueGrey[700],
                ),
              ),
            ),
            Icon(Icons.keyboard_arrow_down, color: Colors.blueGrey[300]),
          ],
        ),
      ),
    );
  }

  Future<void> _pickTime({required bool isStart}) async {
    final fallbackEnd = _startTime != null
        ? TimeOfDay(
            hour: (_startTime!.hour + 1) % 24,
            minute: _startTime!.minute,
          )
        : const TimeOfDay(hour: 10, minute: 0);
    final initialTime = isStart
        ? (_startTime ?? const TimeOfDay(hour: 9, minute: 0))
        : (_endTime ?? fallbackEnd);
    final selected = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );
    if (!mounted) return;

    if (selected != null) {
      setState(() {
        if (isStart) {
          _startTime = selected;
          if (_endTime != null && !_isEndAfterStart(_endTime!, selected)) {
            _endTime = null;
          }
        } else {
          if (_startTime != null && !_isEndAfterStart(selected, _startTime!)) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('End time must be after the start time.')
                ),
              );
            return;
          }
          _endTime = selected;
        }
      });
    }
  }

  bool _isEndAfterStart(TimeOfDay end, TimeOfDay start) {
    final endMinutes = end.hour * 60 + end.minute;
    final startMinutes = start.hour * 60 + start.minute;
    return endMinutes > startMinutes;
  }

  void _saveEvent() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a name for this item.')),
      );
      return;
    }

    if (_endTime != null && _startTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose a start time before selecting the end.'),
        ),
      );      return;
    }

    final reminderDuration = kReminderOptions[_selectedReminderLabel];


    final event = Event(
      title: title,
      description: _descriptionController.text.trim(),
      date: _selectedDate,
      startTime: _startTime,
      endTime: _endTime,
      category: _selectedCategory,
      type: _selectedType,
      reminder: reminderDuration,
      repeatFrequency: _repeatFrequency,
      isCompleted: false,
    );

    widget.onEventAdded(event);
    Navigator.of(context).pop();
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours > 0 && minutes > 0) {
      return '$hours h $minutes m';
    } else if (hours > 0) {
      return '$hours h';
    }
    return '$minutes m';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }
}

class EditEventDialog extends StatefulWidget {
  const EditEventDialog({required this.initial, super.key});
  final Event initial;

  @override
  State<EditEventDialog> createState() => _EditEventDialogState();
}

class _EditEventDialogState extends State<EditEventDialog> {
  late TextEditingController _title;
  late TextEditingController _desc;
  late EventType _type;
  late String _category;
  late String _reminderLabel;
  late RepeatFrequency _repeatFrequency;
  TimeOfDay? _start;
  TimeOfDay? _end;
  late DateTime _selectedDate;


  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    _title = TextEditingController(text: init.title);
    _desc = TextEditingController(text: init.description);
    _type = init.type;
    _category = init.category;
    _reminderLabel = reminderLabelFromDuration(init.reminder);
    _repeatFrequency = init.repeatFrequency;
    _start = init.startTime;
    _end = init.endTime;
      _selectedDate = DateTime(init.date.year, init.date.month, init.date.day);
  }

  Duration? get _calculatedDuration {
    if (_start == null || _end == null) {
      return null;
    }
    final startMinutes = _start!.hour * 60 + _start!.minute;
    final endMinutes = _end!.hour * 60 + _end!.minute;
    if (endMinutes <= startMinutes) {
      return null;
    }
    return Duration(minutes: endMinutes - startMinutes);
  }

  @override
  Widget build(BuildContext context) {
    final formattedDate =
        DateFormat('EEEE, MMM d, yyyy').format(_selectedDate);
    final durationLabel = _calculatedDuration != null
        ? _formatDuration(_calculatedDuration!)
        : null;

    final viewInsets = MediaQuery.of(context).viewInsets.bottom;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFE9F2FF),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Column(
              mainAxisSize: MainAxisSize.max,
              children: [
                _buildHeader(context),
                Expanded(
                  child: SafeArea(
                    top: false,
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        20,
                        24,
                        20,
                        24 + viewInsets,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildTypeSelector(),
                          const SizedBox(height: 20),
                          TextField(
                            controller: _title,
                            decoration: const InputDecoration(
                              labelText: 'Name *',
                              filled: true,
                              prefixIcon: Icon(Icons.edit_outlined),
                            ),
                            autofocus: true,
                          ),
                          const SizedBox(height: 16),
                          _buildReminderAndCategoryFields(),
                          const SizedBox(height: 20),
                          Text('Date',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          _buildDatePickerTile(formattedDate),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Expanded(
                                child: _buildTimePickerTile(
                                  label: 'Start',
                                  time: _start,
                                  onTap: () => _pickTime(isStart: true),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildTimePickerTile(
                                  label: 'End',
                                  time: _end,
                                  onTap: () => _pickTime(isStart: false),
                                ),
                              ),
                            ],
                          ),
                          if (durationLabel != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Duration: $durationLabel',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(color: Colors.blueGrey.shade600),
                            ),
                          ],
                          const SizedBox(height: 20),
                          DropdownButtonFormField<RepeatFrequency>(
                            initialValue: _repeatFrequency,
                            decoration: const InputDecoration(
                              labelText: 'Repeat',
                              prefixIcon: Icon(Icons.repeat_outlined),
                              filled: true,
                            ),
                            items: RepeatFrequency.values
                                .map(
                                  (freq) => DropdownMenuItem<RepeatFrequency>(
                                    value: freq,
                                    child: Text(freq.label),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() => _repeatFrequency = value);
                            },
                          ),
                          const SizedBox(height: 20),
                          TextField(
                            controller: _desc,
                            minLines: 3,
                            maxLines: 5,
                            decoration: const InputDecoration(
                              labelText: 'Details',
                              alignLabelWithHint: true,
                              filled: true,
                              prefixIcon: Icon(Icons.notes_outlined),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(28),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 12,
                        offset: const Offset(0, -4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('Update'),
                          onPressed: _saveEvent,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReminderAndCategoryFields() {
    final reminderField = DropdownButtonFormField<String>(
      initialValue: _reminderLabel,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Notification',
        prefixIcon: Icon(Icons.notifications_outlined),
        filled: true,
      ),
      items: kReminderOptions.keys
          .map(
            (label) => DropdownMenuItem<String>(
              value: label,
              child: Text(label),
            ),
          )
          .toList(),
      onChanged: (value) {
        if (value == null) return;
        setState(() => _reminderLabel = value);
      },
    );

    final categoryField = DropdownButtonFormField<String>(
      initialValue: _category,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Add to',
        prefixIcon: Icon(Icons.folder_outlined),
        filled: true,
      ),
      items: kEventCategories
          .map(
            (category) => DropdownMenuItem<String>(
              value: category,
              child: Text(category),
            ),
          )
          .toList(),
      onChanged: (value) {
        if (value == null) return;
        setState(() => _category = value);
      },
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 16.0;
        final isNarrow = constraints.maxWidth < 380;
        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              reminderField,
              const SizedBox(height: spacing),
              categoryField,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: reminderField),
            const SizedBox(width: spacing),
            Expanded(child: categoryField),
          ],
        );
      },
    );
  }


  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFD6E6FF),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
          Expanded(
            child: Center(
              child: Text(
                'Edit ${_type.label}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildTypeSelector() {
    return Row(
      children: EventType.values.map((type) {
        final isSelected = type == _type;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: GestureDetector(
              onTap: () => setState(() => _type = type),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected
                        ? Colors.blue.shade600
                        : Colors.blueGrey.shade200,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Text(
                    type.label.toUpperCase(),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: isSelected
                          ? Colors.blue.shade700
                          : Colors.blueGrey.shade500,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDatePickerTile(String formattedDate) {
    return InkWell(
      onTap: _pickDate,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F7FA),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: enabled ? Colors.transparent : Colors.blueGrey.shade100,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined, color: Colors.blueGrey[400]),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                formattedDate,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.blueGrey[700],
                ),
              ),
            ),
            Icon(Icons.keyboard_arrow_down, color: Colors.blueGrey[300]),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 10),
    );
    if (selected != null) {
      setState(() {
        _selectedDate = DateTime(selected.year, selected.month, selected.day);
      });
    }
  }


  Widget _buildTimePickerTile({
    required String label,
    required TimeOfDay? time,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F8FF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.blueGrey[100]!),
        ),
        child: Row(
          children: [
            Icon(Icons.schedule_outlined, color: Colors.blueGrey[400]),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                time == null ? '$label time' : time.format(context),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: !enabled
                      ? Colors.blueGrey[300]
                      : time == null
                          ? Colors.blueGrey[400]
                          : Colors.blueGrey[700],                ),
              ),
            ),
            Icon(Icons.keyboard_arrow_down, color: Colors.blueGrey[300]),
          ],
        ),
      ),
    );
  }

  Future<void> _pickTime({required bool isStart}) async {
    final fallbackEnd = _start != null
        ? TimeOfDay(
            hour: (_start!.hour + 1) % 24,
            minute: _start!.minute,
          )
        : const TimeOfDay(hour: 10, minute: 0);
    final initialTime = isStart
        ? (_start ?? const TimeOfDay(hour: 9, minute: 0))
        : (_end ?? fallbackEnd);
    final selected = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );
    if (!mounted) return;

    if (selected != null) {
      setState(() {
        _isAllDay = false;
        if (isStart) {
          _start = selected;
          if (_end != null && !_isEndAfterStart(_end!, selected)) {
            _end = null;
          }
        } else {
          if (_start != null && !_isEndAfterStart(selected, _start!)) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('End time must be after the start time.'),
              ),
            );
            return;
          }
          _end = selected;
        }
      });
    }
  }
  bool _isEndAfterStart(TimeOfDay end, TimeOfDay start) {
    final endMinutes = end.hour * 60 + end.minute;
    final startMinutes = start.hour * 60 + start.minute;
    return endMinutes > startMinutes;
  }

  void _saveEvent() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a name for this item.')),
      );
      return;
    }

    if (_end != null && _start == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Choose a start time before selecting the end.'),
        ),
      );
      return;
    }

    final reminderDuration = kReminderOptions[_reminderLabel];

    final updated = Event(
      title: title,
      description: _desc.text.trim(),
      date: _selectedDate,
      startTime: _start,
      endTime: _end,
      category: _category,
      type: _type,
      reminder: reminderDuration,
      repeatFrequency: _repeatFrequency,
      isCompleted: widget.initial.isCompleted,
    );

    Navigator.of(context).pop(updated);
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours > 0 && minutes > 0) {
      return '$hours h $minutes m';
    } else if (hours > 0) {
      return '$hours h';
    }
    return '$minutes m';
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }
}

class EventSearchDelegate extends SearchDelegate<Event?> {
  EventSearchDelegate({required List<Event> events})
      : _events = List<Event>.from(events);

  final List<Event> _events;

  DateTime? _initialDateFromQuery(String q) {
    final dq = _parseDateQueryLoose(q);
    if (dq == null) return null;

    // Choose a concrete date for the picker:
    final now = DateTime.now();
    final year = dq.year ?? now.year;
    final month = dq.month ?? 1;
    final day = dq.day ?? 1;


    // Clamp to a valid date just in case
    final dt = _safeDate(year, month, day);
    return dt ?? DateTime(year, month, 1);
  }

  List<Event> get _sortedEvents {
    final copy = List<Event>.from(_events);
    copy.sort((a, b) {
      final dateCompare = a.date.compareTo(b.date);
      if (dateCompare != 0) {
        return dateCompare;
      }
      final aStart = a.startTime != null
          ? a.startTime!.hour * 60 + a.startTime!.minute
          : -1;
      final bStart = b.startTime != null
          ? b.startTime!.hour * 60 + b.startTime!.minute
          : -1;
      return aStart.compareTo(bStart);
    });
    return copy;
  }

  List<Event> _filterEvents(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return _sortedEvents;

    final dq = _parseDateQueryLoose(trimmed);
    final lower = trimmed.toLowerCase();

    final seen = <Event>{};
    final dateMatches = <Event>[];
    final keywordMatches = <Event>[];

    for (final e in _sortedEvents) {
      final mDate = dq != null && dq.matches(e.date);
      final mKw = e.title.toLowerCase().contains(lower) ||
          e.description.toLowerCase().contains(lower) ||
          e.category.toLowerCase().contains(lower) ||
          e.type.label.toLowerCase().contains(lower);
      if (mDate && seen.add(e)) dateMatches.add(e);
      if (mKw && seen.add(e)) keywordMatches.add(e);
    }

    // If the query looks like a date (even partial), prioritize date matches
    if (dq != null && dateMatches.isNotEmpty) {
      return [...dateMatches, ...keywordMatches];
    }
    return keywordMatches.isNotEmpty ? keywordMatches : dateMatches;
  }

  @override
  String get searchFieldLabel => 'Search events';

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      IconButton(
        tooltip: 'Pick a date',
        icon: const Icon(Icons.calendar_today),
        onPressed: () async {
          final now = DateTime.now();
          final firstDate = DateTime(now.year - 5);
          final lastDate = DateTime(now.year + 5);

          final guessed = _initialDateFromQuery(query) ?? now;
          final initialDate = guessed.isBefore(firstDate)
              ? firstDate
              : guessed.isAfter(lastDate)
                  ? lastDate
                  : guessed;

          final picked = await showDatePicker(
            context: context,
            initialDate: initialDate,
            firstDate: firstDate,
            lastDate: lastDate,
          );
          if (picked != null) {
            query = DateFormat('yyyy-MM-dd').format(picked);
            showSuggestions(context);
          }
        },
      ),
      if (query.isNotEmpty)
        IconButton(
          onPressed: () => query = '',
          icon: const Icon(Icons.clear),
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    final results = query.isEmpty ? _sortedEvents : _filterEvents(query);
    return _buildEventList(context, results);
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    final suggestions = query.isEmpty ? _sortedEvents : _filterEvents(query);
    return _buildEventList(context, suggestions);
  }

  Widget _buildEventList(BuildContext context, List<Event> events) {
    if (events.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.search_off, size: 48, color: Colors.blueGrey),
            SizedBox(height: 12),
            Text(
              'No matching events',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 4),
            Text(
              'Try searching by title, description, or category.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemBuilder: (context, index) {
        final event = events[index];
        final isCompletedTask =
            event.type == EventType.task && event.isCompleted;
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.blue[600],
            foregroundColor: Colors.white,
            child:
                Text(event.title.isNotEmpty ? event.title[0].toUpperCase() : '?'),
          ),
          title: Text(
            event.title,
            style: isCompletedTask
                ? const TextStyle(
                    decoration: TextDecoration.lineThrough,
                    color: Colors.blueGrey,
                  )
                : null,
          ),          subtitle: Text(_formatSubtitle(event)),
          onTap: () => close(context, event),
        );
      },
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 72, endIndent: 16),
      itemCount: events.length,
    );
  }

  String _formatSubtitle(Event event) {
    final dateLabel = DateFormat('MMM d, yyyy').format(event.date);

    final completionLabel =
        event.type == EventType.task && event.isCompleted ? ' · Completed' : '';

    if (event.hasTimeRange) {
      final start = DateTime(
        event.date.year,
        event.date.month,
        event.date.day,
        event.startTime!.hour,
        event.startTime!.minute,
      );
      final end = DateTime(
        event.date.year,
        event.date.month,
        event.date.day,
        event.endTime!.hour,
        event.endTime!.minute,
      );
      final timeRange =
          '${DateFormat('h:mm a').format(start)} - ${DateFormat('h:mm a').format(end)}';
      return '${event.type.label} · $dateLabel · $timeRange · ${event.category}$completionLabel';
    }

    return '${event.type.label} · $dateLabel · All day · ${event.category}$completionLabel';
  }

}

class _DateQuery {
  const _DateQuery({this.year, this.month, this.day});

  final int? year;
  final int? month;
  final int? day;

  bool matches(DateTime date) {
    if (year != null && date.year != year) return false;
    if (month != null && date.month != month) return false;
    if (day != null && date.day != day) return false;
    return true;
  }
}

DateTime? _safeDate(int year, int month, int day) {
  if (month < 1 || month > 12) return null;
  try {
    final d = DateTime(year, month, day);
    if (d.year == year && d.month == month && d.day == day) {
      return d;
    }
  } catch (_) {
    // invalid date like Feb 30
  }
  return null;
}


DateTime _todayBase() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

_DateQuery? _parseDateQueryLoose(String input) {
  var q = input.trim().toLowerCase();

  // 1) Special words with prefix support
  const words = {
    'today': 0,
    'tomorrow': 1,
    'yesterday': -1,
  };
  final specials = words.keys.where((w) => w.startsWith(q)).toList();
  if (specials.length == 1) {
    final delta = words[specials.first]!;
    final base = _todayBase().add(Duration(days: delta));
    return _DateQuery(year: base.year, month: base.month, day: base.day);
  }

  // 2) Year-month[-day] like "2025", "2025-09", "2025/9/2" (partial allowed)
  final ymd = RegExp(r'^(\d{4})(?:[-/\.](\d{1,2})(?:[-/\.](\d{1,2}))?)?$');
  final ymdM = ymd.firstMatch(q);
  if (ymdM != null) {
    final y = int.parse(ymdM.group(1)!);
    final m = ymdM.group(2) != null ? int.parse(ymdM.group(2)!) : null;
    final d = ymdM.group(3) != null ? int.parse(ymdM.group(3)!) : null;
    if (m == null) return _DateQuery(year: y);                  // year only
    if (d == null) return _DateQuery(year: y, month: m);        // year-month
    final ok = _safeDate(y, m, d) != null;
    return ok ? _DateQuery(year: y, month: m, day: d) : null;   // full date
  }

  // 3) Numeric no-year like "9/29" or "09-29" (assume current year)
  final md = RegExp(r'^(\d{1,2})[-/\.](\d{1,2})$');
  final mdM = md.firstMatch(q);
  if (mdM != null) {
    final now = DateTime.now();
    final a = int.parse(mdM.group(1)!);
    final b = int.parse(mdM.group(2)!);
    // Try MM/DD first, then DD/MM
    if (_safeDate(now.year, a, b) != null) return _DateQuery(year: now.year, month: a, day: b);
    if (_safeDate(now.year, b, a) != null) return _DateQuery(year: now.year, month: b, day: a);
  }

  // 4) Month-name (prefix) forms like "sep", "sept 2", "september 2025", "2 sep 2025"
  final tokens = q.split(RegExp(r'[\s,.-]+')).where((t) => t.isNotEmpty).toList();
  if (tokens.isNotEmpty) {
    final monthMap = <String, int>{
      'january':1,'jan':1,
      'february':2,'feb':2,
      'march':3,'mar':3,
      'april':4,'apr':4,
      'may':5,
      'june':6,'jun':6,
      'july':7,'jul':7,
      'august':8,'aug':8,
      'september':9,'sep':9,'sept':9,
      'october':10,'oct':10,
      'november':11,'nov':11,
      'december':12,'dec':12,
    };

    int? pickMonthPrefix(String t) {
      final hits = monthMap.entries.where((e) => e.key.startsWith(t)).map((e) => e.value).toSet().toList();
      return hits.length == 1 ? hits.first : null; // only if unambiguous
    }

    final now = DateTime.now();

    // Try patterns:
    //  a) "<monPrefix>"          -> month of current year
    //  b) "<monPrefix> <day>"    -> specific day this year
    //  c) "<monPrefix> <year>"   -> any day in that month (month match)
    //  d) "<day> <monPrefix> [year]" -> specific day
    //  e) "<monPrefix> <day> <year>" -> specific day
    if (tokens.length == 1) {
      final m = pickMonthPrefix(tokens[0]);
      if (m != null) return _DateQuery(year: now.year, month: m); // month-only
    } else if (tokens.length == 2) {
      final mA = pickMonthPrefix(tokens[0]);
      final mB = pickMonthPrefix(tokens[1]);
      if (mA != null && RegExp(r'^\d{1,2}$').hasMatch(tokens[1])) {
        final d = int.parse(tokens[1]);
        if (_safeDate(now.year, mA, d) != null) return _DateQuery(year: now.year, month: mA, day: d);
      }
      if (mA != null && RegExp(r'^\d{4}$').hasMatch(tokens[1])) {
        final y = int.parse(tokens[1]);
        return _DateQuery(year: y, month: mA); // year-month
      }
      if (RegExp(r'^\d{1,2}$').hasMatch(tokens[0]) && mB != null) {
        final d = int.parse(tokens[0]);
        if (_safeDate(now.year, mB, d) != null) return _DateQuery(year: now.year, month: mB, day: d);
      }
    } else if (tokens.length >= 3) {
      // e.g., "sep 2 2025", "2 sep 2025"
      int? day, month, year;
      for (final t in tokens) {
        month ??= pickMonthPrefix(t);
      }
      for (final t in tokens) {
        if (year == null && RegExp(r'^\d{4}$').hasMatch(t)) year = int.parse(t);
      }
      for (final t in tokens) {
        if (day == null && RegExp(r'^\d{1,2}$').hasMatch(t)) day = int.parse(t);
      }
      year ??= now.year;
      if (month != null && day != null && _safeDate(year, month, day) != null) {
        return _DateQuery(year: year, month: month, day: day);
      }
    }
  }

  return null; // not a date-like query
}