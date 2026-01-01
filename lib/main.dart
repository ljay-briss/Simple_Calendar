import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:intl/intl.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_localizations.dart';

part 'note_editor_page.dart';
part 'notes_folder_page.dart';

// Core data definitions shared across the calendar, tasks, and notes views.
enum EventType { event, task, note, timeOff }

extension EventTypeExtension on EventType {
  String get label {
    switch (this) {
      case EventType.event:
        return 'Event';
      case EventType.task:
        return 'Task';
      case EventType.note:
        return 'Note';
      case EventType.timeOff:
        return 'Time Off';
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

String _localeToString(Locale locale) {
  return locale.countryCode == null || locale.countryCode!.isEmpty
      ? locale.languageCode
      : '${locale.languageCode}_${locale.countryCode}';
}

Locale? _localeFromString(String raw) {
  if (raw.isEmpty) return null;
  final parts = raw.split('_');
  if (parts.length == 1) return Locale(parts[0]);
  return Locale(parts[0], parts[1]);
}

String _languageLabelForLocale(Locale? locale) {
  if (locale == null) return 'English';
  switch (locale.toLanguageTag()) {
    case 'en':
      return 'English';
    case 'fr':
      return 'French';
    case 'es':
      return 'Spanish';
    case 'ru':
      return 'Russian';
    case 'uk':
      return 'Ukrainian';
    case 'bg':
      return 'Bulgarian';
    case 'pl':
      return 'Polish';
    case 'pt':
      return 'Portuguese';
    case 'ja':
      return 'Japanese';
    case 'zh-TW':
      return 'Taiwanese';
    case 'zh-CN':
      return 'Chinese (Mandarin)';
    case 'ko':
      return 'Korean';
    case 'ar':
      return 'Arabic';
  }
  return locale.toLanguageTag();
}

List<String> _normalizeCategories(Iterable<String> categories) {
  final seen = <String>{};
  final normalized = <String>[];
  for (final category in categories) {
    final trimmed = category.trim();
    if (trimmed.isEmpty) continue;
    final key = trimmed.toLowerCase();
    if (seen.add(key)) {
      normalized.add(trimmed);
    }
  }
  if (normalized.isEmpty) {
    normalized.add(kCategoryOptions.first);
  }
  return normalized;
}

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

final math.Random _idRandom = math.Random();

String _newEventId() {
  return '${DateTime.now().microsecondsSinceEpoch}_${_idRandom.nextInt(1 << 32)}';
}

int _stableHash(String value) {
  var hash = 0x811c9dc5;
  for (final codeUnit in value.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash;
}

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();
  static const String _channelKey = 'event_reminders';
  static const String _channelName = 'Event reminders';
  static const String _channelDescription =
      'Notifications for upcoming calendar events';

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    AwesomeNotifications().initialize(
      null,
      [
        NotificationChannel(
          channelKey: _channelKey,
          channelName: _channelName,
          channelDescription: _channelDescription,
          importance: NotificationImportance.High,
          defaultColor: const Color(0xFF3B82F6),
          ledColor: Colors.white,
        ),
      ],
    );
    await _requestPermissions();
    _initialized = true;
  }

  Future<void> _requestPermissions() async {
    final isAllowed = await AwesomeNotifications().isNotificationAllowed();
    if (!isAllowed) {
      await AwesomeNotifications().requestPermissionToSendNotifications();
    }
  }

  Future<void> rescheduleAll(Iterable<Event> events) async {
    if (!_initialized) return;
    await AwesomeNotifications().cancelAll();
    for (final event in events) {
      await scheduleEventReminder(event);
    }
  }

  Future<void> scheduleEventReminder(Event event) async {
    if (!_initialized) return;
    if (event.type == EventType.note) return;
    final scheduledAt = _reminderTime(event);
    if (scheduledAt == null) return;

    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: event.notificationId,
        channelKey: _channelKey,
        title: event.title.isEmpty ? 'Upcoming event' : event.title,
        body: _buildBody(event),
        notificationLayout: NotificationLayout.Default,
      ),
      schedule: NotificationCalendar(
        year: scheduledAt.year,
        month: scheduledAt.month,
        day: scheduledAt.day,
        hour: scheduledAt.hour,
        minute: scheduledAt.minute,
        second: scheduledAt.second,
        millisecond: 0,
        allowWhileIdle: true,
      ),
    );
  }

  Future<void> cancelEventReminder(Event event) async {
    if (!_initialized) return;
    await AwesomeNotifications().cancel(event.notificationId);
  }

  Future<void> rescheduleEventReminder(Event oldEvent, Event newEvent) async {
    if (!_initialized) return;
    await cancelEventReminder(oldEvent);
    await scheduleEventReminder(newEvent);
  }

  Future<void> showTestNotification() async {
    if (!_initialized) return;
    final scheduledAt = DateTime.now().add(const Duration(seconds: 5));
    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: _idRandom.nextInt(1 << 31),
        channelKey: _channelKey,
        title: 'Test notification',
        body: 'If you see this, notifications are working.',
        notificationLayout: NotificationLayout.Default,
      ),
      schedule: NotificationCalendar(
        year: scheduledAt.year,
        month: scheduledAt.month,
        day: scheduledAt.day,
        hour: scheduledAt.hour,
        minute: scheduledAt.minute,
        second: scheduledAt.second,
        millisecond: 0,
        allowWhileIdle: true,
      ),
    );
  }

  DateTime? _reminderTime(Event event) {
    if (event.reminder == null || event.startTime == null) return null;
    final start = DateTime(
      event.date.year,
      event.date.month,
      event.date.day,
      event.startTime!.hour,
      event.startTime!.minute,
    );
    final reminderAt = start.subtract(event.reminder!);
    if (reminderAt.isBefore(DateTime.now())) return null;
    return reminderAt;
  }

  String _buildBody(Event event) {
    if (event.startTime == null) return event.description;
    final start = DateTime(
      event.date.year,
      event.date.month,
      event.date.day,
      event.startTime!.hour,
      event.startTime!.minute,
    );
    final formatted = DateFormat('EEE, MMM d • h:mm a').format(start);
    if (event.description.trim().isNotEmpty) {
      return '${event.description.trim()}\nStarts $formatted';
    }
    return 'Starts $formatted';
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.init();
  runApp(const CalendarApp());
}

class CalendarApp extends StatefulWidget {
  const CalendarApp({super.key});

  @override
  State<CalendarApp> createState() => _CalendarAppState();
}

class _CalendarAppState extends State<CalendarApp> {
  static const String _localeStorageKey = 'app_locale';
  final ValueNotifier<Locale?> _localeNotifier = ValueNotifier<Locale?>(null);

  @override
  void initState() {
    super.initState();
    unawaited(_loadLocale());
  }

