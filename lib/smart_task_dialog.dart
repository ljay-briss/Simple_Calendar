part of 'main.dart';

// ── AddSmartTaskDialog ────────────────────────────────────────────────────────
//
// Multi-step wizard for creating a smart-split task.
// Steps:
//   0 – Basics   : title, category
//   1 – Timeline : due date, total work duration
//   2 – Schedule : type + config
//   3 – Review   : generated session list (editable times)

class AddSmartTaskDialog extends StatefulWidget {
  const AddSmartTaskDialog({
    super.key,
    required this.selectedDate,
    required this.categories,
    required this.existingEvents,
    required this.dayStartHour,
    required this.dayEndHour,
    required this.onTaskCreated,
  });

  final DateTime selectedDate;
  final List<String> categories;
  final List<Event> existingEvents;
  final int dayStartHour;
  final int dayEndHour;
  final void Function(Event parent, List<Event> sessions) onTaskCreated;

  @override
  State<AddSmartTaskDialog> createState() => _AddSmartTaskDialogState();
}

class _AddSmartTaskDialogState extends State<AddSmartTaskDialog> {
  int _step = 0;

  // Step 0
  final _titleCtrl = TextEditingController();
  late String _category;

  // Step 1
  late DateTime _dueDate;
  int _totalHours = 1;
  int _totalMinutes = 0;

  // Step 2
  WorkScheduleType _scheduleType = WorkScheduleType.evenDays;
  int _workDaysCount = 5;

  // Step 3 – generated
  Event? _parentEvent;
  List<Event> _sessions = [];

  // Custom schedule (day picker)
  final Set<DateTime> _customSelectedDays = {};
  // per-day duration overrides for custom mode (day key → minutes)
  final Map<String, int> _customDurations = {};

  int get _totalWorkMinutes => _totalHours * 60 + _totalMinutes;

  // ── lifecycle ───────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _category =
        widget.categories.isNotEmpty ? widget.categories.first : 'General';
    _dueDate = widget.selectedDate.isAfter(DateTime.now())
        ? widget.selectedDate.add(const Duration(days: 7))
        : DateTime.now().add(const Duration(days: 14));
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  // ── navigation ──────────────────────────────────────────────────────────────

  void _next() {
    if (_step == 0 && _titleCtrl.text.trim().isEmpty) {
      _snack('Please enter a title.');
      return;
    }
    if (_step == 1 && _totalWorkMinutes == 0) {
      _snack('Please enter a total work duration.');
      return;
    }
    if (_step == 2) {
      if (_scheduleType == WorkScheduleType.custom &&
          _customSelectedDays.isEmpty) {
        _snack('Please select at least one day.');
        return;
      }
      _buildPreview();
    }
    setState(() => _step++);
  }

  void _back() => setState(() => _step--);

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── scheduling ──────────────────────────────────────────────────────────────

  void _buildPreview() {
    final parentId = _newEventId();
    _parentEvent = Event(
      id: parentId,
      title: _titleCtrl.text.trim(),
      description: '',
      date: _dueDate,
      category: _category,
      type: EventType.task,
      isSmartTask: true,
      estimatedMinutes: _totalWorkMinutes,
      workScheduleType: _scheduleType.name,
      workDaysCount: _workDaysCount,
    );
    _sessions = _computeSessions(_parentEvent!);
  }

