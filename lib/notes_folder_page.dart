part of 'main.dart';

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
    final preview = note.description.trim().replaceAll('\n', ' ');
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
        } else {
          widget.onDelete(note.id);
          setState(() {});
          return true;
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
                ],
              ),
              const SizedBox(height: 6),
              Text(
                preview.isEmpty ? 'No additional text' : preview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.blueGrey[600], fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
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