  Future<void> _loadLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_localeStorageKey);
    if (stored == null) return;
    final parsed = _localeFromString(stored);
    if (parsed == null) return;
    _localeNotifier.value = parsed;
    Intl.defaultLocale = parsed.toLanguageTag();
  }

  Future<void> _updateLocale(Locale locale) async {
    _localeNotifier.value = locale;
    Intl.defaultLocale = locale.toLanguageTag();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localeStorageKey, _localeToString(locale));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale?>(
      valueListenable: _localeNotifier,
      builder: (context, locale, _) {
        return MaterialApp(
          title: 'Calendar Planner',
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
            useMaterial3: true,
          ),
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: CalendarScreen(
            currentLocale: locale,
            onLocaleChanged: _updateLocale,
          ),
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}
// Event model and serialization
class Event {
  final String id;
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
  final int? estimatedMinutes;
  final List<String> subtasks;

  Event({
    required this.id,
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
    this.estimatedMinutes,
    this.subtasks = const [],
  });

  bool get hasTimeRange => startTime != null && endTime != null;
  int get notificationId => _stableHash(id);

  Map<String, dynamic> toMap() {
    return {
      'id': id,
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
      'estimatedMinutes': estimatedMinutes,
      'subtasks': subtasks,
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
    final rawId = map['id'];
    final id = rawId is String && rawId.trim().isNotEmpty
        ? rawId
        : _newEventId();
    final type = _eventTypeFromString(map['type']) ?? EventType.event;
    final repeat = _repeatFrequencyFromString(map['repeatFrequency']) ?? RepeatFrequency.none;
    final isCompleted = map['isCompleted'] is bool ? map['isCompleted'] as bool : _boolFromAny(map['isCompleted']);
    final estimatedMinutesRaw = map['estimatedMinutes'];
    final estimatedMinutes = estimatedMinutesRaw is num ? estimatedMinutesRaw.round() : null;
    final subtasksRaw = map['subtasks'];
    final subtasks = <String>[];
    if (subtasksRaw is List) {
      for (final entry in subtasksRaw) {
        if (entry is String && entry.trim().isNotEmpty) {
          subtasks.add(entry);
        }
      }
    }

    return Event(
      id: id,
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
      estimatedMinutes: estimatedMinutes,
      subtasks: subtasks,
    );
  }

  Event copyWith({
    String? id,
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
    int? estimatedMinutes,
    List<String>? subtasks,
  }) {
    return Event(
      id: id ?? this.id,
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
      estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
      subtasks: subtasks ?? this.subtasks,
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
  const CalendarScreen({
    super.key,
    required this.currentLocale,
    required this.onLocaleChanged,
  });

  final Locale? currentLocale;
  final ValueChanged<Locale> onLocaleChanged;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  // Calendar navigation and displayed data sets.
  DateTime _selectedDate = DateTime.now();
  DateTime _currentMonth = DateTime(DateTime.now().year, DateTime.now().month);
  final List<Event> _events = [];
  final List<NoteEntry> _notes = [];
  List<String> _categories = List<String>.from(kCategoryOptions);
  bool _showIntroCard = true;
  HomeTab _currentTab = HomeTab.calendar;
  _ScheduleView _currentScheduleView = _ScheduleView.daily;
  _WeeklyTab _currentWeeklyTab = _WeeklyTab.schedule;

  // Local persistence keys and cache handle for SharedPreferences.
  SharedPreferences? _cachedPrefs;
  static const String _eventsStorageKey = 'calendar_events';
  static const String _introCardStorageKey = 'calendar_intro_card';
  static const String _notesStorageKey = 'calendar_notes';
  static const String _categoriesStorageKey = 'calendar_categories';

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

    final storedCategories = prefs.getStringList(_categoriesStorageKey);
    final showIntroPref = prefs.getBool(_introCardStorageKey);

    if (!mounted) return;
    setState(() {
      _events
        ..clear()
        ..addAll(loadedEvents.where((event) => event.type != EventType.note));
      _notes
        ..clear()
        ..addAll(loadedNotes);
      _categories = (storedCategories != null && storedCategories.isNotEmpty)
          ? storedCategories.where((c) => c.trim().isNotEmpty).toSet().toList()
          : List<String>.from(kCategoryOptions);
      _showIntroCard = showIntroPref ?? _events.isEmpty;
    });
    unawaited(_persistEvents());
    unawaited(NotificationService.instance.rescheduleAll(_events));
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

  Future<void> _persistCategories() async {
    final prefs = await _getPrefs();
    await prefs.setStringList(_categoriesStorageKey, _categories);
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
    unawaited(NotificationService.instance.scheduleEventReminder(event));
  }

  void _handleCategoriesUpdated(List<String> updated) {
    setState(() => _categories = updated);
    unawaited(_persistCategories());
  }

  void _handleNoteAdded(NoteEntry note) {
    _upsertNote(note);
    _addCategoryIfMissing(note.category);
  }

  void _addCategoryIfMissing(String category) {
    final trimmed = category.trim();
    if (trimmed.isEmpty) return;
    final exists = _categories.any(
      (entry) => entry.toLowerCase() == trimmed.toLowerCase(),
    );
    if (exists) return;
    final updated = _normalizeCategories([..._categories, trimmed]);
    setState(() => _categories = updated);
    unawaited(_persistCategories());
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
      extendBody: true,
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
    final l10n = AppLocalizations.of(context);
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
          _buildToggleButton(l10n.daily, _ScheduleView.daily, Icons.wb_sunny_rounded),
          const SizedBox(width: 8),
          _buildToggleButton(l10n.weekly, _ScheduleView.weekly, Icons.view_week_rounded),
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
    final l10n = AppLocalizations.of(context);
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
          _buildWeeklyTabButton(l10n.schedule, _WeeklyTab.schedule, Icons.view_week_rounded),
          const SizedBox(width: 8),
          _buildWeeklyTabButton(l10n.freeTime, _WeeklyTab.freeTime, Icons.timer_outlined),
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

    final l10n = AppLocalizations.of(context);
    return _OverviewSection(
      title: l10n.freeTimeThisWeek,
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
    const lineOffset = 10.0;
    const minEventHeight = 68.0;
    final totalHours = endHour - startHour + 1;
    final timelineHeight = totalHours * hourHeight;

    final now = DateTime.now();
    final totalMinutes = (endHour - startHour + 1) * 60;
    final nowMinutes = ((now.hour - startHour) * 60) + now.minute;
    final showNowLine =
        isToday && nowMinutes >= 0 && nowMinutes <= totalMinutes && totalMinutes > 0;
    final nowTop =
        ((nowMinutes.clamp(0, totalMinutes)) / 60) * hourHeight + lineOffset;

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
                                padding: const EdgeInsets.only(top: lineOffset),
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

                final top = (clampedStart / 60) * hourHeight + lineOffset;
                final height = ((clampedEnd - clampedStart) / 60) * hourHeight;
                final visualHeight = height < minEventHeight ? minEventHeight : height;

                return Positioned(
                  top: top,
                  left: 76,
                  right: 16,
                  child: SizedBox(
                    height: visualHeight,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _showEditEventDialog(event),
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
      case EventType.timeOff:
        return Icons.beach_access_outlined;
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
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Text(
            l10n.notes,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.blueGrey[900],
            ),
          ),
          const Spacer(),
          _buildIconButton(
            Icons.folder_outlined,
            _showNotesCategoryManager,
          ),
          const SizedBox(width: 10),
          _buildIconButton(Icons.search, _showEventSearch),
        ],
      ),
    );
  }

  Future<void> _showNotesCategoryManager() async {
    final updated = await showDialog<List<String>>(
      context: context,
      builder: (_) => _CategoryManagerDialog(categories: _categories),
    );
    if (!mounted || updated == null) return;
    _handleCategoriesUpdated(_normalizeCategories(updated));
  }


  Future<void> _showEditEventDialog(Event oldEvent) async {
    final edited = await showDialog<Event>(
      context: context,
      builder: (_) => EditEventDialog(
        initial: oldEvent,
        categories: _categories,
        onCategoriesChanged: _handleCategoriesUpdated,
      ),
    );
    if (edited != null) {
      setState(() {
        final i = _events.indexOf(oldEvent);
        if (i != -1) _events[i] = edited;
      });
      unawaited(_persistEvents());
      unawaited(
        NotificationService.instance.rescheduleEventReminder(oldEvent, edited),
      );
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
              MaterialPageRoute(
                builder: (_) => ProfilePage(
                  currentLocale: widget.currentLocale,
                  onLocaleChanged: widget.onLocaleChanged,
                ),
              ),
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
    final l10n = AppLocalizations.of(context);
    final eventsAffectingTime =
        events.where((event) => event.type != EventType.note).toList();
    final hasAllDayEvent =
        eventsAffectingTime.any((event) => !event.hasTimeRange);

    return _OverviewSection(
      title: l10n.freeTime,
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
  final isTimeOff = event.type == EventType.timeOff;
  final isNote = event.type == EventType.note;
  final isCompleted = isTask && event.isCompleted;

  final IconData typeIcon;
  final Color typeColor;
  if (isTask) {
    typeIcon = Icons.check_circle_outline;
    typeColor = const Color(0xFFF1E8FF);
  } else if (isTimeOff) {
    typeIcon = Icons.beach_access_outlined;
    typeColor = const Color(0xFFEAF7F1);
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
    final l10n = AppLocalizations.of(context);
    final textScaleFactor = MediaQuery.textScaleFactorOf(context);
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    final estimatedMinHeight = 24 + 4 + (12 * textScaleFactor) + 16;
    final minHeight = math.max(52.0, estimatedMinHeight);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Container(
        padding: EdgeInsets.fromLTRB(16, 1, 16, 1 + bottomInset),
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
                        Icons.calendar_today, l10n.calendar, HomeTab.calendar),
                    _buildBottomNavItem(
                        Icons.note_outlined, l10n.notes, HomeTab.notes),
                    _buildBottomNavItem(
                        Icons.view_day_outlined, l10n.daily, HomeTab.daily),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _buildAddButton(),
            ],
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
        categories: _categories,
        onCategoriesChanged: _handleCategoriesUpdated,
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
              unawaited(NotificationService.instance.cancelEventReminder(event));
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
  return type.label;
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
    required this.categories,
    required this.onCategoriesChanged,
    required this.onEventAdded,
    super.key,
  });
  
  final DateTime selectedDate;
  final List<String> categories;
  final ValueChanged<List<String>> onCategoriesChanged;
  final ValueChanged<Event> onEventAdded;

  @override
  State<AddEventDialog> createState() => _AddEventDialogState();
}

class _AddEventDialogState extends State<AddEventDialog> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _taskHoursController = TextEditingController();
  final _taskMinutesController = TextEditingController();
  final _subtaskController = TextEditingController();
  final List<String> _subtasks = [];
  EventType _selectedType = EventType.event;
  String _selectedCategory = '';
  String _selectedReminderLabel = kReminderOptions.keys.first;
  RepeatFrequency _repeatFrequency = RepeatFrequency.none;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  bool _isAllDay = true;
  late List<String> _categories;
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    final base = widget.selectedDate;
    _selectedDate = DateTime(base.year, base.month, base.day);
    _categories = _normalizeCategories(widget.categories);
    _selectedCategory = _categories.first;
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

  Future<void> _showCategoryManager() async {
    final updated = await showDialog<List<String>>(
      context: context,
      useRootNavigator: false,
      builder: (_) => _CategoryManagerDialog(categories: _categories),
    );
    if (!mounted) return;
    if (updated == null) return;
    final normalized = _normalizeCategories(updated);
    setState(() {
      _categories = normalized;
      if (!_categories.contains(_selectedCategory)) {
        _selectedCategory = _categories.first;
      }
    });
    widget.onCategoriesChanged(_categories);
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
                          if (_selectedType == EventType.task) ...[
                            _buildTaskDetailsSection(),
                            const SizedBox(height: 20),
                          ],
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


  int? _parseEstimatedMinutes() {
    final hours = int.tryParse(_taskHoursController.text.trim());
    final minutes = int.tryParse(_taskMinutesController.text.trim());
    final total = (hours ?? 0) * 60 + (minutes ?? 0);
    return total > 0 ? total : null;
  }

  void _addSubtask() {
    final value = _subtaskController.text.trim();
    if (value.isEmpty) return;
    setState(() {
      _subtasks.add(value);
      _subtaskController.clear();
    });
  }

  void _removeSubtask(String value) {
    setState(() {
      _subtasks.remove(value);
    });
  }

  Widget _buildTaskDetailsSection() {
    final estimatedMinutes = _parseEstimatedMinutes();
    final estimatedLabel = estimatedMinutes != null
        ? _formatDuration(Duration(minutes: estimatedMinutes))
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Task details'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _taskHoursController,
                keyboardType: TextInputType.number,
                decoration: _sharedInputDecoration(
                  label: 'Hours',
                  icon: Icons.timelapse_outlined,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _taskMinutesController,
                keyboardType: TextInputType.number,
                decoration: _sharedInputDecoration(
                  label: 'Minutes',
                  icon: Icons.timer_outlined,
                ),
              ),
            ),
          ],
        ),
        if (estimatedLabel != null) ...[
          const SizedBox(height: 10),
          Text(
            'Estimated duration: $estimatedLabel',
            style: TextStyle(
              color: Colors.blueGrey.shade600,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 12),
        _sectionLabel('Subtasks'),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _subtaskController,
                decoration: _sharedInputDecoration(
                  label: 'Add subtask',
                  icon: Icons.playlist_add_check_outlined,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Add subtask',
              onPressed: _addSubtask,
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
        if (_subtasks.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _subtasks
                .map(
                  (subtask) => InputChip(
                    label: Text(subtask),
                    onDeleted: () => _removeSubtask(subtask),
                  ),
                )
                .toList(),
          ),
        ],
      ],
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
      items: _categories
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
    final manageButton = Align(
      alignment: Alignment.centerRight,
      child: TextButton.icon(
        onPressed: _showCategoryManager,
        icon: const Icon(Icons.edit_outlined, size: 18),
        label: const Text('Manage categories'),
      ),
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
              manageButton,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: reminderField),
                const SizedBox(width: spacing),
                Expanded(child: categoryField),
              ],
            ),
            const SizedBox(height: 8),
            manageButton,
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
    final estimatedMinutes =
        _selectedType == EventType.task ? _parseEstimatedMinutes() : null;
    final subtasks = _selectedType == EventType.task
        ? List<String>.from(_subtasks)
        : <String>[];

    final event = Event(
      id: _newEventId(),
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
      estimatedMinutes: estimatedMinutes,
      subtasks: subtasks,
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
    _taskHoursController.dispose();
    _taskMinutesController.dispose();
    _subtaskController.dispose();
    super.dispose();
  }
}

class EditEventDialog extends StatefulWidget {
  const EditEventDialog({
    required this.initial,
    required this.categories,
    required this.onCategoriesChanged,
    super.key,
  });
  final Event initial;
  final List<String> categories;
  final ValueChanged<List<String>> onCategoriesChanged;

  @override
  State<EditEventDialog> createState() => _EditEventDialogState();
}

class _EditEventDialogState extends State<EditEventDialog> {
  late TextEditingController _title;
  late TextEditingController _desc;
  late TextEditingController _taskHoursController;
  late TextEditingController _taskMinutesController;
  late TextEditingController _subtaskController;
  late List<String> _subtasks;
  late EventType _type;
  late String _category;
  late String _reminderLabel;
  late RepeatFrequency _repeatFrequency;
  TimeOfDay? _start;
  TimeOfDay? _end;
  late List<String> _categories;
  late DateTime _selectedDate;


  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    _title = TextEditingController(text: init.title);
    _desc = TextEditingController(text: init.description);
    _type = init.type == EventType.note ? EventType.event : init.type;
    _category = init.category;
    _categories = _normalizeCategories(widget.categories);
    if (!_categories.contains(_category)) {
      _categories.insert(0, _category);
    }
    _reminderLabel = reminderLabelFromDuration(init.reminder);
    _repeatFrequency = init.repeatFrequency;
    _start = init.startTime;
    _end = init.endTime;
    _selectedDate = DateTime(init.date.year, init.date.month, init.date.day);

    final estimatedMinutes = init.estimatedMinutes ?? 0;
    final hours = estimatedMinutes ~/ 60;
    final minutes = estimatedMinutes % 60;
    _taskHoursController =
        TextEditingController(text: hours > 0 ? hours.toString() : '');
    _taskMinutesController =
        TextEditingController(text: minutes > 0 ? minutes.toString() : '');
    _subtaskController = TextEditingController();
    _subtasks = List<String>.from(init.subtasks);
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

  Future<void> _showCategoryManager() async {
    final updated = await showDialog<List<String>>(
      context: context,
      useRootNavigator: false,
      builder: (_) => _CategoryManagerDialog(categories: _categories),
    );
    if (!mounted) return;
    if (updated == null) return;
    final normalized = _normalizeCategories(updated);
    setState(() {
      _categories = normalized;
      if (!_categories.contains(_category)) {
        _category = _categories.first;
      }
    });
    widget.onCategoriesChanged(_categories);
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
                          if (_type == EventType.task) ...[
                            const SizedBox(height: 20),
                            _buildTaskDetailsSection(),
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


  int? _parseEstimatedMinutes() {
    final hours = int.tryParse(_taskHoursController.text.trim());
    final minutes = int.tryParse(_taskMinutesController.text.trim());
    final total = (hours ?? 0) * 60 + (minutes ?? 0);
    return total > 0 ? total : null;
  }

  void _addSubtask() {
    final value = _subtaskController.text.trim();
    if (value.isEmpty) return;
    setState(() {
      _subtasks.add(value);
      _subtaskController.clear();
    });
  }

  void _removeSubtask(String value) {
    setState(() {
      _subtasks.remove(value);
    });
  }

  Widget _buildTaskDetailsSection() {
    final estimatedMinutes = _parseEstimatedMinutes();
    final estimatedLabel = estimatedMinutes != null
        ? _formatDuration(Duration(minutes: estimatedMinutes))
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Task details'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _taskHoursController,
                keyboardType: TextInputType.number,
                decoration: _sharedInputDecoration(
                  label: 'Hours',
                  icon: Icons.timelapse_outlined,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _taskMinutesController,
                keyboardType: TextInputType.number,
                decoration: _sharedInputDecoration(
                  label: 'Minutes',
                  icon: Icons.timer_outlined,
                ),
              ),
            ),
          ],
        ),
        if (estimatedLabel != null) ...[
          const SizedBox(height: 10),
          Text(
            'Estimated duration: $estimatedLabel',
            style: TextStyle(
              color: Colors.blueGrey.shade600,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 12),
        _sectionLabel('Subtasks'),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _subtaskController,
                decoration: _sharedInputDecoration(
                  label: 'Add subtask',
                  icon: Icons.playlist_add_check_outlined,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Add subtask',
              onPressed: _addSubtask,
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
        if (_subtasks.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _subtasks
                .map(
                  (subtask) => InputChip(
                    label: Text(subtask),
                    onDeleted: () => _removeSubtask(subtask),
                  ),
                )
                .toList(),
          ),
        ],
      ],
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
      items: _categories
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
    final manageButton = Align(
      alignment: Alignment.centerRight,
      child: TextButton.icon(
        onPressed: _showCategoryManager,
        icon: const Icon(Icons.edit_outlined, size: 18),
        label: const Text('Manage categories'),
      ),
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
              manageButton,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: reminderField),
                const SizedBox(width: spacing),
                Expanded(child: categoryField),
              ],
            ),
            const SizedBox(height: 8),
            manageButton,
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
    final estimatedMinutes = _type == EventType.task ? _parseEstimatedMinutes() : null;
    final subtasks = _type == EventType.task
        ? List<String>.from(_subtasks)
        : <String>[];

    final updated = Event(
      id: widget.initial.id,
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
      estimatedMinutes: estimatedMinutes,
      subtasks: subtasks,
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
    _taskHoursController.dispose();
    _taskMinutesController.dispose();
    _subtaskController.dispose();
    super.dispose();
  }
}