  List<Event> _computeSessions(Event parent) {
    final totalMinutes = _totalWorkMinutes;
    final dueDate =
        DateTime(parent.date.year, parent.date.month, parent.date.day);

    final now = DateTime.now();
    final todayNorm = DateTime(now.year, now.month, now.day);
    final twoWeeksBefore = dueDate.subtract(const Duration(days: 14));
    final startDate =
        todayNorm.isAfter(twoWeeksBefore) ? todayNorm : twoWeeksBefore;

    final availableDays = <DateTime>[];
    var cursor = startDate;
    while (!cursor.isAfter(dueDate)) {
      availableDays.add(cursor);
      cursor = cursor.add(const Duration(days: 1));
    }
    if (availableDays.isEmpty) return [];

    List<DateTime> selectedDays;
    List<int> perDayMinutes;

    switch (_scheduleType) {
      case WorkScheduleType.evenDays:
        final n = _workDaysCount.clamp(1, availableDays.length);
        selectedDays = _CalendarScreenState._pickEvenIntervalDays(availableDays, n);
        final m = (totalMinutes / selectedDays.length).ceil();
        perDayMinutes = List.filled(selectedDays.length, m);

      case WorkScheduleType.timesPerWeek:
        selectedDays = _CalendarScreenState._pickTimesPerWeekDays(
            availableDays, _workDaysCount.clamp(1, 7));
        final m = selectedDays.isNotEmpty
            ? (totalMinutes / selectedDays.length).ceil()
            : totalMinutes;
        perDayMinutes = List.filled(selectedDays.length, m);

      case WorkScheduleType.everyday:
        const minMin = 30;
        final needed = (totalMinutes / minMin).ceil();
        final n = needed.clamp(1, availableDays.length);
        selectedDays = availableDays.take(n).toList();
        final m =
            (totalMinutes / selectedDays.length).ceil().clamp(minMin, totalMinutes);
        perDayMinutes = List.filled(selectedDays.length, m);

      case WorkScheduleType.custom:
        final sorted = _customSelectedDays.toList()..sort();
        selectedDays = sorted;
        perDayMinutes = sorted.map((d) {
          final key = '${d.year}-${d.month}-${d.day}';
          return _customDurations[key] ?? (totalMinutes ~/ sorted.length).clamp(1, totalMinutes);
        }).toList();
    }

    final sessions = <Event>[];
    final scheduledByDay = <String, List<Event>>{};

    for (int i = 0; i < selectedDays.length; i++) {
      final day = selectedDays[i];
      final mins = perDayMinutes[i];
      final dayKey = '${day.year}-${day.month}-${day.day}';

      final dayExisting = widget.existingEvents
          .where((e) =>
              e.parentTaskId == null &&
              e.type != EventType.note &&
              e.date.year == day.year &&
              e.date.month == day.month &&
              e.date.day == day.day &&
              e.repeatFrequency == RepeatFrequency.none)
          .toList();
      final alreadyPlaced = scheduledByDay[dayKey] ?? [];

      final slotStart =
          _findSlot(day, [...dayExisting, ...alreadyPlaced], mins);
      final startTOD =
          slotStart ?? TimeOfDay(hour: widget.dayStartHour, minute: 0);
      final endMin = startTOD.hour * 60 + startTOD.minute + mins;
      final endTOD =
          TimeOfDay(hour: (endMin ~/ 60).clamp(0, 23), minute: endMin % 60);

      final session = Event(
        id: _newEventId(),
        title: parent.title,
        description: '',
        date: day,
        startTime: startTOD,
        endTime: endTOD,
        category: parent.category,
        type: EventType.task,
        parentTaskId: parent.id,
        estimatedMinutes: mins,
        workScheduleType: parent.workScheduleType,
      );
      sessions.add(session);
      scheduledByDay.putIfAbsent(dayKey, () => []).add(session);
    }
    return sessions;
  }

