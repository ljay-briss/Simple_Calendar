import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;


import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'note_editor_page.dart';
part 'notes_folder_page.dart';

// Core data definitions shared across the calendar, tasks, and notes views.
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

// Supported recurrence options for timed events.
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

// Tabs shown in the bottom navigation bar.
enum HomeTab { calendar, notes, daily }

// Internal toggle for the daily/weekly schedule views on the daily tab.
enum _ScheduleView { daily, weekly }

// Weekly view tabs to switch between schedule and free time breakdowns.
enum _WeeklyTab { schedule, freeTime }


// Standard reminder presets offered in the event editor.
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

// Categories shared between events and notes to keep tagging consistent.
const List<String> kCategoryOptions = <String>[
  'General',
  'Work',
  'Personal',
  'Family',
  'Health',
  'Education',
  'School',
  'Sport',
  'Travel',
  'Entertainment',
  'Other',
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
// Event model and serialization
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

  Event({
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
    DateTime parseDate(String? s) {
      if (s == null || s.isEmpty) return DateTime.now();
      try {
        return DateTime.parse(s);
      } catch (_) {
        return DateTime.now();
      }
    }

    final date = parseDate(map['date'] as String?);
    final start = _timeOfDayFromMap(map['startTime']);
    final end = _timeOfDayFromMap(map['endTime']);
    final reminder = _durationFromMinutes(map['reminderMinutes']);
    final type = _eventTypeFromString(map['type']) ?? EventType.event;
    final repeat = _repeatFrequencyFromString(map['repeatFrequency']) ?? RepeatFrequency.none;
    final isCompleted = map['isCompleted'] is bool ? map['isCompleted'] as bool : _boolFromAny(map['isCompleted']);

    return Event(
      title: (map['title'] as String?) ?? '',
      description: (map['description'] as String?) ?? '',
      date: date,
      startTime: start,
      endTime: end,
      category: (map['category'] as String?) ?? 'General',
      type: type,
      reminder: reminder,
      repeatFrequency: repeat,
      isCompleted: isCompleted,
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
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final lower = value.toLowerCase();
      if (lower == 'true') return true;
      if (lower == 'false') return false;
    }
    return false;
  }
}

// Note model representing quick notes and checklists that can live beside events.
class NoteEntry {
  final String id;
  final String title;
  final String description;
  final String category;
  final DateTime? date;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isPinned;
  final bool addedToCalendar;
  final bool isChecklist;

  const NoteEntry({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    this.date,
    required this.createdAt,
    required this.updatedAt,
    this.isPinned = false,
    this.addedToCalendar = false,
     this.isChecklist = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'category': category,
      'date': date?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'isPinned': isPinned,
      'addedToCalendar': addedToCalendar,
      'isChecklist': isChecklist,
    };
  }

  factory NoteEntry.fromMap(Map<String, dynamic> map) {
    DateTime? parseOpt(String? s) {
      if (s == null || s.isEmpty) return null;
      try {
        return DateTime.parse(s);
      } catch (_) {
        return null;
      }
    }

    DateTime parseOrNow(String? s) {
      if (s == null || s.isEmpty) return DateTime.now();
      try {
        return DateTime.parse(s);
      } catch (_) {
        return DateTime.now();
      }
    }

    final createdAt = parseOrNow(map['createdAt'] as String?);
    final updatedAtStr = map['updatedAt'] as String?;
    final updatedAt = updatedAtStr == null ? createdAt : parseOrNow(updatedAtStr);

    final id = (map['id'] as String?) ?? createdAt.microsecondsSinceEpoch.toString();

    final addedToCalendarValue = map['addedToCalendar'];
    final isChecklistValue = map['isChecklist'];
    final isPinnedValue = map['isPinned'];

    return NoteEntry(
      id: id,
      title: (map['title'] as String?) ?? '',
      description: (map['description'] as String?) ?? '',
      category: (map['category'] as String?) ?? 'General',
      date: parseOpt(map['date'] as String?),
      createdAt: createdAt,
      updatedAt: updatedAt,
      isPinned: isPinnedValue is bool ? isPinnedValue : Event._boolFromAny(isPinnedValue),
      addedToCalendar: addedToCalendarValue is bool
          ? addedToCalendarValue
          : Event._boolFromAny(addedToCalendarValue),
        isChecklist: isChecklistValue is bool
          ? isChecklistValue
          : Event._boolFromAny(isChecklistValue),
    );
  }

  NoteEntry copyWith({
    String? id,
    String? title,
    String? description,
    String? category,
    DateTime? date,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isPinned,
    bool? addedToCalendar,
    bool? isChecklist,
  }) {
    return NoteEntry(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      date: date ?? this.date,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isPinned: isPinned ?? this.isPinned,
      addedToCalendar: addedToCalendar ?? this.addedToCalendar,
      isChecklist: isChecklist ?? this.isChecklist,
    );
  }
}



class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  // Calendar navigation and displayed data sets.
  DateTime _selectedDate = DateTime.now();
  DateTime _currentMonth = DateTime(DateTime.now().year, DateTime.now().month);
  final List<Event> _events = [];
  final List<NoteEntry> _notes = [];
  bool _showIntroCard = true;
  HomeTab _currentTab = HomeTab.calendar;
  _ScheduleView _currentScheduleView = _ScheduleView.daily;
  _WeeklyTab _currentWeeklyTab = _WeeklyTab.schedule;

  // Local persistence keys and cache handle for SharedPreferences.
  SharedPreferences? _cachedPrefs;
  static const String _eventsStorageKey = 'calendar_events';
  static const String _introCardStorageKey = 'calendar_intro_card';
  static const String _notesStorageKey = 'calendar_notes';

  // Hours that bound the daily/weekly time grid views.
  static const int _dayStartHour = 8;
  static const int _dayEndHour = 20;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPersistedState());
  }

  // Lazily retrieve shared preferences so disk access happens off the first
  // build frame and is reused across saves and loads.
  Future<SharedPreferences> _getPrefs() async {
    return _cachedPrefs ??= await SharedPreferences.getInstance();
  }


  // Load stored events/notes along with the onboarding card dismissal flag,
  // parsing each JSON payload defensively so corrupt entries do not crash UI.
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
        ..addAll(loadedEvents.where((event) => event.type != EventType.note));
      _notes
        ..clear()
        ..addAll(loadedNotes);
      _showIntroCard = showIntroPref ?? _events.isEmpty;
    });
    unawaited(_persistEvents());
  }

  // Write the current events list back to disk after creation/edits.
  Future<void> _persistEvents() async {
    final prefs = await _getPrefs();
    final encoded = _events
        .where((event) => event.type != EventType.note)
        .map((event) => jsonEncode(event.toMap()))
        .toList();
    await prefs.setStringList(_eventsStorageKey, encoded);
  }

  void _upsertNote(NoteEntry note) {
    final i = _notes.indexWhere((n) => n.id == note.id);
    setState(() {
      if (i == -1) {
        _notes.add(note);
      } else {
        _notes[i] = note;
      }
    });
    unawaited(_saveNotes());
  }

  void _deleteNote(String id) {
    setState(() => _notes.removeWhere((n) => n.id == id));
    unawaited(_saveNotes());
  }

  void _togglePin(String id) {
    final i = _notes.indexWhere((n) => n.id == id);
    if (i == -1) return;

    final current = _notes[i];
    final updated = current.copyWith(
      isPinned: !current.isPinned,
      updatedAt: DateTime.now(),
    );

    setState(() => _notes[i] = updated);
    unawaited(_saveNotes());
  }

  // Persist notes list to local storage whenever changes occur.
  Future<void> _saveNotes() async {
    final prefs = await _getPrefs();
    final encoded = _notes.map((note) => jsonEncode(note.toMap())).toList();
    await prefs.setStringList(_notesStorageKey, encoded);
  }

  // Remember whether the intro banner is dismissed so it only shows once.
  Future<void> _persistIntroCard(bool value) async {
    final prefs = await _getPrefs();
    await prefs.setBool(_introCardStorageKey, value);
  }

  void _handleEventAdded(Event event) {
    if (event.type == EventType.note) {
      return;
    }
    setState(() {
      _events.add(event);
    });
    unawaited(_persistEvents());
  }

  void _handleNoteAdded(NoteEntry note) {
    _upsertNote(note);
  }

  @override
  Widget build(BuildContext context) {
    final eventsForSelectedDate = _getEventsForDate(_selectedDate);
    final freeSlots =
        _calculateFreeTimeSlots(eventsForSelectedDate, targetDate: _selectedDate);

    // Each tab is rendered independently so the surrounding scaffold stays
    // consistent while switching between calendar, notes, and daily planner.
    final body = (() {
      switch (_currentTab) {
        case HomeTab.calendar:
          return _buildCalendarBody(eventsForSelectedDate, freeSlots);
        case HomeTab.notes:
          return _buildNotesBody();
        case HomeTab.daily:
          return _buildDailyBody(eventsForSelectedDate);
      }
    })();


    return Scaffold(
      backgroundColor:
          _currentTab == HomeTab.daily ? Colors.white : const Color(0xFFF5F7FB),
      body: SafeArea(child: body),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  Widget _buildCalendarBody(
      List<Event> eventsForSelectedDate, List<_TimeSlot> freeSlots) {
    // Overview tab combines the small month picker, daily agenda, and summaries
    // for free time and scheduled items.
    return Column(
      children: [
        _buildCompactCalendarHeader(),
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

    // Daily tab focuses on scheduling tools including toggleable daily/weekly
    // grids and quick-add buttons for events and notes.
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Row(
            children: [
              _buildCircularIconButton(Icons.arrow_back_ios_new, () {
                setState(() {
                  final deltaDays =
                      _currentScheduleView == _ScheduleView.weekly ? 7 : 1;
                  _selectedDate =
                      _selectedDate.subtract(Duration(days: deltaDays));
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
                  final deltaDays =
                      _currentScheduleView == _ScheduleView.weekly ? 7 : 1;
                  _selectedDate = _selectedDate.add(Duration(days: deltaDays));
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
                _buildScheduleToggle(),
                const SizedBox(height: 12),
                if (_currentScheduleView == _ScheduleView.daily)
                  _buildDailyTimeline(sortedEvents, isToday)
                else
                  _buildWeeklyOverview(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildScheduleToggle() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE9F0FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD8E3FF)),
      ),
      child: Row(
        children: [
          _buildToggleButton('Daily', _ScheduleView.daily, Icons.wb_sunny_rounded),
          const SizedBox(width: 8),
          _buildToggleButton('Weekly', _ScheduleView.weekly, Icons.view_week_rounded),
        ],
      ),
    );
  }

  Widget _buildToggleButton(String label, _ScheduleView view, IconData icon) {
    final isActive = _currentScheduleView == view;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (!isActive) {
            setState(() => _currentScheduleView = view);
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          decoration: BoxDecoration(
            color: isActive ? Colors.white : const Color(0xFFDDE7FB),
            borderRadius: BorderRadius.circular(12),
            boxShadow: isActive
                ? const [
                    BoxShadow(
                      color: Color(0x142C3A4B),
                      blurRadius: 10,
                      offset: Offset(0, 6),
                    ),
                  ]
                : [],
            border: Border.all(
              color: isActive ? const Color(0xFFBFD4FF) : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 18,
                  color: isActive ? Colors.blue[700] : Colors.blueGrey[600]),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: isActive ? Colors.blue[800] : Colors.blueGrey[700],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _calculateScheduledHours(List<Event> events) {
    return events.fold<double>(0, (sum, event) {
      if (event.startTime == null || event.endTime == null) return sum + 1;
      final startMinutes = (event.startTime!.hour * 60) + event.startTime!.minute;
      final endMinutes = (event.endTime!.hour * 60) + event.endTime!.minute;
      final durationMinutes = (endMinutes - startMinutes).clamp(30, 180);
      return sum + (durationMinutes / 60).toDouble();
    });
  }

  Widget _buildWeeklyOverview() {
    // Google Calendar style: week grid, not summary cards
    final weekStart = _selectedDate.subtract(Duration(days: _selectedDate.weekday - 1));
    final weekDays = List.generate(7, (i) => weekStart.add(Duration(days: i)));

    // Keep the visual proportions of the calendar grid consistent and avoid the
    // blank gutter that appeared when the height calculation did not match the
    // grid cell height.
    const startHour = 1;
    const endHour = 23;
    const hourHeight = 50.0;
    final totalHours = endHour - startHour + 1;
    final gridHeight = totalHours * hourHeight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildWeeklyTabToggle(),
        const SizedBox(height: 12),
        if (_currentWeeklyTab == _WeeklyTab.schedule) ...[
          _buildWeeklyHeaderRow(weekDays),
          const SizedBox(height: 12),
          SizedBox(
            height: gridHeight,
            child: _buildWeeklyTimeGrid(
              weekDays,
              startHour: startHour,
              endHour: endHour,
              hourHeight: hourHeight,
            ),
          ),
          const SizedBox(height: 16),
          _buildWeeklySummarySection(weekDays),
        ] else
          _buildWeeklyFreeTimeSection(weekDays),
      ],
    );
  }

  Widget _buildWeeklyTabToggle() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F4FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD8E3FF)),
      ),
      child: Row(
        children: [
          _buildWeeklyTabButton('Schedule', _WeeklyTab.schedule, Icons.view_week_rounded),
          const SizedBox(width: 8),
          _buildWeeklyTabButton('Free time', _WeeklyTab.freeTime, Icons.timer_outlined),
        ],
      ),
    );
  }


  Widget _buildWeeklyTabButton(String label, _WeeklyTab tab, IconData icon) {
    final isActive = _currentWeeklyTab == tab;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (!isActive) {
            setState(() => _currentWeeklyTab = tab);
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          decoration: BoxDecoration(
            color: isActive ? Colors.white : const Color(0xFFDDE7FB),
            borderRadius: BorderRadius.circular(12),
            boxShadow: isActive
                ? const [
                    BoxShadow(
                      color: Color(0x142C3A4B),
                      blurRadius: 10,
                      offset: Offset(0, 6),
                    ),
                  ]
                : [],
            border: Border.all(
              color: isActive ? const Color(0xFFBFD4FF) : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: isActive ? Colors.blue[700] : Colors.blueGrey[600]),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: isActive ? Colors.blue[800] : Colors.blueGrey[700],                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWeeklyHeaderRow(List<DateTime> days) {
    const timeColWidth = 52.0;
    final today = DateTime.now();


    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.blueGrey.shade200),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: timeColWidth),
          for (final day in days)
            Expanded(
              child: _WeeklyHeaderCell(
                day: day,
                today: today,
                selectedDate: _selectedDate,
                onTap: () {
                  setState(() {
                    _selectedDate = day;
                    _currentScheduleView = _ScheduleView.daily;
                  });
                },
              ),
            ),
        ],
      ),
    );
  }


  Widget _buildWeeklyTimeGrid(
    List<DateTime> days, {
    required int startHour,
    required int endHour,
    required double hourHeight,
  }) {
    const timeColWidth = 52.0;

    final totalHours = endHour - startHour + 1;
    final gridHeight = totalHours * hourHeight;

    return LayoutBuilder(
      builder: (context, constraints) {
        final gridWidth = constraints.maxWidth;
        final dayWidth = (gridWidth - timeColWidth) / 7;

        return SizedBox(
          width: gridWidth,
          height: gridHeight,
          child: _buildWeeklyGridStack(
            days: days,
            startHour: startHour,
            endHour: endHour,
            hourHeight: hourHeight,
            timeColWidth: timeColWidth,
            gridWidth: gridWidth,
            dayWidth: dayWidth,
          ),
        );
      },
    );
  }

  Widget _buildWeeklySummarySection(List<DateTime> weekDays) {
    final weekStart = weekDays.first;
    final weekEnd = weekDays.last;

    final eventsByDay = weekDays
        .map((day) => MapEntry(day, _getEventsForDate(day)))
        .where((entry) => entry.value.isNotEmpty)
        .toList();

    return _OverviewSection(
      title:
          'Week of ${DateFormat('MMM d').format(weekStart)} - ${DateFormat('MMM d, yyyy').format(weekEnd)}',
      child: eventsByDay.isEmpty
          ? const _EmptyOverviewMessage(
              message: 'No events scheduled this week yet.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < eventsByDay.length; i++) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      DateFormat('EEEE, MMM d').format(eventsByDay[i].key),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  ...eventsByDay[i].value.map(_buildEventTile),
                  if (i != eventsByDay.length - 1) const SizedBox(height: 8),
                ],
              ],
            ),
    );
  }

  Widget _buildWeeklyFreeTimeSection(List<DateTime> weekDays) {
    final freeSlotsByDay = weekDays
        .map((day) => MapEntry(day, _calculateFreeTimeSlots(_getEventsForDate(day), targetDate: day)))
        .toList();

    final hasAnyFreeTime = freeSlotsByDay.any((entry) => entry.value.isNotEmpty);

    return _OverviewSection(
      title: 'Free time this week',
      child: hasAnyFreeTime
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < freeSlotsByDay.length; i++) ...[
                  _buildWeeklyFreeTimeCard(freeSlotsByDay[i].key, freeSlotsByDay[i].value),
                  if (i != freeSlotsByDay.length - 1) const SizedBox(height: 12),
                ],
              ],
            )
          : const _EmptyOverviewMessage(
              message: 'No free time detected this week. Add time ranges to see openings.',
            ),
    );
  }

  Widget _buildWeeklyFreeTimeCard(DateTime date, List<_TimeSlot> slots) {
    final totalDuration = slots.fold<Duration>(Duration.zero, (sum, slot) => sum + slot.duration);
    final dateLabel = DateFormat('EEE, MMM d').format(date);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4EAF3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: Colors.green[500],
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  dateLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
              if (totalDuration > Duration.zero)
                _buildSummaryChip(Icons.timer_outlined, _formatDuration(totalDuration)),
            ],
          ),
          const SizedBox(height: 10),
          if (slots.isEmpty)
            Text(
              'No free time',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.blueGrey[500],
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final slot in slots)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(Icons.timer_outlined, size: 16, color: Colors.green[600]),
                        const SizedBox(width: 8),
                        Text(
                          '${_formatTime(slot.start)} - ${_formatTime(slot.end)} · ${_formatDuration(slot.duration)}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }


  List<Widget> _buildWeeklyNowLine(
    List<DateTime> days,
    double timeColWidth,
    double dayWidth,
    int startHour,
    int endHour,
    double hourHeight,
  ) {
    final now = DateTime.now();
    final todayIndex = days.indexWhere((d) => DateUtils.isSameDay(d, now));
    if (todayIndex == -1) return [];

    final totalMinutes = (endHour - startHour + 1) * 60;
    final nowMinutes = ((now.hour - startHour) * 60) + now.minute;
    if (nowMinutes < 0 || nowMinutes > totalMinutes) return [];

    final top = ((nowMinutes.clamp(0, totalMinutes)) / 60) * hourHeight;
    final left = timeColWidth + (todayIndex * dayWidth);

    return [
      Positioned(
        top: top,
        left: left,
        width: dayWidth,
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: Colors.red[600],
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(child: Container(height: 1.5, color: Colors.red[300])),
          ],
        ),
      ),
    ];
  }


  Widget _buildWeeklyGridStack({
    required List<DateTime> days,
    required int startHour,
    required int endHour,
    required double hourHeight,
    required double timeColWidth,
    required double gridWidth,
    required double dayWidth,
  }) {
    final totalHours = endHour - startHour + 1;
    final gridHeight = totalHours * hourHeight;

    const double lineOffset = 10; // MUST match the hour-line margin top

    return SizedBox(
      width: gridWidth,
      height: gridHeight,
      child: Stack(
        children: [
          // hour grid
          Column(
            children: List.generate(totalHours, (i) {
              final hour = startHour + i;
              return SizedBox(
                height: hourHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: timeColWidth,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 6, right: 8),
                        child: Text(
                          _formatHourLabel(hour),
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          style: TextStyle(
                            color: Colors.blueGrey[400],
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.only(top: lineOffset),
                        height: 1,
                        color: const Color(0xFFE4EAF3),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        // vertical separators
        Positioned(
          left: timeColWidth,
          top: 0,
          bottom: 0,
          child: SizedBox(
            width: gridWidth - timeColWidth,
            child: Row(
              children: List.generate(7, (_) {
                return Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                      border: Border(
                        right: BorderSide(color: Color(0xFFE7EDF6)),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),

        // events — snapped to the visible grid lines
        for (int dayIndex = 0; dayIndex < 7; dayIndex++)
          ..._getEventsForDate(days[dayIndex]).map((event) {
            final start =
                event.startTime ?? TimeOfDay(hour: startHour, minute: 0);
            final end = event.endTime ??
                TimeOfDay(
                  hour: math.min(start.hour + 1, endHour),
                  minute: 0,
                );

            // snap to full hours
            final snappedStartHour = start.hour.clamp(startHour, endHour);
            final snappedEndHour = end.hour.clamp(snappedStartHour + 1, endHour + 1);

            // IMPORTANT: top includes lineOffset so it aligns to the drawn grid line
            final top = ((snappedStartHour - startHour) * hourHeight) + lineOffset;
            final height = (snappedEndHour - snappedStartHour) * hourHeight;

            final left = timeColWidth + (dayIndex * dayWidth);

            return Positioned(
              top: top,
              left: left,
              width: dayWidth,
              height: height,
              child: _buildWeeklyEventBlock(event, start, end),
            );
          }),
      ],
    ),
  );
}







Widget _buildWeeklyEventBlock(Event event, TimeOfDay start, TimeOfDay end) {
  return Container(
    padding: const EdgeInsets.all(5),
    decoration: BoxDecoration(
      color: Colors.blue[600],
      borderRadius: BorderRadius.circular(5),
    ),
    child: DefaultTextStyle(
      style: const TextStyle(color: Colors.white),
      child: Text(
        event.title,
        maxLines: 1,
        overflow: TextOverflow.clip,
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    ),
  );
}




  Widget _buildWeeklyDayCard(DateTime date, List<Event> events) {
    final isSelected = _isSameDay(date, _selectedDate);
    final isToday = _isSameDay(date, DateTime.now());
    final scheduledHours = _calculateScheduledHours(events);
    final eventCount = events.length;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedDate = date;
          _currentScheduleView = _ScheduleView.daily;
        });
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE9F1FF) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color:
                isSelected ? const Color(0xFFBFD4FF) : const Color(0xFFE5EAF2),
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0D000000),
              blurRadius: 10,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isToday ? Colors.blue[50] : const Color(0xFFF6F8FC),
                shape: BoxShape.circle,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    DateFormat('EEE').format(date),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.blueGrey[700],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    DateFormat('d').format(date),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.blueGrey[900],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        DateFormat('MMMM d').format(date),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      if (isToday) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red[50],
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'Today',
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
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _buildScheduleChip(
                        Icons.schedule,
                        '${scheduledHours.toStringAsFixed(1)} hrs',
                      ),
                      _buildScheduleChip(
                        Icons.check_circle_outline,
                        '$eventCount scheduled',
                      ),
                    ],
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

  Widget _buildScheduleChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F8FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE6EEF9)),
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

  Widget _buildDailyTimeline(List<Event> events, bool isToday) {
    const startHour = 5;
    const endHour = 23;
    const hourHeight = 72.0;
    const minEventHeight = 68.0;
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
        color: const Color(0xFFF9FBFF),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE7EDF6)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
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
                            padding: const EdgeInsets.only(top: 6, right: 8),
                            child: Text(
                              _formatHourLabel(hour),
                              style: TextStyle(
                                color: Colors.blueGrey[400],
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Container(
                                  height: 1,
                                  color: const Color(0xFFE4EAF3),
                                ),
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
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: Colors.red[600],
                          shape: BoxShape.circle,
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x1AF44336),
                              blurRadius: 6,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Container(
                          height: 1.5,
                          color: Colors.red[300],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x142C3A4B),
                              blurRadius: 8,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Text(
                          DateFormat.jm().format(now),
                          style: TextStyle(
                            color: Colors.red[600],
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
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
                final clampedEnd = math.max(
                  clampedStart + 45,
                  math.min(endMinutes, (endHour - startHour + 1) * 60),
                );

                final top = (clampedStart / 60) * hourHeight;
                final height = ((clampedEnd - clampedStart) / 60) * hourHeight;
                final visualHeight = height < minEventHeight ? minEventHeight : height;

                return Positioned(
                  top: top,
                  left: 76,
                  right: 16,
                  child: SizedBox(
                    height: visualHeight,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isCompact = constraints.maxHeight <= minEventHeight + 0.1;
                        final verticalPadding = isCompact ? 6.0 : 8.0;
                        final betweenTitleAndCategory = isCompact ? 4.0 : 6.0;
                        final betweenCategoryAndTime = isCompact ? 2.0 : 4.0;

                        return DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF3FF),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFD7E2F8)),
                          ),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: verticalPadding,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.max,
                              children: [
                                ConstrainedBox(
                                  constraints: const BoxConstraints(maxHeight: 28),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Flexible(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Text(
                                            event.title,
                                            style: TextStyle(
                                              color: Colors.blue[800],
                                              fontWeight: FontWeight.w600,
                                              fontSize: 11,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Icon(
                                        _iconForEventType(event.type),
                                        size: 16,
                                        color: Colors.blue[700],
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(height: betweenTitleAndCategory),
                                Flexible(
                                  fit: FlexFit.tight,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      event.category,
                                      style: TextStyle(
                                        color: Colors.blueGrey[900],
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                      maxLines: isCompact ? 1 : 2,
                                      overflow: TextOverflow.ellipsis,
                                      softWrap: true,
                                    ),
                                  ),
                                ),
                                SizedBox(height: betweenCategoryAndTime),
                                Text(
                                  _formatEventTimeRange(start, end),
                                  style: TextStyle(
                                    color: Colors.blueGrey[500],
                                    fontWeight: FontWeight.w500,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  String _formatHourLabel(int hour) {
    // Compact label: e.g. 1AM, 12PM — omit ":00" to save horizontal space.
    final isPm = hour >= 12;
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    return '$displayHour${isPm ? 'PM' : 'AM'}';
  }

  String _formatEventTimeRange(TimeOfDay start, TimeOfDay end) {
    return '${_formatTimeOfDay(start)} - ${_formatTimeOfDay(end)}';
  }

  IconData _iconForEventType(EventType type) {
    switch (type) {
      case EventType.task:
        return Icons.checklist_rounded;
      case EventType.note:
        return Icons.sticky_note_2_outlined;
      default:
        return Icons.event;
    }
  }


  Widget _buildNotesBody() {
    final categories = _notes
        .map((n) => n.category.trim())
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    int countFor(String category) => _notes
        .where((n) => n.category.toLowerCase() == category.toLowerCase())
        .length;

    int pinnedCountFor(String category) => _notes
        .where((n) =>
            n.category.toLowerCase() == category.toLowerCase() && n.isPinned)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildNotesTopBar(),
        Expanded(
          child: categories.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      'Create a note to see it appear in a folder.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                  itemCount: categories.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final category = categories[index];
                    return _buildFolderCard(
                      category: category,
                      count: countFor(category),
                      pinnedCount: pinnedCountFor(category),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => NotesFolderPage(
                              category: category,
                              notes: _notes,
                              onUpsert: _upsertNote,
                              onDelete: _deleteNote,
                              onTogglePin: _togglePin,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFolderCard({
    required String category,
    required int count,
    required int pinnedCount,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],        
          ),
        child: Row(
          children: [
            Icon(Icons.folder_outlined, color: Colors.blueGrey[500]),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(category,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  if (pinnedCount > 0) ...[
                    const SizedBox(height: 2),
                    Text('$pinnedCount pinned',
                        style: TextStyle(fontSize: 12, color: Colors.blueGrey[500])),
                  ],
                ],
              ),
            ),
            Text('$count',
                style: TextStyle(color: Colors.blueGrey[400], fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right, color: Colors.blueGrey[300]),
          ],
        ),
      ),
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


Widget _buildCompactCalendarHeader() {
  final monthLabel = DateFormat('MMMM yyyy').format(_currentMonth);

  return SafeArea(
    bottom: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [

          _RoundedArrowButton(
            icon: Icons.chevron_left,
            onTap: () {
              setState(() {
                _currentMonth =
                    DateTime(_currentMonth.year, _currentMonth.month - 1);
                _selectedDate =
                    DateTime(_currentMonth.year, _currentMonth.month, 1);
              });
            },
          ),

          const SizedBox(width: 8),

          Expanded(
            child: Center(
              child: Text(
                monthLabel,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),

          const SizedBox(width: 8),

          _RoundedArrowButton(
            icon: Icons.chevron_right,
            onTap: () {
              setState(() {
                _currentMonth =
                    DateTime(_currentMonth.year, _currentMonth.month + 1);
                _selectedDate =
                    DateTime(_currentMonth.year, _currentMonth.month, 1);
              });
            },
          ),

          const SizedBox(width: 10),

          _buildIconButton(Icons.search, _showEventSearch),
          const SizedBox(width: 8),
          _buildIconButton(Icons.person_outline, () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ProfilePage()),
            );
          }),
        ],
      ),
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
        delegate: EventSearchDelegate(
        events: List<Event>.from(
          _events.where((event) => event.type != EventType.note),
        ),
      ),
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



Widget _buildCalendarCard(List<Event> eventsForSelectedDate) {
  return Container(
    margin: EdgeInsets.zero,
    decoration: BoxDecoration(
      color: Colors.white,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 16,
          offset: const Offset(0, 10),
        ),
      ],
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      child: Column(
        children: [
          _buildWeekdayHeader(),
          const SizedBox(height: 12),
          _buildCalendarGrid(eventsForSelectedDate),
        ],
      ),
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
  const labels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: Row(
      children: List.generate(7, (i) {
        return Expanded(
          child: Center(
            child: Text(
              labels[i],
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.blueGrey[500],
              ),
            ),
          ),
        );
      }),
    ),
  );
}


Widget _buildCalendarGrid(List<Event> eventsForSelectedDate) {
  final firstOfMonth = DateTime(_currentMonth.year, _currentMonth.month, 1);

  // weekday: Mon=1..Sun=7, we want Sun=0..Sat=6
  final startOffset = firstOfMonth.weekday % 7;
  final gridStart = firstOfMonth.subtract(Duration(days: startOffset));

  return GridView.builder(
    padding: EdgeInsets.zero,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 7,
      mainAxisSpacing: 0,
      crossAxisSpacing: 0,
      childAspectRatio: .80, // tweak if you want taller cells
    ),
    itemCount: 42,
    itemBuilder: (context, index) {
      final date = DateTime(gridStart.year, gridStart.month, gridStart.day + index);

      final isInMonth = date.month == _currentMonth.month;
      final isSelected = _isSameDay(date, _selectedDate);
      final isToday = _isSameDay(date, DateTime.now());

      final dayEvents = _getEventsForDate(date);
      final hasEvents = dayEvents.isNotEmpty;

      // Draw thin grid lines like the reference
      final isLastCol = (index % 7) == 6;
      final isLastRow = index >= 35;

      return InkWell(
        onTap: () {
          setState(() => _selectedDate = date);
        },
        child: Container(
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.blue.withOpacity(0.08) // subtle selected cell wash
                : Colors.white,
            border: Border(
              right: isLastCol
                  ? BorderSide.none
                  : BorderSide(color: Colors.blueGrey.shade100, width: 1),
              bottom: isLastRow
                  ? BorderSide.none
                  : BorderSide(color: Colors.blueGrey.shade100, width: 1),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.max,
            children: [
              // Day number row with selected circle
              Row(
                children: [
                  Container(
                    width: 35,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected
                          ? Colors.blue[600]
                          : Colors.transparent,
                    ),
                    child: Text(
                      '${date.day}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isSelected
                            ? Colors.white
                            : !isInMonth
                                ? Colors.blueGrey[300]
                                : isToday
                                    ? Colors.blue[700]
                                    : Colors.blueGrey[800],
                      ),
                    ),
                  ),
                  const Spacer(),
                ],
              ),

              const SizedBox(height: 6),

              // Event chip like the reference ("Welco...")
              Expanded(
                child: hasEvents
                    ? Container(
                        constraints: const BoxConstraints(minWidth: 100, minHeight: 22),
                        alignment: Alignment.center, // 👈 controls text position in pill
                        decoration: BoxDecoration(
                          color: Colors.blue[600],
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          dayEvents.first.title,
                          maxLines: 1,
                          textAlign: TextAlign.center, // 👈 text alignment
                          overflow: TextOverflow.clip,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
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
    final minHeight = math.max(52.0, estimatedMinHeight);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 1),
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

  void _handleAddTap() {
    switch (_currentTab) {      
      
      case HomeTab.calendar:
      case HomeTab.daily:
        _showAddEventDialog();
        break;
      case HomeTab.notes:
        _showAddNoteDialog();
        break;    
    }
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
        .where(
          (event) =>
              event.type != EventType.note && _occursOnDate(event, targetDate),
        )
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
      case 'general':
        return Colors.blueGrey;
      case 'work':
        return Colors.blue;
      case 'personal':
        return Colors.green;
      case 'family':
        return Colors.deepOrange;
      case 'health':
        return Colors.redAccent;
      case 'education':
        return Colors.deepPurple;
      case 'school':
        return Colors.teal;
      case 'sport':
        return Colors.lightGreen;
      case 'travel':
        return Colors.orange;
      case 'entertainment':
        return Colors.pinkAccent;
      case 'other':
        return Colors.indigoAccent;
      default:
        return Colors.blueGrey;
    }
  }

  List<_TimeSlot> _calculateFreeTimeSlots(List<Event> events, {DateTime? targetDate}) {
    final blockingEvents =
        events.where((event) => event.type != EventType.note).toList();

    if (blockingEvents.any((event) => !event.hasTimeRange)) {
      return [];
    }

    final date = targetDate ?? _selectedDate;

    final dayStart = DateTime(
      date.year,
      date.month,
      date.day,
      _dayStartHour,
    );
    final dayEnd = DateTime(
      date.year,
      date.month,
      date.day,
      _dayEndHour,
    );

    final scheduled = blockingEvents
        .where((event) => event.hasTimeRange)
        .map(
          (event) => _TimeSlot(
            start: _dateWithTime(date, event.startTime!),
            end: _dateWithTime(date, event.endTime!),
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
    // Compact time formatting: omit ":00" when minutes == 0 and remove
    // the space before AM/PM to save horizontal space (e.g. "1AM", "1:30AM").
    final hour24 = time.hour;
    final minute = time.minute;
    final isPm = hour24 >= 12;
    final displayHour = hour24 % 12 == 0 ? 12 : hour24 % 12;
    final ampm = isPm ? 'PM' : 'AM';
    if (minute == 0) return '$displayHour$ampm';
    final minStr = minute.toString().padLeft(2, '0');
    return '$displayHour:$minStr$ampm';
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
    final result = await showDialog<NoteEntry>(
      context: context,
      builder: (context) => const AddNoteDialog(),
    );

    if (result != null) {
      _handleNoteAdded(result);
      const message = 'Note saved.';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(message)),
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

class _WeeklyHeaderCell extends StatelessWidget {
  final DateTime day;
  final DateTime today;
  final DateTime selectedDate;
  final VoidCallback onTap;

  const _WeeklyHeaderCell({
    required this.day,
    required this.today,
    required this.selectedDate,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isToday = DateUtils.isSameDay(day, today);
    final isSelected = DateUtils.isSameDay(day, selectedDate);

    // pick a “calendar-like” visual: clean cell + subtle selection
    final bg = isSelected
        ? Colors.blue.shade50
        : Colors.transparent;

    final borderColor = Colors.blueGrey.shade200;

    return InkWell(
      onTap: onTap,
      child: Container(
        height: 56, // consistent cell height like month grid rows
        decoration: BoxDecoration(
          color: bg,
          border: Border(
            left: BorderSide(color: borderColor),
            bottom: BorderSide(color: borderColor),
          ),
        ),
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              DateFormat('EEE').format(day).toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Colors.blueGrey[600],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: isToday ? Colors.blue[700] : Colors.blueGrey[900],
              ),
            ),
            // small today indicator like many calendar grids
            if (isToday)
              Container(
                margin: const EdgeInsets.only(top: 3),
                width: 16,
                height: 3,
                decoration: BoxDecoration(
                  color: Colors.blue[600],
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
          ],
        ),
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
      padding: const EdgeInsets.all(6),
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
                : MainAxisAlignment.start,
            children: [
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

String _eventTypeLabel(EventType type) {
  return type == EventType.note ? 'Time Off' : type.label;
}

Widget _sectionLabel(String text) {
  return Text(
    text.toUpperCase(),
    style: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.6,
      color: Colors.blueGrey.shade500,
    ),
  );
}

InputDecoration _sharedInputDecoration({
  required String label,
  IconData? icon,
  bool alignLabelWithHint = false,
}) {
  return InputDecoration(
    labelText: label,
    alignLabelWithHint: alignLabelWithHint,
    labelStyle: TextStyle(
      color: Colors.blueGrey.shade400,
      fontWeight: FontWeight.w600,
    ),
    filled: true,
    fillColor: const Color(0xFFF7F8FA),
    prefixIcon: icon != null ? Icon(icon, color: Colors.blueGrey[400]) : null,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.blueGrey.shade100),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.blueGrey.shade100),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Colors.blue),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
  );
}

class _EventTypeTabs extends StatelessWidget {
  const _EventTypeTabs({
    required this.selected,
    required this.onSelected,
  });

  final EventType selected;
  final ValueChanged<EventType> onSelected;

  @override
  Widget build(BuildContext context) {
    final eventTypes = EventType.values.where((type) => type != EventType.note);
    return Row(
      children: eventTypes.map((type) {
        final isSelected = type == selected;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: GestureDetector(
              onTap: () => onSelected(type),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
                    _eventTypeLabel(type).toUpperCase(),
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
}

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
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
                title,
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
}

class AddNoteDialog extends StatefulWidget {
  const AddNoteDialog({super.key});

  @override
  State<AddNoteDialog> createState() => _AddNoteDialogState();
}

class _AddNoteDialogState extends State<AddNoteDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;


  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _descriptionController = TextEditingController();
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;


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


  void _save() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add a title for this note.')),
      );
      return;
    }


    final now = DateTime.now();
    final note = NoteEntry(
      id: now.microsecondsSinceEpoch.toString(),
      title: title,
      description: _descriptionController.text.trim(),
      category: title,
      date: null,
      createdAt: now,
      updatedAt: now,
      isPinned: false,
      addedToCalendar: false,
    );

    Navigator.of(context).pop(note);
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
  String _selectedCategory = kCategoryOptions.first;
  String _selectedReminderLabel = kReminderOptions.keys.first;
  RepeatFrequency _repeatFrequency = RepeatFrequency.none;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  bool _isAllDay = true;
  late DateTime _selectedDate;

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
              mainAxisSize: MainAxisSize.min,
              children: [
                _DialogHeader(title: _eventTypeLabel(_selectedType)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: _EventTypeTabs(
                    selected: _selectedType,
                    onSelected: (type) => setState(() => _selectedType = type),
                  ),
                ),
                Divider(color: Colors.blueGrey.shade100, height: 24),
                Flexible(
                  child: SafeArea(
                    top: false,
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        20,
                        0,
                        20,
                        24 + viewInsets,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionLabel('Name'),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _titleController,
                            decoration: _sharedInputDecoration(
                              label: 'Name *',
                              icon: Icons.edit_outlined,
                            ),
                            autofocus: true,
                          ),
                          const SizedBox(height: 16),
                          _buildReminderAndCategoryFields(),
                          const SizedBox(height: 20),
                          _sectionLabel('Date'),
                          const SizedBox(height: 8),
                          _buildDatePickerTile(formattedDate),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<RepeatFrequency>(
                            initialValue: _repeatFrequency,
                            decoration: _sharedInputDecoration(
                              label: 'Repeat',
                              icon: Icons.refresh_outlined,
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
                          _sectionLabel('Time'),
                          const SizedBox(height: 8),
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
                            const SizedBox(height: 12),
                            Text(
                              'Duration: $durationLabel',
                              style: TextStyle(
                                color: Colors.blueGrey.shade600,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          _buildAllDayToggle(),
                          const SizedBox(height: 20),
                          _sectionLabel('Details'),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _descriptionController,
                            minLines: 3,
                            maxLines: 5,
                            decoration: _sharedInputDecoration(
                              label: 'Details',
                              icon: Icons.notes_outlined,
                              alignLabelWithHint: true,
                            ),
                          ),
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
      ),
    );
  }


  Widget _buildReminderAndCategoryFields() {
    final reminderField = DropdownButtonFormField<String>(
      initialValue: _selectedReminderLabel,
      isExpanded: true,
      decoration: _sharedInputDecoration(
        label: 'Notification',
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
    final categoryField = DropdownButtonFormField<String>(
      initialValue: _selectedCategory,
      isExpanded: true,
      decoration: _sharedInputDecoration(
        label: 'Add to',
        icon: Icons.folder_outlined,
      ),
      items: kCategoryOptions
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

  Widget _buildAllDayToggle() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() {
          _isAllDay = !_isAllDay;
          if (_isAllDay) {
            _startTime = null;
            _endTime = null;
          }
        }),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F8FA),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blueGrey.shade100),
          ),
          child: Row(
            children: [
              Checkbox(
                value: _isAllDay,
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
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
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }

 

  Widget _buildDatePickerTile(String formattedDate) {
    return InkWell(
      onTap: _pickDate,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F8FA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blueGrey.shade100),
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
          color: const Color(0xFFF7F8FA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blueGrey.shade100),
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
    _type = init.type == EventType.note ? EventType.event : init.type;
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
                _DialogHeader(title: 'Edit ${_eventTypeLabel(_type)}'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: _EventTypeTabs(
                    selected: _type,
                    onSelected: (type) => setState(() => _type = type),
                  ),
                ),
                Divider(color: Colors.blueGrey.shade100, height: 24),
                Expanded(
                  child: SafeArea(
                    top: false,
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        20,
                        0,
                        20,
                        24 + viewInsets,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionLabel('Name'),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _title,
                            decoration: _sharedInputDecoration(
                              label: 'Name *',
                              icon: Icons.edit_outlined,
                            ),
                            autofocus: true,
                          ),
                          const SizedBox(height: 16),
                          _buildReminderAndCategoryFields(),
                          const SizedBox(height: 20),
                          _sectionLabel('Date'),
                          const SizedBox(height: 8),
                          _buildDatePickerTile(formattedDate),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<RepeatFrequency>(
                            initialValue: _repeatFrequency,
                            decoration: _sharedInputDecoration(
                              label: 'Repeat',
                              icon: Icons.refresh_outlined,
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
                          _sectionLabel('Time'),
                          const SizedBox(height: 8),
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
                              style: TextStyle(
                                color: Colors.blueGrey.shade600,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          _sectionLabel('Details'),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _desc,
                            minLines: 3,
                            maxLines: 5,
                            decoration: _sharedInputDecoration(
                              label: 'Details',
                              icon: Icons.notes_outlined,
                              alignLabelWithHint: true,
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
      decoration: _sharedInputDecoration(
        label: 'Notification',
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
        setState(() => _reminderLabel = value);
      },
    );

    final categoryField = DropdownButtonFormField<String>(
      initialValue: _category,
      isExpanded: true,
      decoration: _sharedInputDecoration(
        label: 'Add to',
        icon: Icons.folder_outlined,
      ),
      items: kCategoryOptions
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



  Widget _buildDatePickerTile(String formattedDate) {
    return InkWell(
      onTap: _pickDate,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F8FA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blueGrey.shade100),
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
          color: const Color(0xFFF7F8FA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blueGrey.shade100),
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

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // These map to the rest of your app's look:
    final background = scheme.surface; // or scheme.background
    final card = scheme.surface;
    final border = Colors.blueGrey.shade100;
    final accent = scheme.primary; // your app blue
    final subtle = accent.withOpacity(0.08);

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.blueGrey[800]),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(
                context: context,
                background: subtle,
                accent: accent,
                border: border,
              ),
              const SizedBox(height: 20),

              _ProfileOptionTile(
                icon: Icons.person_outline,
                label: 'Account',
                accentColor: accent,
                cardColor: card,
                borderColor: border,
              ),
              const SizedBox(height: 12),
              _ProfileOptionTile(
                icon: Icons.emoji_events_outlined,
                label: 'Points',
                accentColor: accent,
                cardColor: card,
                borderColor: border,
              ),
              const SizedBox(height: 12),
              _ProfileOptionTile(
                icon: Icons.card_giftcard_outlined,
                label: 'Rewards',
                accentColor: accent,
                cardColor: card,
                borderColor: border,
              ),
              const SizedBox(height: 12),
              _ProfileOptionTile(
                icon: Icons.group_outlined,
                label: 'Friends',
                accentColor: accent,
                cardColor: card,
                borderColor: border,
              ),
              const SizedBox(height: 12),
              _ProfileOptionTile(
                icon: Icons.translate,
                label: 'Language',
                accentColor: accent,
                cardColor: card,
                borderColor: border,
              ),
              const SizedBox(height: 12),
              _ProfileOptionTile(
                icon: Icons.help_outline,
                label: 'Help',
                accentColor: accent,
                cardColor: card,
                borderColor: border,
              ),
              const SizedBox(height: 12),
              _ProfileOptionTile(
                icon: Icons.settings_outlined,
                label: 'Settings',
                accentColor: accent,
                cardColor: card,
                borderColor: border,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader({
    required BuildContext context,
    required Color background,
    required Color accent,
    required Color border,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.workspace_premium, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text(
                  'Level 10',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: border),
            ),
            child: CircleAvatar(
              radius: 24,
              backgroundColor: accent,
              child: const Icon(Icons.person, color: Colors.white, size: 26),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileOptionTile extends StatelessWidget {
  const _ProfileOptionTile({
    required this.icon,
    required this.label,
    required this.accentColor,
    required this.cardColor,
    required this.borderColor,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color accentColor;
  final Color cardColor;
  final Color borderColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Container(
              height: 44,
              width: 44,
              decoration: BoxDecoration(
                color: accentColor,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.blueGrey[800],
                ),
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: Colors.blueGrey[400], size: 18),
          ],
        ),
      ),
    );
  }
}
