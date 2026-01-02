part of 'main.dart';

class _BackspaceIntent extends Intent {
  const _BackspaceIntent();
}

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

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.existing?.title ?? '');
    _title.addListener(_markDirty);
    _populateLinesFromDescription(widget.existing?.description ?? '');
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
    if (!text.contains('\n')) return;
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

  void _removeLine(int index) {
    if (index < 0 || index >= _lines.length) return;
    setState(() {
      _lines[index].dispose();
      _lines.removeAt(index);
      if (_lines.isEmpty) {
        _addLine(markDirty: false);
      }
      _dirty = true;
    });
  }

  void _toggleChecklistLine() {
    final i = _activeLineIndex;
    if (i == null || i < 0 || i >= _lines.length) return;
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
    if (line.controller.text.isNotEmpty) return;
    if (_lines.length == 1) return;
    setState(() {
      line.dispose();
      _lines.removeAt(index);
      _dirty = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _lines.isEmpty) return;
      final nextIndex = (index - 1).clamp(0, _lines.length - 1);
      _activeLineIndex = nextIndex;
      _lines[nextIndex].focusNode.requestFocus();
    });
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  String _serializeLines() {
    return _lines
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
    return WillPopScope(
      onWillPop: () async {
        await _close();
        return false;
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
        return Shortcuts(
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.backspace): _BackspaceIntent(),
          },
          child: Actions(
            actions: <Type, Action<Intent>>{
              _BackspaceIntent: CallbackAction<_BackspaceIntent>(
                onInvoke: (intent) {
                  _handleBackspace(index);
                  return null;
                },
              ),
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
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _title.dispose();
    _clearLines();
    super.dispose();
  }
}