  TimeOfDay? _findSlot(
      DateTime day, List<Event> existing, int neededMinutes) {
    final dayStart =
        DateTime(day.year, day.month, day.day, widget.dayStartHour);
    final dayEnd =
        DateTime(day.year, day.month, day.day, widget.dayEndHour);
    const bufferMin = 30;

    final timed = existing
        .where((e) => e.startTime != null && e.endTime != null)
        .map((e) => (
              start: DateTime(day.year, day.month, day.day,
                  e.startTime!.hour, e.startTime!.minute),
              end: DateTime(day.year, day.month, day.day,
                  e.endTime!.hour, e.endTime!.minute),
            ))
        .where((s) => s.end.isAfter(s.start))
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    // Merge overlapping blocked slots.
    final merged = <({DateTime start, DateTime end})>[];
    for (final s in timed) {
      if (merged.isEmpty || s.start.isAfter(merged.last.end)) {
        merged.add(s);
      } else {
        merged[merged.length - 1] = (
          start: merged.last.start,
          end: s.end.isAfter(merged.last.end) ? s.end : merged.last.end,
        );
      }
    }

    var cursor = dayStart;
    for (final blocked in merged) {
      final gapEnd =
          blocked.start.subtract(const Duration(minutes: bufferMin));
      if (gapEnd.isAfter(cursor) &&
          gapEnd.difference(cursor).inMinutes >= neededMinutes) {
        return TimeOfDay(hour: cursor.hour, minute: cursor.minute);
      }
      final next = blocked.end.add(const Duration(minutes: bufferMin));
      if (next.isAfter(cursor)) cursor = next;
    }
    if (cursor.isBefore(dayEnd) &&
        dayEnd.difference(cursor).inMinutes >= neededMinutes) {
      return TimeOfDay(hour: cursor.hour, minute: cursor.minute);
    }
    return null;
  }

  // ── save ────────────────────────────────────────────────────────────────────

  void _save() {
    if (_parentEvent == null || _sessions.isEmpty) return;
    widget.onTaskCreated(_parentEvent!, _sessions);
    Navigator.of(context).pop();
  }

  // ── helpers ─────────────────────────────────────────────────────────────────

  String _fmtTOD(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    final p = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $p';
  }

  String _fmtDate(DateTime d) => DateFormat('EEE, MMM d').format(d);