class _CategoryManagerDialog extends StatefulWidget {
  const _CategoryManagerDialog({required this.categories});

  final List<String> categories;

  @override
  State<_CategoryManagerDialog> createState() => _CategoryManagerDialogState();
}

class _CategoryManagerDialogState extends State<_CategoryManagerDialog> {
  late List<String> _categories;
  final _newCategoryController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _categories = List<String>.from(widget.categories);
  }

  bool _isDuplicate(String value, {String? excluding}) {
    final lower = value.toLowerCase();
    for (final category in _categories) {
      if (excluding != null && category == excluding) continue;
      if (category.toLowerCase() == lower) return true;
    }
    return false;
  }

  void _addCategory() {
    final value = _newCategoryController.text.trim();
    if (value.isEmpty) return;
    if (_isDuplicate(value)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Category already exists.')),
      );
      return;
    }
    setState(() {
      _categories.add(value);
      _newCategoryController.clear();
    });
  }

  Future<void> _editCategory(String category) async {
    final controller = TextEditingController(text: category);
    final updated = await showDialog<String>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: const Text('Edit category'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Category'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final value = updated?.trim() ?? '';
    if (value.isEmpty || value == category) return;
    if (_isDuplicate(value, excluding: category)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Category already exists.')),
      );
      return;
    }
    setState(() {
      final index = _categories.indexOf(category);
      if (index != -1) {
        _categories[index] = value;
      }
    });
  }

  Future<void> _deleteCategory(String category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: const Text('Delete category?'),
        content: Text('Delete "$category"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _categories.remove(category));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Manage categories'),
      content: SizedBox(
        width: 320,
        height: 360,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newCategoryController,
                    decoration: const InputDecoration(
                      labelText: 'New category',
                    ),
                    onSubmitted: (_) => _addCategory(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Add category',
                  onPressed: _addCategory,
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _categories.isEmpty
                  ? const Center(child: Text('No categories yet.'))
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: _categories.length,
                      separatorBuilder: (_, __) => const Divider(height: 16),
                      itemBuilder: (context, index) {
                        final category = _categories[index];
                        return Row(
                          children: [
                            Expanded(
                              child: Text(
                                category,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Edit',
                              onPressed: () => _editCategory(category),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              tooltip: 'Delete',
                              onPressed: () => _deleteCategory(category),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_categories),
          child: const Text('Done'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _newCategoryController.dispose();
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
      final dateCompare = b.date.compareTo(a.date);
      if (dateCompare != 0) {
        return dateCompare;
      }
      final aStart = a.startTime != null
          ? a.startTime!.hour * 60 + a.startTime!.minute
          : -1;
      final bStart = b.startTime != null
          ? b.startTime!.hour * 60 + b.startTime!.minute
          : -1;
      return bStart.compareTo(aStart);
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

class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key});

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

enum _FriendsTab { search, myList, pending }

class _PendingEntry {
  const _PendingEntry({required this.contact, required this.isIncoming});

  final Contact contact;
  final bool isIncoming;
}

class _FriendsPageState extends State<FriendsPage> {
  final TextEditingController _searchController = TextEditingController();
  final List<Contact> _contacts = [];
  final Set<String> _friendIds = <String>{};
  final Set<String> _pendingIncomingIds = <String>{};
  final Set<String> _pendingOutgoingIds = <String>{};

  _FriendsTab _currentTab = _FriendsTab.myList;
  bool _isLoadingContacts = false;
  String? _contactsError;

  static const String _friendsStorageKey = 'friends_friend_ids';
  static const String _pendingIncomingStorageKey = 'friends_pending_incoming_ids';
  static const String _pendingOutgoingStorageKey = 'friends_pending_outgoing_ids';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChange);
    unawaited(_loadFriendState());
    _loadContacts();
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_handleSearchChange)
      ..dispose();
    super.dispose();
  }

  void _handleSearchChange() {
    if (_currentTab != _FriendsTab.search) return;
    setState(() {});
  }

  Future<void> _loadFriendState() async {
    final prefs = await SharedPreferences.getInstance();
    final friends = prefs.getStringList(_friendsStorageKey) ?? <String>[];
    final incoming =
        prefs.getStringList(_pendingIncomingStorageKey) ?? <String>[];
    final outgoing =
        prefs.getStringList(_pendingOutgoingStorageKey) ?? <String>[];
    if (!mounted) return;
    setState(() {
      _friendIds
        ..clear()
        ..addAll(friends);
      _pendingIncomingIds
        ..clear()
        ..addAll(incoming);
      _pendingOutgoingIds
        ..clear()
        ..addAll(outgoing);
    });
  }

  Future<void> _persistFriendState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_friendsStorageKey, _friendIds.toList());
    await prefs.setStringList(
        _pendingIncomingStorageKey, _pendingIncomingIds.toList());
    await prefs.setStringList(
        _pendingOutgoingStorageKey, _pendingOutgoingIds.toList());
  }

  Future<void> _loadContacts() async {
    setState(() {
      _isLoadingContacts = true;
      _contactsError = null;
    });
    final status = await Permission.contacts.request();
    if (!status.isGranted) {
      if (!mounted) return;
      setState(() {
        _isLoadingContacts = false;
        _contactsError = 'Contacts permission denied.';
      });
      return;
    }

    try {
      final fetched = await ContactsService.getContacts(withThumbnails: false);
      final list = fetched
          .where((contact) => _contactDisplayName(contact).isNotEmpty)
          .toList();
      list.sort((a, b) => _contactDisplayName(a)
          .toLowerCase()
          .compareTo(_contactDisplayName(b).toLowerCase()));
      if (!mounted) return;
      setState(() {
        _contacts
          ..clear()
          ..addAll(list);
        _isLoadingContacts = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _contactsError = 'Unable to load contacts.';
        _isLoadingContacts = false;
      });
    }
  }

  void _selectTab(_FriendsTab tab) {
    setState(() {
      _currentTab = tab;
    });
  }

  void _acceptRequest(Contact contact) {
    final id = _contactId(contact);
    setState(() {
      _pendingIncomingIds.remove(id);
      _pendingOutgoingIds.remove(id);
      _friendIds.add(id);
    });
    unawaited(_persistFriendState());
  }

  void _rejectRequest(Contact contact) {
    final id = _contactId(contact);
    setState(() {
      _pendingIncomingIds.remove(id);
      _pendingOutgoingIds.remove(id);
    });
    unawaited(_persistFriendState());
  }

  void _sendRequest(Contact contact) {
    final id = _contactId(contact);
    if (_friendIds.contains(id) ||
        _pendingIncomingIds.contains(id) ||
        _pendingOutgoingIds.contains(id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).friendRequestAlreadyPending)),
      );
      return;
    }
    setState(() {
      _pendingOutgoingIds.add(id);
    });
    unawaited(_persistFriendState());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).friendRequestSent)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final background = Colors.white;
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        elevation: 0,
        centerTitle: true,
        title: Text(
          l10n.friends,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              tooltip: l10n.profile,
              icon: const Icon(Icons.person),
              onPressed: () {},
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _buildTabBar(l10n),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _buildTabList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(AppLocalizations l10n) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFE5E5E5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          _buildTabButton(_FriendsTab.search, l10n.search),
          _buildTabButton(_FriendsTab.myList, l10n.myList),
          _buildTabButton(_FriendsTab.pending, l10n.pending),
        ],
      ),
    );
  }

  Widget _buildTabButton(_FriendsTab tab, String label) {
    final isSelected = _currentTab == tab;
    return Expanded(
      child: InkWell(
        onTap: () => _selectTab(tab),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : const Color(0xFFE5E5E5),
            borderRadius: BorderRadius.circular(8),
            border: isSelected
                ? Border.all(color: Colors.black26)
                : Border.all(color: Colors.transparent),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.black87 : Colors.black54,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabList() {
    final l10n = AppLocalizations.of(context);
    if (_isLoadingContacts) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_contactsError != null) {
      return _buildStatusMessage(
        _contactsError!,
        action: TextButton(
          onPressed: _loadContacts,
          child: Text(l10n.tryAgain),
        ),
      );
    }

    if (_contacts.isEmpty) {
      return _buildStatusMessage(
        l10n.noContactsFound,
      );
    }

    switch (_currentTab) {
      case _FriendsTab.search:
        return _buildSearchTab();
      case _FriendsTab.myList:
        return _buildMyListTab();
      case _FriendsTab.pending:
        return _buildPendingTab();
    }
  }

  Widget _buildSearchTab() {
    final l10n = AppLocalizations.of(context);
    final query = _searchController.text.trim().toLowerCase();
    final filtered = _contacts.where((contact) {
      if (query.isEmpty) return true;
      final name = _contactDisplayName(contact).toLowerCase();
      final subtitle = _contactSubtitle(contact).toLowerCase();
      return name.contains(query) || subtitle.contains(query);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: l10n.searchContacts,
              prefixIcon: const Icon(Icons.search),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              filled: true,
              fillColor: const Color(0xFFF2F2F2),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _buildContactList(
            filtered,
            emptyMessage: l10n.noMatchingContacts,
            trailingBuilder: (contact) {
              final id = _contactId(contact);
              if (_friendIds.contains(id)) {
                return _buildStatusPill(l10n.friends);
              }
              if (_pendingIncomingIds.contains(id)) {
                return _buildStatusPill(l10n.incoming);
              }
              if (_pendingOutgoingIds.contains(id)) {
                return _buildStatusPill(l10n.requested);
              }
              return _buildActionButton(
                icon: Icons.add,
                onTap: () => _sendRequest(contact),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMyListTab() {
    final l10n = AppLocalizations.of(context);
    final friends = _contacts
        .where((contact) => _friendIds.contains(_contactId(contact)))
        .toList();
    return _buildContactList(
      friends,
      emptyMessage: l10n.noFriendsYet,
    );
  }

  Widget _buildPendingTab() {
    final l10n = AppLocalizations.of(context);
    final pending = _pendingEntries();
    if (pending.isEmpty) {
      return _buildStatusMessage(l10n.noPendingRequests);
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      itemBuilder: (context, index) {
        final entry = pending[index];
        final actions = entry.isIncoming
            ? [
                _buildActionButton(
                  icon: Icons.close,
                  onTap: () => _rejectRequest(entry.contact),
                ),
                _buildActionButton(
                  icon: Icons.check,
                  onTap: () => _acceptRequest(entry.contact),
                ),
              ]
            : [
                _buildActionButton(
                  icon: Icons.close,
                  onTap: () => _rejectRequest(entry.contact),
                ),
              ];
        final status = entry.isIncoming ? l10n.incoming : l10n.requested;
        return _buildContactRow(entry.contact, status: status, actions: actions);
      },
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemCount: pending.length,
    );
  }

  List<_PendingEntry> _pendingEntries() {
    final entries = <_PendingEntry>[];
    for (final contact in _contacts) {
      final id = _contactId(contact);
      if (_pendingIncomingIds.contains(id)) {
        entries.add(_PendingEntry(contact: contact, isIncoming: true));
      } else if (_pendingOutgoingIds.contains(id)) {
        entries.add(_PendingEntry(contact: contact, isIncoming: false));
      }
    }
    return entries;
  }

  Widget _buildContactList(
    List<Contact> contacts, {
    required String emptyMessage,
    Widget Function(Contact contact)? trailingBuilder,
  }) {
    if (contacts.isEmpty) {
      return _buildStatusMessage(emptyMessage);
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      itemBuilder: (context, index) {
        final contact = contacts[index];
        return _buildContactRow(
          contact,
          actions: trailingBuilder == null
              ? const []
              : [trailingBuilder(contact)],
        );
      },
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemCount: contacts.length,
    );
  }

  Widget _buildContactRow(
    Contact contact, {
    String? status,
    List<Widget> actions = const [],
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 16,
            backgroundColor: Color(0xFFE0E0E0),
            child: Icon(Icons.person, color: Colors.black54, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _contactDisplayName(contact),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  status ?? _contactSubtitle(contact),
                  style: TextStyle(
                    color: Colors.blueGrey[400],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (actions.isNotEmpty)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: actions,
            ),
        ],
      ),
    );
  }

  Widget _buildActionButton({required IconData icon, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          height: 28,
          width: 28,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.black26),
            borderRadius: BorderRadius.circular(6),
            color: Colors.white,
          ),
          child: Icon(icon, size: 16, color: Colors.black87),
        ),
      ),
    );
  }

  Widget _buildStatusPill(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFE5E5E5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildStatusMessage(String message, {Widget? action}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            style: TextStyle(color: Colors.blueGrey[400]),
          ),
          if (action != null) ...[
            const SizedBox(height: 8),
            action,
          ],
        ],
      ),
    );
  }

  String _contactId(Contact contact) {
    final phone = contact.phones?.isNotEmpty == true
        ? contact.phones!.first.value ?? ''
        : '';
    return contact.identifier ??
        '${contact.displayName ?? ''}-$phone';
  }

  String _contactDisplayName(Contact contact) {
    final display = contact.displayName?.trim();
    if (display != null && display.isNotEmpty) return display;
    final given = contact.givenName?.trim() ?? '';
    final family = contact.familyName?.trim() ?? '';
    return '$given $family'.trim();
  }

  String _contactSubtitle(Contact contact) {
    final phone = contact.phones?.isNotEmpty == true
        ? contact.phones!.first.value ?? ''
        : '';
    if (phone.trim().isNotEmpty) return phone.trim();
    final email = contact.emails?.isNotEmpty == true
        ? contact.emails!.first.value ?? ''
        : '';
    if (email.trim().isNotEmpty) return email.trim();
    return 'No contact info';
  }
}

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  static const String _accountUsernameKey = 'account_username';
  static const String _accountFullNameKey = 'account_full_name';
  static const String _accountEmailKey = 'account_email';
  static const String _accountPasswordKey = 'account_password';
  static const String _accountLevelKey = 'account_level';
  static const String _accountPointsKey = 'account_points';
  static const String _friendsStorageKey = 'friends_friend_ids';

  String _username = 'Charlie';
  String _fullName = 'Charlie Edmonton';
  String _email = 'charlie_ed23@gmail.com';
  String _password = '************';
  int _level = 10;
  int _points = 100;
  int _friends = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadAccountData());
  }

  Future<void> _loadAccountData() async {
    final prefs = await SharedPreferences.getInstance();
    final friends = prefs.getStringList(_friendsStorageKey) ?? <String>[];
    if (!mounted) return;
    setState(() {
      _username = prefs.getString(_accountUsernameKey) ?? _username;
      _fullName = prefs.getString(_accountFullNameKey) ?? _fullName;
      _email = prefs.getString(_accountEmailKey) ?? _email;
      _password = prefs.getString(_accountPasswordKey) ?? _password;
      _level = prefs.getInt(_accountLevelKey) ?? _level;
      _points = prefs.getInt(_accountPointsKey) ?? _points;
      _friends = friends.length;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final background = const Color(0xFFF0F3F7);
    final card = Colors.white;
    final border = Colors.blueGrey.withOpacity(0.08);
    final l10n = AppLocalizations.of(context);
    final localeTag = Localizations.localeOf(context).toLanguageTag();

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        centerTitle: true,
        title: Text(
          l10n.account,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _buildProfileCard(
                    card: card,
                    border: border,
                    accent: scheme.primary,
                    l10n: l10n,
                    localeTag: localeTag,
                  ),
                  const SizedBox(height: 16),
                  _buildSectionCard(
                    title: l10n.account,
                    card: card,
                    border: border,
                    children: [
                      _buildMenuTile(
                        icon: Icons.person,
                        iconColor: const Color(0xFF3B82F6),
                        title: l10n.personalInfo,
                        subtitle: l10n.manageInfo,
                        onTap: () => _showPlaceholder(l10n.personalInfo),
                      ),
                      _buildMenuTile(
                        icon: Icons.notifications,
                        iconColor: const Color(0xFFF59E0B),
                        title: l10n.notificationSettings,
                        subtitle: l10n.alertsReminders,
                        onTap: () => _showPlaceholder(l10n.notificationSettings),
                      ),
                      _buildMenuTile(
                        icon: Icons.notification_important_outlined,
                        iconColor: const Color(0xFFEF4444),
                        title: 'Test notification',
                        subtitle: 'Send in 5 seconds',
                        onTap: () {
                          unawaited(
                            NotificationService.instance.showTestNotification(),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Test notification scheduled.'),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildSectionCard(
                    title: l10n.preferences,
                    card: card,
                    border: border,
                    children: [
                      _buildMenuTile(
                        icon: Icons.dark_mode,
                        iconColor: const Color(0xFF111827),
                        title: l10n.darkMode,
                        subtitle: l10n.off,
                        onTap: () => _showPlaceholder(l10n.darkMode),
                      ),
                      _buildMenuTile(
                        icon: Icons.language,
                        iconColor: const Color(0xFF10B981),
                        title: l10n.language,
                        subtitle: _languageLabelForLocale(
                            Localizations.localeOf(context)),
                        onTap: () => _showPlaceholder(l10n.language),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildSectionCard(
                    title: l10n.security,
                    card: card,
                    border: border,
                    children: [
                      _buildMenuTile(
                        icon: Icons.lock,
                        iconColor: const Color(0xFF4B5563),
                        title: l10n.changePassword,
                        subtitle: l10n.updatePassword,
                        onTap: () => _showPlaceholder(l10n.changePassword),
                      ),
                      _buildMenuTile(
                        icon: Icons.shield,
                        iconColor: const Color(0xFF1F2937),
                        title: l10n.twoFactor,
                        subtitle: l10n.extraSecurity,
                        onTap: () => _showPlaceholder(l10n.twoFactor),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildActionButton(
                    label: l10n.logOut,
                    icon: Icons.power_settings_new,
                    color: const Color(0xFFEF4444),
                    onTap: () => _showPlaceholder(l10n.logOut),
                  ),
                  const SizedBox(height: 12),
                  _buildActionButton(
                    label: l10n.deleteAccount,
                    icon: Icons.delete_outline,
                    color: const Color(0xFFEF4444),
                    onTap: () => _showPlaceholder(l10n.deleteAccount),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildProfileCard({
    required Color card,
    required Color border,
    required Color accent,
    required AppLocalizations l10n,
    required String localeTag,
  }) {
    final pointsFormatted =
        NumberFormat.decimalPattern(localeTag).format(_points);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
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
          CircleAvatar(
            radius: 28,
            backgroundColor: accent.withOpacity(0.15),
            child: Icon(Icons.person, color: accent, size: 30),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _fullName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _email,
                  style: TextStyle(color: Colors.blueGrey[400], fontSize: 12),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    _buildStatChip(l10n.level, _level.toString()),
                    _buildStatChip(l10n.points, pointsFormatted),
                    _buildStatChip(l10n.friends, _friends.toString()),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () => _showPlaceholder(l10n.editProfile),
            style: ElevatedButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              l10n.editProfile,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required Color card,
    required Color border,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                title,
                style: TextStyle(
                  color: Colors.blueGrey[700],
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          ...children,
        ],
      ),
    );
  }

  Widget _buildMenuTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            Container(
              height: 36,
              width: 36,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(color: Colors.blueGrey[400], fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.blueGrey[300]),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 44,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, color: color, size: 18),
        label: Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: color.withOpacity(0.4)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          backgroundColor: Colors.white,
        ),
      ),
    );
  }

  void _showPlaceholder(String label) {
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.actionPressed(label))),
    );
  }
}

class PointsPage extends StatefulWidget {
  const PointsPage({super.key});

  @override
  State<PointsPage> createState() => _PointsPageState();
}

class _PointsPageState extends State<PointsPage> {
  static const String _accountPointsKey = 'account_points';

  int _points = 1240;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPoints());
  }

  Future<void> _loadPoints() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _points = prefs.getInt(_accountPointsKey) ?? _points;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = const Color(0xFFF1F4F9);
    final card = Colors.white;
    final border = Colors.blueGrey.withOpacity(0.08);
    final accent = scheme.primary;
    final l10n = AppLocalizations.of(context);
    final localeTag = Localizations.localeOf(context).toLanguageTag();

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          l10n.points,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  _buildPointsTotalCard(
                    card: card,
                    border: border,
                    accent: accent,
                    title: l10n.totalPoints,
                    localeTag: localeTag,
                  ),
                  const SizedBox(height: 16),
                  _buildSectionTitle(l10n.activities),
                  const SizedBox(height: 8),
                  _buildActivitiesCard(
                    card: card,
                    border: border,
                    choresLabel: l10n.chores,
                    workLabel: l10n.work,
                    freeTimeLabel: l10n.freeTime,
                    timeOffLabel: l10n.timeOff,
                  ),
                  const SizedBox(height: 16),
                  _buildSectionTitle(l10n.history),
                  const SizedBox(height: 8),
                  _buildHistoryCard(
                    card: card,
                    border: border,
                    levelUpLabel: l10n.levelUp,
                    pointsLabel: l10n.pointsWithValue,
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildPointsTotalCard({
    required Color card,
    required Color border,
    required Color accent,
    required String title,
    required String localeTag,
  }) {
    final formatted = NumberFormat.decimalPattern(localeTag).format(_points);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            height: 44,
            width: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  accent.withOpacity(0.9),
                  accent.withOpacity(0.6),
                ],
              ),
            ),
            child: const Icon(Icons.emoji_events, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Row(
                  children: List.generate(
                    5,
                    (index) => const Padding(
                      padding: EdgeInsets.only(right: 2),
                      child: Icon(Icons.star, size: 10, color: Color(0xFFCBD5F5)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Text(
            formatted,
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, color: Colors.black38),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text(
        title,
        style: TextStyle(
          color: Colors.blueGrey[700],
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildActivitiesCard({
    required Color card,
    required Color border,
    required String choresLabel,
    required String workLabel,
    required String freeTimeLabel,
    required String timeOffLabel,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildActivityRow(
            icon: Icons.check_circle,
            iconColor: const Color(0xFF3B82F6),
            label: choresLabel,
            chipLabel: '+10',
            chipColor: const Color(0xFF22C55E),
          ),
          _buildDivider(),
          _buildActivityRow(
            icon: Icons.work,
            iconColor: const Color(0xFF60A5FA),
            label: workLabel,
            chipLabel: '+20',
            chipColor: const Color(0xFFF59E0B),
          ),
          _buildDivider(),
          _buildActivityRow(
            icon: Icons.play_circle_fill,
            iconColor: const Color(0xFF22C55E),
            label: freeTimeLabel,
            chipLabel: '+1',
            chipColor: const Color(0xFFE2E8F0),
          ),
          _buildDivider(),
          _buildActivityRow(
            icon: Icons.hotel,
            iconColor: const Color(0xFF8B5CF6),
            label: timeOffLabel,
            chipLabel: '+1',
            chipColor: const Color(0xFFE2E8F0),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String chipLabel,
    required Color chipColor,
  }) {
    final isMuted = chipColor == const Color(0xFFE2E8F0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            height: 32,
            width: 32,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: chipColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              chipLabel,
              style: TextStyle(
                color: isMuted ? Colors.blueGrey[500] : Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard({
    required Color card,
    required Color border,
    required String levelUpLabel,
    required String Function(String) pointsLabel,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildHistoryRow('Nov 16', pointsLabel('+30')),
          _buildDivider(),
          _buildHistoryRow('Nov 15', pointsLabel('+20')),
          _buildDivider(),
          _buildHistoryRow(
            levelUpLabel,
            pointsLabel('+25'),
            highlight: true,
          ),
          _buildDivider(),
          _buildHistoryRow('Nov 12', pointsLabel('+20')),
          _buildDivider(),
          _buildHistoryRow('Nov 11', pointsLabel('+11')),
        ],
      ),
    );
  }

  Widget _buildHistoryRow(String label, String value, {bool highlight = false}) {
    final labelStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: highlight ? const Color(0xFF2563EB) : Colors.blueGrey[800],
    );
    final valueStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: highlight ? const Color(0xFF2563EB) : const Color(0xFF16A34A),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: highlight
          ? BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFE0F2FE),
                  Colors.white.withOpacity(0.0),
                ],
              ),
            )
          : null,
      child: Row(
        children: [
          Container(
            height: 12,
            width: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: highlight ? const Color(0xFF60A5FA) : const Color(0xFF93C5FD),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: labelStyle)),
          Text(value, style: valueStyle),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return const Divider(height: 1, indent: 16, endIndent: 16);
  }
}

class RewardsPage extends StatelessWidget {
  const RewardsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = const Color(0xFFF1F4F9);
    final card = Colors.white;
    final border = Colors.blueGrey.withOpacity(0.08);
    final accent = scheme.primary;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          l10n.rewards,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: 20,
          itemBuilder: (context, index) {
            final level = (index + 1) * 5;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildRewardRow(
                level: level,
                coins: level,
                card: card,
                border: border,
                accent: accent,
                levelShort: l10n.levelShort,
                coinsLabel: l10n.coins,
                showConnector: index != 0,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildRewardRow({
    required int level,
    required int coins,
    required Color card,
    required Color border,
    required Color accent,
    required String levelShort,
    required String coinsLabel,
    required bool showConnector,
  }) {
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 18),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                const SizedBox(width: 44),
                Text(
                  '$levelShort $level',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                const Spacer(),
                Text(
                  '$coins $coinsLabel',
                  style: TextStyle(
                    color: Colors.blueGrey[600],
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right, color: Colors.black38),
              ],
            ),
          ),
        ),
        Positioned(
          left: 0,
          top: 6,
          child: Column(
            children: [
              Container(
                height: 40,
                width: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      accent.withOpacity(0.9),
                      const Color(0xFFFBCFE8),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withOpacity(0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    '$levelShort $level',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
              if (showConnector)
                Container(
                  height: 40,
                  width: 2,
                  margin: const EdgeInsets.only(top: 6),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class LanguagePage extends StatelessWidget {
  const LanguagePage({
    super.key,
    required this.currentLocale,
    required this.onLocaleChanged,
  });

  final Locale? currentLocale;
  final ValueChanged<Locale> onLocaleChanged;

  static const List<_LanguageOption> _options = [
    _LanguageOption('English', Locale('en')),
    _LanguageOption('French', Locale('fr')),
    _LanguageOption('Spanish', Locale('es')),
    _LanguageOption('Russian', Locale('ru')),
    _LanguageOption('Ukrainian', Locale('uk')),
    _LanguageOption('Bulgarian', Locale('bg')),
    _LanguageOption('Polish', Locale('pl')),
    _LanguageOption('Portuguese', Locale('pt')),
    _LanguageOption('Japanese', Locale('ja')),
    _LanguageOption('Taiwanese', Locale('zh', 'TW')),
    _LanguageOption('Chinese (Mandarin)', Locale('zh', 'CN')),
    _LanguageOption('Korean', Locale('ko')),
    _LanguageOption('Arabic', Locale('ar')),
  ];

  @override
  Widget build(BuildContext context) {
    final background = const Color(0xFFF1F4F9);
    final card = Colors.white;
    final border = Colors.blueGrey.withOpacity(0.08);
    final selected = _localeToString(currentLocale ?? const Locale('en'));
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          l10n.language,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          decoration: BoxDecoration(
            color: card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 12,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ListView.separated(
            itemCount: _options.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, indent: 16, endIndent: 16),
            itemBuilder: (context, index) {
              final option = _options[index];
              final isSelected =
                  _localeToString(option.locale) == selected;
              return ListTile(
                title: Text(
                  option.label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                trailing: isSelected
                    ? const Icon(Icons.check_circle, color: Color(0xFF3B82F6))
                    : null,
                onTap: () {
                  onLocaleChanged(option.locale);
                  Navigator.of(context).pop();
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _LanguageOption {
  const _LanguageOption(this.label, this.locale);

  final String label;
  final Locale locale;
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({
    super.key,
    required this.currentLocale,
    required this.onLocaleChanged,
  });

  final Locale? currentLocale;
  final ValueChanged<Locale> onLocaleChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final background = const Color(0xFFF1F4F9);
    final card = Colors.white;
    final border = Colors.blueGrey.withOpacity(0.08);
    final accent = scheme.primary;
    final l10n = AppLocalizations.of(context);
    final localeTag = Localizations.localeOf(context).toLanguageTag();
    final pointsFormatted = NumberFormat.decimalPattern(localeTag).format(1240);

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
              _buildProfileHeader(
                accent: accent,
                border: border,
                levelLabel: l10n.levelLabel(10),
                levelPointsLabel:
                    l10n.levelPointsLabel(10, '$pointsFormatted ${l10n.pointsShort}'),
              ),
              const SizedBox(height: 18),

              _buildSection(
                title: l10n.profile,
                card: card,
                border: border,
                children: [
                  _ProfileOptionTile(
                    icon: Icons.person_outline,
                    label: l10n.account,
                    subtitle: l10n.manageProfile,
                    accentColor: const Color(0xFF3B82F6),
                    cardColor: card,
                    borderColor: border,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AccountPage()),
                    ),
                  ),
                  _ProfileOptionTile(
                    icon: Icons.group_outlined,
                    label: l10n.friends,
                    accentColor: const Color(0xFF3B82F6),
                    cardColor: card,
                    borderColor: border,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const FriendsPage()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              _buildSection(
                title: l10n.progress,
                card: card,
                border: border,
                children: [
                  _ProfileOptionTile(
                    icon: Icons.emoji_events_outlined,
                    label: l10n.points,
                    trailingText: '$pointsFormatted ${l10n.pointsShort}',
                    accentColor: const Color(0xFF2563EB),
                    cardColor: card,
                    borderColor: border,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const PointsPage()),
                    ),
                  ),
                  _ProfileOptionTile(
                    icon: Icons.card_giftcard_outlined,
                    label: l10n.rewards,
                    accentColor: const Color(0xFF6366F1),
                    cardColor: card,
                    borderColor: border,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const RewardsPage()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              _buildSection(
                title: l10n.preferences,
                card: card,
                border: border,
                children: [
                  _ProfileOptionTile(
                    icon: Icons.translate,
                    label: l10n.language,
                    trailingText: _languageLabelForLocale(currentLocale),
                    accentColor: const Color(0xFF38BDF8),
                    cardColor: card,
                    borderColor: border,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => LanguagePage(
                          currentLocale: currentLocale,
                          onLocaleChanged: onLocaleChanged,
                        ),
                      ),
                    ),
                  ),
                  _ProfileOptionTile(
                    icon: Icons.settings_outlined,
                    label: l10n.settings,
                    accentColor: const Color(0xFF3B82F6),
                    cardColor: card,
                    borderColor: border,
                  ),
                  _ProfileOptionTile(
                    icon: Icons.notification_important_outlined,
                    label: 'Test notification',
                    subtitle: 'Send in 5 seconds',
                    accentColor: const Color(0xFFEF4444),
                    cardColor: card,
                    borderColor: border,
                    onTap: () {
                      unawaited(
                        NotificationService.instance.showTestNotification(),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Test notification scheduled.'),
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),

              _buildSection(
                title: l10n.support,
                card: card,
                border: border,
                children: [
                  _ProfileOptionTile(
                    icon: Icons.help_outline,
                    label: l10n.help,
                    accentColor: const Color(0xFF3B82F6),
                    cardColor: card,
                    borderColor: border,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileHeader({
    required Color accent,
    required Color border,
    required String levelLabel,
    required String levelPointsLabel,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            accent.withOpacity(0.75),
            accent.withOpacity(0.35),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.workspace_premium,
                    color: Colors.white, size: 16),
                const SizedBox(width: 6),
                Text(
                  levelLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
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
                const Text(
                  'John Doe',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  levelPointsLabel,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.35),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24),
            ),
            child: CircleAvatar(
              radius: 26,
              backgroundColor: Colors.white,
              child: Icon(Icons.person, color: accent, size: 28),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required Color card,
    required Color border,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            title,
            style: TextStyle(
              color: Colors.blueGrey[700],
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 12,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                children[i],
                if (i != children.length - 1)
                  const Divider(height: 1, indent: 16, endIndent: 16),
              ],
            ],
          ),
        ),
      ],
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
    this.subtitle,
    this.trailingText,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color accentColor;
  final Color cardColor;
  final Color borderColor;
  final String? subtitle;
  final String? trailingText;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              height: 36,
              width: 36,
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: accentColor, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.blueGrey[800],
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style:
                          TextStyle(color: Colors.blueGrey[400], fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            if (trailingText != null)
              Text(
                trailingText!,
                style: TextStyle(color: Colors.blueGrey[500], fontSize: 12),
              ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right, color: Colors.blueGrey[300], size: 20),
          ],
        ),
      ),
    );
  }
}
