import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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

  const Event({
    required this.title,
    required this.description,
    required this.date,
    this.startTime,
    this.endTime,
    this.category = 'General',
  });

  bool get hasTimeRange => startTime != null && endTime != null;
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
  bool _showIntroCard = true;

  static const int _dayStartHour = 8;
  static const int _dayEndHour = 20;


  @override
  Widget build(BuildContext context) {
    final eventsForSelectedDate = _getEventsForDate(_selectedDate);
    final freeSlots = _calculateFreeTimeSlots(eventsForSelectedDate);

    return Scaffold(
       backgroundColor: const Color(0xFFF5F7FB),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            _buildMonthHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 24),
                child: Column(
                  children: [
                    _buildCalendarCard(eventsForSelectedDate),
                    _buildOverviewRow(eventsForSelectedDate, freeSlots),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddEventDialog,
        backgroundColor: Colors.blue[600],
        child: const Icon(Icons.add, color: Colors.white),
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
           _buildIconButton(Icons.search, () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Search coming soon!')),
            );
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

  Widget _buildOverviewRow(List<Event> events, List<_TimeSlot> freeSlots) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _buildDateOverview(events)),
          const SizedBox(width: 16),
          Expanded(child: _buildFreeTimeOverview(freeSlots, events)),
        ],
      ),
    );
  }

  Widget _buildDateOverview(List<Event> events) {
    return _OverviewSection(
      title: 'Date',
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
    return _OverviewSection(
      title: 'Free time',
      onShare: _shareFreeTime,
      child: freeSlots.isEmpty
          ? _buildFreeTimeEmptyMessage(events)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: freeSlots
                  .map(
                    (slot) => Padding(
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
                    ),
                  )
                  .toList(),
            ),
    );
  }

  Widget _buildFreeTimeEmptyMessage(List<Event> events) {
    if (events.isEmpty) {
      return const _EmptyOverviewMessage(
        message: 'Add time blocks to calculate your free time.',
      );
    }
    return const _EmptyOverviewMessage(
      message: 'No free time detected. Try adjusting your schedule.',
    );
  }

  Widget _buildEventTile(Event event) {
    final categoryColor = _getCategoryColor(event.category);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blueGrey[50]!),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
                Text(
                  event.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  event.hasTimeRange
                      ? '${_formatTimeOfDay(event.startTime!)} - ${_formatTimeOfDay(event.endTime!)}'
                      : 'All day',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.blueGrey[500],
                  ),
                ),
          Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: categoryColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  event.hasTimeRange
                      ? '${_formatTimeOfDay(event.startTime!)} - ${_formatTimeOfDay(event.endTime!)}'
                      : 'All day',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.blueGrey[500],
                  ),
                ),
                if (event.description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    event.description,
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: categoryColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    event.category,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: categoryColor.withOpacity(0.9),
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _confirmDelete(event),
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavigationBar() {
    return BottomAppBar(
      shape: const CircularNotchedRectangle(),
      notchMargin: 10,
      color: Colors.white,
      child: SizedBox(
        height: 64,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildBottomNavItem(Icons.calendar_today, 'Calendar', true),
            _buildBottomNavItem(Icons.note_outlined, 'Notes', false),
            const SizedBox(width: 48),
            _buildBottomNavItem(Icons.view_day_outlined, 'Daily', false),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNavItem(IconData icon, String label, bool isActive) {
    final color = isActive ? Colors.blue[600] : Colors.blueGrey[400];
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: color),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }

  void _shareDaySchedule() {
    final events = _getEventsForDate(_selectedDate);
    final formattedDate = DateFormat('EEEE, MMMM d').format(_selectedDate);

    final summary = events.isEmpty
        ? 'No tasks scheduled for $formattedDate.'
        : 'Tasks for $formattedDate:\n${events.map((e) => '- ${e.title} (${e.hasTimeRange ? '${_formatTimeOfDay(e.startTime!)} - ${_formatTimeOfDay(e.endTime!)}' : 'All day'})').join('\n')}';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(summary)),
    );
  }

  void _shareFreeTime() {
    final freeSlots = _calculateFreeTimeSlots(_getEventsForDate(_selectedDate));
    final formattedDate = DateFormat('EEEE, MMMM d').format(_selectedDate);

    final summary = freeSlots.isEmpty
        ? 'No free time available on $formattedDate.'
        : 'Free time on $formattedDate:\n${freeSlots.map((slot) => '- ${_formatTime(slot.start)} to ${_formatTime(slot.end)}').join('\n')}';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(summary)),
    );
  }

  List<Event> _getEventsForDate(DateTime date) {
    return _events
        .where((event) => _isSameDay(event.date, date))
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

    final scheduled = events
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
          setState(() {
            _events.add(event);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Event added successfully!')),
          );
        },
      ),
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
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Event deleted')), 
              );
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.redAccent),
            ),          ),
        ],
      ),
    );
  }
}

class _OverviewSection extends StatelessWidget {
  const _OverviewSection({
    required this.title,
    required this.child,
    required this.onShare,
  });

  final String title;
  final Widget child;
  final VoidCallback onShare;

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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
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
  String _selectedCategory = 'General';
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;

  final List<String> _categories = const [
    'General',
    'Work',
    'Personal',
    'Health',
    'Education',
    'Travel',
    'Entertainment',
  ];

  @override
  Widget build(BuildContext context) {
      final formattedDate = DateFormat('EEEE, MMMM d').format(widget.selectedDate);

    return AlertDialog(
      title: const Text('Add Event'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Event Title *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.title),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description (Optional)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.description_outlined),
              ),
              minLines: 1,
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedCategory,
              decoration: const InputDecoration(
                labelText: 'Category',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.category_outlined),
              ),
              items: _categories
                  .map(
                    (category) => DropdownMenuItem<String>(
                      value: category,
                      child: Text(category),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _selectedCategory = value ?? 'General'),
            ),
            const SizedBox(height: 16),
            _buildTimePickerTile(
              label: 'Start time',
              time: _startTime,
              onTap: () => _pickTime(isStart: true),
            ),
            const SizedBox(height: 12),
            _buildTimePickerTile(
              label: 'End time',
              time: _endTime,
              onTap: () => _pickTime(isStart: false),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_outlined, color: Colors.blue),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Date: $formattedDate',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saveEvent,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue[600],
            foregroundColor: Colors.white,
          ),
          child: const Text('Add Event'),
        ),
      ],
    );
  }

    Widget _buildTimePickerTile({
    required String label,
    required TimeOfDay? time,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blueGrey[100]!),
        ),
        child: Row(
          children: [
            Icon(Icons.schedule_outlined, color: Colors.blueGrey[400]),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                time == null ? 'Select $label' : time.format(context),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: time == null ? Colors.blueGrey[300] : Colors.blueGrey[700],
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
    final initialTime = isStart
        ? (_startTime ?? const TimeOfDay(hour: 9, minute: 0))
        : (_endTime ?? const TimeOfDay(hour: 10, minute: 0));
    final selected = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );
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
              const SnackBar(content: Text('End time must be after the start time.')),
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
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an event title.')),
      );
      return;
    }

    if (_endTime != null && _startTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please choose a start time before the end time.')),
      );
      return;
    }

    final event = Event(
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      date: widget.selectedDate,
      startTime: _startTime,
      endTime: _endTime,
      category: _selectedCategory,
    );

    widget.onEventAdded(event);
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }
}