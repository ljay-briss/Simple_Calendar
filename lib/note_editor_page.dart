part of 'main.dart';

class _ChecklistItemData {
  _ChecklistItemData({required String text, required this.isChecked})
      : controller = TextEditingController(text: text);

  final TextEditingController controller;
  bool isChecked;

  void dispose() => controller.dispose();
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
  late final TextEditingController _body;
  bool _isChecklist = false;
  final List<_ChecklistItemData> _checklistItems = [];

  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _isChecklist = widget.existing?.isChecklist ?? false;
    _title = TextEditingController(text: widget.existing?.title ?? '');
    _body = TextEditingController(
      text: _isChecklist ? '' : (widget.existing?.description ?? ''),
    );
    _title.addListener(_markDirty);
    _body.addListener(_markDirty);

        if (_isChecklist) {
      _populateChecklistFromDescription(widget.existing?.description ?? '');
    }
  }

  void _populateChecklistFromDescription(String description) {
    _clearChecklistControllers();
    final lines = description.isEmpty ? [''] : description.split('\n');
    for (final line in lines) {
      final match = RegExp(r'^\[( |x|X)\]\s*').firstMatch(line);
      final isChecked = match != null && match.group(1)?.toLowerCase() == 'x';
      final text = match == null ? line : line.replaceFirst(match.group(0)!, '');
      _addChecklistItem(text: text, isChecked: isChecked, markDirty: false);
    }
    if (_checklistItems.isEmpty) {
      _addChecklistItem(markDirty: false);
    }
  }

  void _addChecklistItem({String text = '', bool isChecked = false, bool markDirty = true}) {
    final item = _ChecklistItemData(text: text, isChecked: isChecked);
    item.controller.addListener(_markDirty);
    _checklistItems.add(item);
    if (markDirty && !_dirty) {
      _dirty = true;
    }
  }

  void _removeChecklistItem(int index) {
    if (index < 0 || index >= _checklistItems.length) return;
    setState(() {
      _checklistItems[index].dispose();
      _checklistItems.removeAt(index);
      if (_checklistItems.isEmpty) {
        _addChecklistItem(markDirty: false);
      }
      _dirty = true;
    });
  }

  void _toggleChecklist() {
    setState(() {
      if (_isChecklist) {
        _body.text = _checklistItems.map((item) => item.controller.text).join('\n');
        _clearChecklistControllers();
        _isChecklist = false;
      } else {
        _populateChecklistFromDescription(_body.text);
        _isChecklist = true;
      }
      _dirty = true;
    });
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }


  String _serializeChecklist() {
    return _checklistItems
        .map(
          (item) => '[${item.isChecked ? 'x' : ' '}] ${item.controller.text.trim()}',
        )
        .join('\n');
  }

  void _clearChecklistControllers() {
    for (final item in _checklistItems) {
      item.dispose();
    }
    _checklistItems.clear();
  }

  NoteEntry _buildResult() {
    final now = DateTime.now();
    final description = _isChecklist ? _serializeChecklist() : _body.text;

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
        isChecklist: _isChecklist,
      );
    }

    return widget.existing!.copyWith(
      title: _title.text.trim(),
      description: description,
      updatedAt: now,
      isChecklist: _isChecklist,
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
              icon: Icon(_isChecklist ? Icons.checklist_rtl : Icons.checklist_outlined),
              onPressed: _toggleChecklist,
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
                child: _isChecklist ? _buildChecklistEditor() : _buildTextBody(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextBody() {
    return TextField(
      controller: _body,
      decoration: const InputDecoration(
        hintText: 'Start typing...',
        border: InputBorder.none,
      ),
      keyboardType: TextInputType.multiline,
      maxLines: null,
      expands: true,
      style: const TextStyle(fontSize: 15, height: 1.35),
    );
  }

  Widget _buildChecklistEditor() {
    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            itemCount: _checklistItems.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final item = _checklistItems[index];
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blueGrey[50],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Checkbox(
                      value: item.isChecked,
                      onChanged: (value) {
                        setState(() {
                          item.isChecked = value ?? false;
                          _dirty = true;
                        });
                      },
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: TextField(
                        controller: item.controller,
                        decoration: const InputDecoration(
                          hintText: 'List item',
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => _removeChecklistItem(index),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            icon: const Icon(Icons.add_task),
            label: const Text('Add item'),
            onPressed: () => setState(() => _addChecklistItem()),
          ),
        ),
      ],
    );
  }


  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _clearChecklistControllers();
    super.dispose();
  }
}