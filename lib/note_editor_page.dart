part of 'main.dart';


class _NoteLineData {
  _NoteLineData({
    required String text,
    this.isChecklist = false,
    this.isChecked = false,
  })  : controller = TextEditingController(text: text),
        focusNode = FocusNode();

  final TextEditingController controller;
  final FocusNode focusNode;
  bool isChecklist;
  bool isChecked;

  void dispose() {
    controller.dispose();
    focusNode.dispose();
  }
}

/// A snapshot of the entire note editor state, used for undo/redo.
class _NoteSnapshot {
  const _NoteSnapshot({required this.title, required this.lines});
  final String title;
  final List<_SnapshotLine> lines;
}

class _SnapshotLine {
  const _SnapshotLine({
    required this.text,
    required this.isChecklist,
    required this.isChecked,
  });
  final String text;
  final bool isChecklist;
  final bool isChecked;
}


class NoteEditorPage extends StatefulWidget {
  final String category;
  final NoteEntry? existing;

  const NoteEditorPage({
    super.key,
    required this.category,
    required this.existing,
  });

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage> {
  late final TextEditingController _title;
  final List<_NoteLineData> _lines = [];
  int? _activeLineIndex;
  bool _suppressTextListener = false;
  bool _dirty = false;

  // ── Undo / Redo ──────────────────────────────────────────────────────────
  final List<_NoteSnapshot> _undoStack = [];
  final List<_NoteSnapshot> _redoStack = [];

  /// Snapshot captured the moment the user begins a typing session.
  _NoteSnapshot? _preTypingSnapshot;
  bool _isInTypingSession = false;
  Timer? _sessionEndTimer;

  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.existing?.title ?? '');
    _title.addListener(_onTitleChanged);
    _populateLinesFromDescription(widget.existing?.description ?? '');
  }

  // ── Undo / Redo helpers ──────────────────────────────────────────────────

  _NoteSnapshot _captureSnapshot() {
    return _NoteSnapshot(
      title: _title.text,
      lines: _lines
          .map((l) => _SnapshotLine(
                text: l.controller.text,
                isChecklist: l.isChecklist,
                isChecked: l.isChecked,
              ))
          .toList(),
    );
  }

  bool _snapshotsEqual(_NoteSnapshot a, _NoteSnapshot b) {
    if (a.title != b.title) return false;
    if (a.lines.length != b.lines.length) return false;
    for (var i = 0; i < a.lines.length; i++) {
      if (a.lines[i].text != b.lines[i].text) return false;
      if (a.lines[i].isChecklist != b.lines[i].isChecklist) return false;
      if (a.lines[i].isChecked != b.lines[i].isChecked) return false;
    }
    return true;
  }

  /// Push [snapshot] onto the undo stack and clear the redo stack.
  /// Skips if [snapshot] is identical to the current top.
  void _pushToUndo(_NoteSnapshot snapshot) {
    if (_undoStack.isNotEmpty && _snapshotsEqual(_undoStack.last, snapshot)) {
      return;
    }
    _undoStack.add(snapshot);
    if (_undoStack.length > 100) _undoStack.removeAt(0);
    _redoStack.clear();
    if (mounted) setState(() {});
  }

  /// Called from text-change listeners (normal typing — no structural change).
  void _onTypingChange() {
    if (!_isInTypingSession) {
      // Remember state before the typing session began.
      _preTypingSnapshot = _captureSnapshot();
      _isInTypingSession = true;
    }
    _sessionEndTimer?.cancel();
    _sessionEndTimer =
        Timer(const Duration(milliseconds: 600), _endTypingSession);
  }

  /// Called when the debounce timer fires — typing paused.
  void _endTypingSession() {
    if (!_isInTypingSession) return;
    final before = _preTypingSnapshot;
    _preTypingSnapshot = null;
    _isInTypingSession = false;
    if (before != null) _pushToUndo(before);
  }

  /// Call this BEFORE applying any structural change (Enter, delete line,
  /// toggle checklist, checkbox toggle). Flushes any pending typing session
  /// first so every distinct action is a separate undo step.
  void _commitBeforeStructuralChange() {
    _sessionEndTimer?.cancel();
    _endTypingSession(); // may push pre-typing snapshot

    // Now push the current state as the "before structural change" snapshot.
    _pushToUndo(_captureSnapshot());
  }

  void _undo() {
    _sessionEndTimer?.cancel();

    // Flush any mid-typing state so it lands on the undo stack.
    if (_isInTypingSession && _preTypingSnapshot != null) {
      final before = _preTypingSnapshot!;
      _preTypingSnapshot = null;
      _isInTypingSession = false;
      final current = _captureSnapshot();
      if (!_snapshotsEqual(before, current)) {
        _undoStack.add(before);
        if (_undoStack.length > 100) _undoStack.removeAt(0);
        // Don't clear redo here — we're undoing, not making a new change.
      }
    } else {
      _preTypingSnapshot = null;
      _isInTypingSession = false;
    }

    if (_undoStack.isEmpty) return;

    final current = _captureSnapshot();
    final snapshot = _undoStack.removeLast();
    _redoStack.add(current);
    _restoreSnapshot(snapshot);
    setState(() {});
  }

  void _redo() {
    _sessionEndTimer?.cancel();
    _preTypingSnapshot = null;
    _isInTypingSession = false;

    if (_redoStack.isEmpty) return;

    final current = _captureSnapshot();
    final snapshot = _redoStack.removeLast();
    _undoStack.add(current);
    if (_undoStack.length > 100) _undoStack.removeAt(0);
    _restoreSnapshot(snapshot);
    setState(() {});
  }

  void _restoreSnapshot(_NoteSnapshot snapshot) {
    _suppressTextListener = true;
    _title.text = snapshot.title;
    setState(() {
      _clearLines();
      for (final line in snapshot.lines) {
        _addLine(
          text: line.text,
          isChecklist: line.isChecklist,
          isChecked: line.isChecked,
          markDirty: false,
        );
      }
      if (_lines.isEmpty) _addLine(markDirty: false);
      _dirty = true;
    });
    _suppressTextListener = false;
  }

  // ── Existing editor logic ────────────────────────────────────────────────

  void _onTitleChanged() {
    if (_suppressTextListener) return;
    _markDirty();
    _onTypingChange();
  }

  void _populateLinesFromDescription(String description) {
    _clearLines();
    final rawLines = description.isEmpty ? [''] : description.split('\n');
    for (final raw in rawLines) {
      final match = RegExp(r'^\[( |x|X)\]\s*').firstMatch(raw);
      final isChecklist = match != null;
      final isChecked = match != null && match.group(1)?.toLowerCase() == 'x';
      final text = match == null ? raw : raw.replaceFirst(match.group(0)!, '');
      _addLine(
        text: text,
        isChecklist: isChecklist,
        isChecked: isChecked,
        markDirty: false,
      );
    }
    if (_lines.isEmpty) {
      _addLine(markDirty: false);
    }
    _activeLineIndex = _lines.isEmpty ? null : 0;
  }

  void _addLine({
    String text = '',
    bool isChecklist = false,
    bool isChecked = false,
    bool markDirty = true,
    int? insertAt,
    bool requestFocus = false,
  }) {
    final line = _NoteLineData(
      text: text,
      isChecklist: isChecklist,
      isChecked: isChecked,
    );
    line.controller.addListener(() => _handleLineChanged(line));
    line.focusNode.addListener(() {
      if (line.focusNode.hasFocus) {
        _activeLineIndex = _lines.indexOf(line);
      }
    });
    if (insertAt == null || insertAt < 0 || insertAt > _lines.length) {
      _lines.add(line);
    } else {
      _lines.insert(insertAt, line);
    }
    if (markDirty) _markDirty();
    if (requestFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) line.focusNode.requestFocus();
      });
    }
  }

  void _handleLineChanged(_NoteLineData line) {
    if (_suppressTextListener) return;
    _markDirty();
    final text = line.controller.text;
    if (!text.contains('\n')) {
      _onTypingChange(); // normal typing
      return;
    }
    // Enter key — structural change.
    _commitBeforeStructuralChange();
    final parts = text.split('\n');
    final first = parts.first;
    final rest = parts.sublist(1);
    final index = _lines.indexOf(line);
    if (index < 0) return;
    _suppressTextListener = true;
    line.controller.value = TextEditingValue(
      text: first,
      selection: TextSelection.collapsed(offset: first.length),
    );
    _suppressTextListener = false;
    if (rest.isEmpty) return;
    setState(() {
      var insertAt = index + 1;
      for (final entry in rest) {
        _addLine(
          text: entry,
          isChecklist: line.isChecklist,
          isChecked: false,
          markDirty: false,
          insertAt: insertAt,
        );
        insertAt += 1;
      }
      _dirty = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final focusIndex = (index + 1).clamp(0, _lines.length - 1);
      _activeLineIndex = focusIndex;
      final target = _lines[focusIndex];
      target.focusNode.requestFocus();
      target.controller.selection = TextSelection.collapsed(
        offset: target.controller.text.length,
      );
    });
  }

  void _toggleChecklistLine() {
    final i = _activeLineIndex;
    if (i == null || i < 0 || i >= _lines.length) return;
    _commitBeforeStructuralChange();
    setState(() {
      final line = _lines[i];
      line.isChecklist = !line.isChecklist;
      if (!line.isChecklist) {
        line.isChecked = false;
      } else {
        line.controller.text = line.controller.text.replaceAll('\n', ' ');
      }
      _dirty = true;
    });
  }

  void _handleBackspace(int index) {
    if (index < 0 || index >= _lines.length) return;
    final line = _lines[index];
    if (!line.focusNode.hasFocus) return;
    if (line.controller.text.trim().isNotEmpty) return;
    if (_lines.length == 1) return;

    _commitBeforeStructuralChange();
    setState(() {
      line.dispose();
      _lines.removeAt(index);
      _dirty = true;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _lines.isEmpty) return;
      final prevIndex = (index - 1).clamp(0, _lines.length - 1);
      _activeLineIndex = prevIndex;
      final prev = _lines[prevIndex];
      prev.focusNode.requestFocus();
      prev.controller.selection = TextSelection.collapsed(
        offset: prev.controller.text.length,
      );
    });
  }

  bool _shouldHandleBackspace(_NoteLineData line) {
    if (!line.focusNode.hasFocus) return false;
    if (_lines.length == 1) return false;
    final selection = line.controller.selection;
    if (!selection.isValid || !selection.isCollapsed) return false;
    return line.controller.text.isEmpty;
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  String _serializeLines() {
    return _lines
        .where((line) => line.controller.text.trim().isNotEmpty || line.isChecklist)
        .map((line) {
          final text = line.controller.text;
          if (!line.isChecklist) return text;
          return '[${line.isChecked ? 'x' : ' '}] ${text.trim()}';
        })
        .join('\n');
  }

  void _clearLines() {
    for (final line in _lines) {
      line.dispose();
    }
    _lines.clear();
  }

  NoteEntry _buildResult() {
    final now = DateTime.now();
    final description = _serializeLines();
    final hasChecklist = _lines.any((line) => line.isChecklist);

    if (widget.existing == null) {
      return NoteEntry(
        id: now.microsecondsSinceEpoch.toString(),
        title: _title.text.trim(),
        description: description,
        category: widget.category,
        date: null,
        createdAt: now,
        updatedAt: now,
        isPinned: false,
        addedToCalendar: false,
        isChecklist: hasChecklist,
      );
    }

    return widget.existing!.copyWith(
      title: _title.text.trim(),
      description: description,
      updatedAt: now,
      isChecklist: hasChecklist,
    );
  }

  Future<void> _close() async {
    if (_dirty) {
      Navigator.pop(context, _buildResult());
    } else {
      Navigator.pop(context, null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canUndo = _undoStack.isNotEmpty;
    final canRedo = _redoStack.isNotEmpty;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _close();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: _close,
          ),
          actions: [
            IconButton(
              icon: Icon(
                Icons.undo,
                color: canUndo ? null : Colors.grey[300],
              ),
              onPressed: canUndo ? _undo : null,
              tooltip: 'Undo',
            ),
            IconButton(
              icon: Icon(
                Icons.redo,
                color: canRedo ? null : Colors.grey[300],
              ),
              onPressed: canRedo ? _redo : null,
              tooltip: 'Redo',
            ),
            IconButton(
              icon: const Icon(Icons.checklist_outlined),
              onPressed: _toggleChecklistLine,
            ),
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _close,
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
          child: Column(
            children: [
              TextField(
                controller: _title,
                decoration: const InputDecoration(
                  hintText: 'Title',
                  border: InputBorder.none,
                ),
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: _buildLinesEditor(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLinesEditor() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 12),
      itemCount: _lines.length,
      separatorBuilder: (_, __) => const SizedBox(height: 2),
      itemBuilder: (context, index) {
        final line = _lines[index];
        final isChecklist = line.isChecklist;
        return Focus(
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.backspace) {
              if (_shouldHandleBackspace(line)) {
                _handleBackspace(index);
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.ignored;
          },
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isChecklist)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: Checkbox(
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity:
                          const VisualDensity(horizontal: -4, vertical: -4),
                      value: line.isChecked,
                      onChanged: (value) {
                        _commitBeforeStructuralChange();
                        setState(() {
                          line.isChecked = value ?? false;
                          _dirty = true;
                        });
                      },
                    ),
                  ),
                ),
              if (isChecklist) const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: line.controller,
                  focusNode: line.focusNode,
                  decoration: InputDecoration(
                    hintText: index == 0 ? 'Start typing...' : null,
                    border: InputBorder.none,
                    isCollapsed: true,
                  ),
                  style: TextStyle(
                    color: line.isChecklist && line.isChecked
                        ? Colors.blueGrey
                        : Colors.black87,
                    decoration: line.isChecklist && line.isChecked
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                  ),
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  maxLines: null,
                  minLines: 1,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _sessionEndTimer?.cancel();
    _title.dispose();
    _clearLines();
    super.dispose();
  }
}