  String _fmtDuration(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h > 0 && m > 0) return '${h}h ${m}m';
    if (h > 0) return '${h}h';
    return '${m}m';
  }

  // ── build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
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
                // Header
                _header(),
                // Step indicator dots
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _stepDots(),
                ),
                Divider(color: Colors.blueGrey.shade100, height: 24),
                // Content
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                    child: _stepContent(),
                  ),
                ),
                // Navigation buttons
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: _navRow(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── header ──────────────────────────────────────────────────────────────────

  Widget _header() {
    const titles = ['New Smart Task', 'Timeline', 'Work Schedule', 'Review'];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.deepPurple.shade50,
        border: Border(
            bottom: BorderSide(color: Colors.blueGrey.shade100)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.deepPurple.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.auto_awesome_outlined,
                color: Colors.deepPurple.shade700, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              titles[_step],
              style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 18),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  // ── step dots ───────────────────────────────────────────────────────────────

  Widget _stepDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (i) {
        final active = i == _step;
        final done = i < _step;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: done
                ? Colors.deepPurple.shade300
                : active
                    ? Colors.deepPurple
                    : Colors.blueGrey.shade200,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }

  // ── step content ────────────────────────────────────────────────────────────

  Widget _stepContent() {
    switch (_step) {
      case 0:
        return _step0Basics();
      case 1:
        return _step1Timeline();
      case 2:
        return _step2Schedule();
      case 3:
        return _step3Review();
      default:
        return const SizedBox.shrink();
    }
  }

  // ── Step 0: Basics ──────────────────────────────────────────────────────────

  Widget _step0Basics() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        _sectionLabel('Task title'),
        const SizedBox(height: 8),
        TextField(
          controller: _titleCtrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: _sharedInputDecoration(
            label: 'e.g. Essay for English class',
            icon: Icons.title,
          ),
        ),
        const SizedBox(height: 16),
        _sectionLabel('Category'),
        const SizedBox(height: 8),
        _categoryPicker(),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _categoryPicker() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: widget.categories.map((cat) {
        final selected = cat == _category;
        return GestureDetector(
          onTap: () => setState(() => _category = cat),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? Colors.deepPurple.shade600
                  : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected
                    ? Colors.deepPurple.shade600
                    : Colors.blueGrey.shade200,
              ),
            ),
            child: Text(
              cat,
              style: TextStyle(
                color:
                    selected ? Colors.white : Colors.blueGrey.shade700,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Step 1: Timeline ────────────────────────────────────────────────────────

  Widget _step1Timeline() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        _sectionLabel('Due date'),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _pickDueDate,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F8FA),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blueGrey.shade100),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_today_outlined,
                    color: Colors.blueGrey[400], size: 18),
                const SizedBox(width: 10),
                Text(
                  _fmtDate(_dueDate),
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 15),
                ),
                const Spacer(),
                Icon(Icons.edit_outlined,
                    size: 16, color: Colors.blueGrey[400]),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _sectionLabel('Total work time'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _numberField(
                label: 'Hours',
                icon: Icons.timelapse_outlined,
                value: _totalHours,
                min: 0,
                max: 99,
                onChanged: (v) => setState(() => _totalHours = v),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _numberField(
                label: 'Minutes',
                icon: Icons.timer_outlined,
                value: _totalMinutes,
                min: 0,
                max: 59,
                onChanged: (v) => setState(() => _totalMinutes = v),
              ),
            ),
          ],
        ),
        if (_totalWorkMinutes > 0) ...[
          const SizedBox(height: 10),
          _infoBox(Icons.info_outline,
              'Total: ${_fmtDuration(_totalWorkMinutes)}'),
        ],
        const SizedBox(height: 16),
        // Show window info
        _infoBox(
          Icons.schedule_outlined,
          'Work will be split starting ${_dueDate.difference(DateTime.now()).inDays > 14 ? '2 weeks before' : 'today'} and ending on the due date.',
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Widget _numberField({
    required String label,
    required IconData icon,
    required int value,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
  }) {
    final ctrl = TextEditingController(text: value.toString());
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      decoration: _sharedInputDecoration(label: label, icon: icon),
      onChanged: (s) {
        final v = int.tryParse(s);
        if (v != null) onChanged(v.clamp(min, max));
      },
    );
  }

  // ── Step 2: Schedule ────────────────────────────────────────────────────────

  Widget _step2Schedule() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        _sectionLabel('How do you want to spread the work?'),
        const SizedBox(height: 12),
        _scheduleOption(
          type: WorkScheduleType.evenDays,
          icon: Icons.calendar_view_week_outlined,
          title: 'Over X days',
          subtitle: 'Choose how many days total',
        ),
        _scheduleOption(
          type: WorkScheduleType.timesPerWeek,
          icon: Icons.repeat_outlined,
          title: 'X times per week',
          subtitle: 'App picks the earliest available days each week',
        ),
        _scheduleOption(
          type: WorkScheduleType.everyday,
          icon: Icons.calendar_today_outlined,
          title: 'Every day',
          subtitle: 'Minimum 30 min/session, as many days as needed',
        ),
        _scheduleOption(
          type: WorkScheduleType.custom,
          icon: Icons.tune_outlined,
          title: 'Custom',
          subtitle: 'Pick specific days yourself',
        ),
        const SizedBox(height: 12),
        // Config area per type
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _scheduleConfig(),
        ),
        const SizedBox(height: 4),
        if (_totalWorkMinutes > 0) _sessionPreviewText(),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _scheduleOption({
    required WorkScheduleType type,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final selected = _scheduleType == type;
    return GestureDetector(
      onTap: () => setState(() => _scheduleType = type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? Colors.deepPurple.shade50 : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? Colors.deepPurple.shade300
                : Colors.blueGrey.shade100,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                color: selected
                    ? Colors.deepPurple.shade600
                    : Colors.blueGrey[400],
                size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: selected
                              ? Colors.deepPurple.shade800
                              : Colors.blueGrey[800])),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 12, color: Colors.blueGrey[500])),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle,
                  color: Colors.deepPurple.shade600, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _scheduleConfig() {
    switch (_scheduleType) {
      case WorkScheduleType.evenDays:
        return _intSliderConfig(
          key: const ValueKey('evenDays'),
          label: 'Number of days',
          value: _workDaysCount,
          min: 1,
          max: 14,
          onChanged: (v) => setState(() => _workDaysCount = v),
        );
      case WorkScheduleType.timesPerWeek:
        return _intSliderConfig(
          key: const ValueKey('timesPerWeek'),
          label: 'Times per week',
          value: _workDaysCount,
          min: 1,
          max: 7,
          onChanged: (v) => setState(() => _workDaysCount = v),
        );
      case WorkScheduleType.everyday:
        return _infoBox(
          Icons.info_outline,
          'The app will schedule 30-min sessions every day until all '
          '${_fmtDuration(_totalWorkMinutes)} of work is covered.',
          key: const ValueKey('everyday'),
        );
      case WorkScheduleType.custom:
        return _customDayPicker(key: const ValueKey('custom'));
    }
  }

  Widget _intSliderConfig({
    required Key key,
    required String label,
    required int value,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
  }) {
    return Container(
      key: key,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.blueGrey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.shade50,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('$value',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Colors.deepPurple.shade700,
                        fontSize: 16)),
              ),
            ],
          ),
          Slider(
            value: value.toDouble(),
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: max - min,
            activeColor: Colors.deepPurple,
            onChanged: (v) => onChanged(v.round()),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$min', style: TextStyle(color: Colors.blueGrey[400], fontSize: 12)),
              Text('$max', style: TextStyle(color: Colors.blueGrey[400], fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _customDayPicker({required Key key}) {
    final now = DateTime.now();
    final todayNorm = DateTime(now.year, now.month, now.day);
    final twoWeeksBefore =
        DateTime(_dueDate.year, _dueDate.month, _dueDate.day)
            .subtract(const Duration(days: 14));
    final startDate =
        todayNorm.isAfter(twoWeeksBefore) ? todayNorm : twoWeeksBefore;
    final endDate =
        DateTime(_dueDate.year, _dueDate.month, _dueDate.day);

    final days = <DateTime>[];
    var d = startDate;
    while (!d.isAfter(endDate)) {
      days.add(d);
      d = d.add(const Duration(days: 1));
    }

    return Container(
      key: key,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.blueGrey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Tap days to select them',
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.blueGrey[700])),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: days.map((day) {
              final selected = _customSelectedDays.contains(day);
              final label = DateFormat('M/d').format(day);
              return GestureDetector(
                onTap: () => setState(() {
                  if (selected) {
                    _customSelectedDays.remove(day);
                  } else {
                    _customSelectedDays.add(day);
                  }
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.deepPurple.shade600
                        : Colors.blueGrey.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? Colors.white
                          : Colors.blueGrey.shade600,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          if (_customSelectedDays.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              '${_customSelectedDays.length} day${_customSelectedDays.length == 1 ? '' : 's'} selected  ·  '
              '~${_fmtDuration((_totalWorkMinutes / _customSelectedDays.length).ceil())} per session',
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.deepPurple.shade700,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sessionPreviewText() {
    final daysAvail = _dueDate
        .difference(DateTime.now())
        .inDays
        .clamp(1, 14);

    String preview;
    switch (_scheduleType) {
      case WorkScheduleType.evenDays:
        final n = _workDaysCount;
        final m = (_totalWorkMinutes / n).ceil();
        preview =
            '$n session${n == 1 ? '' : 's'} · ${_fmtDuration(m)} each';
      case WorkScheduleType.timesPerWeek:
        final weeks = (daysAvail / 7).ceil().clamp(1, 2);
        final total = _workDaysCount * weeks;
        final m = (_totalWorkMinutes / total).ceil();
        preview =
            '$total session${total == 1 ? '' : 's'} · ${_fmtDuration(m)} each';
      case WorkScheduleType.everyday:
        final n = (_totalWorkMinutes / 30).ceil();
        preview = '$n day${n == 1 ? '' : 's'} of 30 min sessions';
      case WorkScheduleType.custom:
        if (_customSelectedDays.isEmpty) {
          preview = 'No days selected';
        } else {
          final m =
              (_totalWorkMinutes / _customSelectedDays.length).ceil();
          preview =
              '${_customSelectedDays.length} session${_customSelectedDays.length == 1 ? '' : 's'} · ~${_fmtDuration(m)} each';
        }
    }

    return _infoBox(Icons.auto_awesome_outlined, preview);
  }

  // ── Step 3: Review ──────────────────────────────────────────────────────────

  Widget _step3Review() {
    if (_sessions.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
            child: Text('No sessions could be scheduled.\n'
                'Try adjusting the due date or schedule type.',
                textAlign: TextAlign.center)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        _infoBox(
          Icons.check_circle_outline,
          '${_sessions.length} work session${_sessions.length == 1 ? '' : 's'} scheduled for "${_titleCtrl.text.trim()}". '
          'You can edit the time of any session after saving.',
        ),
        const SizedBox(height: 12),
        ..._sessions.asMap().entries.map((entry) {
          final i = entry.key;
          final s = entry.value;
          final mins = s.estimatedMinutes ?? 0;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blueGrey.shade100),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text('${i + 1}',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                            color: Colors.deepPurple.shade600)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_fmtDate(s.date),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 13)),
                      Text(
                        '${_fmtTOD(s.startTime!)} – ${_fmtTOD(s.endTime!)} · ${_fmtDuration(mins)}',
                        style: TextStyle(
                            fontSize: 12, color: Colors.blueGrey[500]),
                      ),
                    ],
                  ),
                ),
                // Allow tapping to change time
                IconButton(
                  icon: Icon(Icons.edit_outlined,
                      size: 16, color: Colors.blueGrey[400]),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _editSessionTime(i),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 8),
        _infoBox(
          Icons.info_outline,
          'Due date: ${_fmtDate(_dueDate)}  ·  '
          'Total: ${_fmtDuration(_totalWorkMinutes)}',
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Future<void> _editSessionTime(int index) async {
    final session = _sessions[index];
    final picked = await showTimePicker(
      context: context,
      initialTime: session.startTime ?? TimeOfDay(hour: widget.dayStartHour, minute: 0),
    );
    if (picked == null) return;
    final mins = session.estimatedMinutes ?? 30;
    final endMin = picked.hour * 60 + picked.minute + mins;
    final newEnd = TimeOfDay(
        hour: (endMin ~/ 60).clamp(0, 23), minute: endMin % 60);
    setState(() {
      _sessions[index] = session.copyWith(startTime: picked, endTime: newEnd);
    });
  }

  // ── nav row ─────────────────────────────────────────────────────────────────

  Widget _navRow() {
    final isFirst = _step == 0;
    final isLast = _step == 3;
    return Row(
      children: [
        if (!isFirst) ...[
          TextButton.icon(
            onPressed: _back,
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 14),
            label: const Text('Back'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.blueGrey[600],
            ),
          ),
        ],
        const Spacer(),
        FilledButton.icon(
          onPressed: isLast ? _save : _next,
          icon: Icon(isLast ? Icons.check_rounded : Icons.arrow_forward_ios_rounded,
              size: 14),
          label: Text(isLast ? 'Save Task' : 'Next'),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.deepPurple,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
        ),
      ],
    );
  }

  // ── shared small widgets ─────────────────────────────────────────────────────

  Widget _infoBox(IconData icon, String text, {Key? key}) {
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.deepPurple.shade50,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.deepPurple.shade400),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.deepPurple.shade700,
                  fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

}
