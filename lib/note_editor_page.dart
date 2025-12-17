part of 'main.dart';

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

  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.existing?.title ?? '');
    _body = TextEditingController(text: widget.existing?.description ?? '');

    _title.addListener(_markDirty);
    _body.addListener(_markDirty);
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  NoteEntry _buildResult() {
    final now = DateTime.now();

    if (widget.existing == null) {
      return NoteEntry(
        id: now.microsecondsSinceEpoch.toString(),
        title: _title.text.trim(),
        description: _body.text,
        category: widget.category,
        date: null,
        createdAt: now,
        updatedAt: now,
        isPinned: false,
        addedToCalendar: false,
      );
    }

    return widget.existing!.copyWith(
      title: _title.text.trim(),
      description: _body.text,
      updatedAt: now,
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
                child: TextField(
                  controller: _body,
                  decoration: const InputDecoration(
                    hintText: 'Start typing...',
                    border: InputBorder.none,
                  ),
                  keyboardType: TextInputType.multiline,
                  maxLines: null,
                  expands: true,
                  style: const TextStyle(fontSize: 15, height: 1.35),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }
}