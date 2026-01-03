part of 'main.dart';

const int _notePreviewLineLimit = 3;

enum _NoteAction { pin, delete }

class NotesFolderPage extends StatefulWidget {
  final String category;
  final List<NoteEntry> notes;
  final void Function(NoteEntry note) onUpsert;
  final void Function(String noteId) onDelete;
  final void Function(String noteId) onTogglePin;

  const NotesFolderPage({
    super.key,
    required this.category,
    required this.notes,
    required this.onUpsert,
    required this.onDelete,
    required this.onTogglePin,
  });

  @override
  State<NotesFolderPage> createState() => _NotesFolderPageState();
}

class _NotesFolderPageState extends State<NotesFolderPage> {
  List<NoteEntry> get _sortedFolderNotes {
    final list = widget.notes
        .where((n) => n.category.toLowerCase() == widget.category.toLowerCase())
        .toList();

    list.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final all = _sortedFolderNotes;
    final pinned = all.where((n) => n.isPinned).toList();
    final normal = all.where((n) => !n.isPinned).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFD4E8F4),
      appBar: AppBar(
        backgroundColor: const Color(0xFFD4E8F4),
        elevation: 0,
        title: Text(widget.category, style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () async {
              final created = await Navigator.push<NoteEntry?>(
                context,
                MaterialPageRoute(
                  builder: (_) => NoteEditorPage(
                    category: widget.category,
                    existing: null,
                  ),
                ),
              );
              if (created != null) {
                widget.onUpsert(created);
                setState(() {});
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (pinned.isNotEmpty) ...[
            _sectionLabel('Pinned'),
            const SizedBox(height: 8),
            ...pinned.map(_noteRow),
            const SizedBox(height: 14),
          ],
          if (normal.isNotEmpty) ...[
            _sectionLabel('Notes'),
            const SizedBox(height: 8),
            ...normal.map(_noteRow),
          ],
          if (pinned.isEmpty && normal.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(child: Text('No notes yet.')),
            ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        color: Colors.blueGrey[700],
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _noteRow(NoteEntry note) {
    final dateLabel = _formatAppleLikeDate(note.updatedAt);

    return Dismissible(
      key: ValueKey(note.id),
      background: _swipeBg(Icons.push_pin, note.isPinned ? 'Unpin' : 'Pin'),
      secondaryBackground: _swipeBg(Icons.delete_outline, 'Delete', isRight: true),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          widget.onTogglePin(note.id);
          setState(() {});
          return false;
        }
        return direction == DismissDirection.endToStart;
      },
      onDismissed: (direction) {
        if (direction == DismissDirection.endToStart) {
          widget.onDelete(note.id);
          setState(() {});
        }
      },
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          final updated = await Navigator.push<NoteEntry?>(
            context,
            MaterialPageRoute(
              builder: (_) => NoteEditorPage(
                category: widget.category,
                existing: note,
              ),
            ),
          );
          if (updated != null) {
            widget.onUpsert(updated);
            setState(() {});
          }
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.blueGrey[50]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      note.title.isEmpty ? 'Untitled' : note.title,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    dateLabel,
                    style: TextStyle(
                      color: Colors.blueGrey[500],
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (note.isPinned) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.push_pin, size: 16, color: Colors.blueGrey[400]),
                  ],
                  const SizedBox(width: 4),
                  PopupMenuButton<_NoteAction>(
                    icon: Icon(Icons.more_horiz, color: Colors.blueGrey[500], size: 20),
                    onSelected: (action) {
                      if (action == _NoteAction.pin) {
                        widget.onTogglePin(note.id);
                        setState(() {});
                        return;
                      }
                      widget.onDelete(note.id);
                      setState(() {});
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: _NoteAction.pin,
                        child: Text(note.isPinned ? 'Unpin' : 'Pin'),
                      ),
                      const PopupMenuItem(
                        value: _NoteAction.delete,
                        child: Text('Delete'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _buildNotePreview(note),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotePreview(NoteEntry note) {
    final allLines = _previewLines(note);
    if (allLines.isEmpty) {
      return Text(
        'No additional text',
        style: TextStyle(color: Colors.blueGrey[600], fontWeight: FontWeight.w500),
      );
    }
    final lines = allLines.take(_notePreviewLineLimit).toList();
    final hasMore = allLines.length > _notePreviewLineLimit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: line.isSpacer
                ? const SizedBox(height: 8)
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (line.isChecklist)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(
                            line.isChecked
                                ? Icons.check_box
                                : Icons.check_box_outline_blank,
                            size: 14,
                            color: line.isChecked
                                ? Colors.blueGrey[400]
                                : Colors.blueGrey[500],
                          ),
                        ),
                      if (line.isChecklist) const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            line.text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color:
                                  line.isChecked ? Colors.blueGrey[400] : Colors.blueGrey[600],
                              fontWeight: FontWeight.w500,
                              decoration: line.isChecked
                                  ? TextDecoration.lineThrough
                                  : TextDecoration.none,
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        if (hasMore)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '...',
              style: TextStyle(
                color: Colors.blueGrey[500],
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  List<_PreviewLine> _previewLines(NoteEntry note) {
    final result = <_PreviewLine>[];
    final raw = note.description;
    if (raw.trim().isEmpty) return result;
    final lines = raw.split('\n');
    for (final line in lines) {
      final trimmed = line.trimRight();
      if (trimmed.isEmpty) {
        result.add(const _PreviewLine(
          text: '',
          isChecklist: false,
          isChecked: false,
          isSpacer: true,
        ));
        continue;
      }
      final match = RegExp(r'^\[( |x|X)\]\s*').firstMatch(trimmed);
      final isChecklist = match != null;
      final isChecked = match != null && match.group(1)?.toLowerCase() == 'x';
      final text = match == null ? trimmed : trimmed.replaceFirst(match.group(0)!, '');
      result.add(_PreviewLine(
        text: text,
        isChecklist: isChecklist,
        isChecked: isChecked,
        isSpacer: false,
      ));
    }
    return result;
  }

  Widget _swipeBg(IconData icon, String label, {bool isRight = false}) {
    return Container(
      alignment: isRight ? Alignment.centerRight : Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: Colors.blueGrey[100],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.blueGrey[700]),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: Colors.blueGrey[700], fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  String _formatAppleLikeDate(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final thatDay = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(thatDay).inDays;

    if (diff == 0) return DateFormat('h:mm a').format(dt);
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return DateFormat('EEE').format(dt);
    return DateFormat('MMM d').format(dt);
  }
}

class _PreviewLine {
  const _PreviewLine({
    required this.text,
    required this.isChecklist,
    required this.isChecked,
    required this.isSpacer,
  });

  final String text;
  final bool isChecklist;
  final bool isChecked;
  final bool isSpacer;
}
