part of 'main.dart';

// Matches URLs in three forms:
//   1. Protocol-prefixed  — https://example.com, http://example.com
//   2. www-prefixed       — www.example.com
//   3. Bare domain        — example.com (common TLDs only, to avoid false positives)
final _urlRegex = RegExp(
  r'(?:https?://|www\.)[^\s]+'
  r'|\b[a-zA-Z0-9][\w\-]*\.(?:com|net|org|edu|gov|io|co|app|dev|ai|me'
  r'|info|biz|tech|uk|ca|au|de|fr|jp|cn|us|ly|gg|tv|fm|online|store'
  r'|cloud|site|web|link|shop|live|news|blog|media|studio|works|page'
  r'|digital|social|agency|email|support|help)[^\s]*',
  caseSensitive: false,
);

const String _plainUrlStart = '\uE000';
const String _plainUrlEnd = '\uE001';

/// Ensures [raw] has a scheme and strips trailing sentence punctuation.
String _normalizeUrl(String raw) {
  // Drop trailing punctuation that commonly follows a URL mid-sentence.
  final cleaned = raw.replaceAll(RegExp(r'[.,;:!?()\[\]«»"]+$'), '');
  if (cleaned.startsWith('http://') || cleaned.startsWith('https://')) {
    return cleaned;
  }
  return 'https://$cleaned';
}

class _ParsedPlainUrls {
  const _ParsedPlainUrls({required this.text, required this.urls});

  final String text;
  final Set<String> urls;
}

_ParsedPlainUrls _parsePlainUrlMarkers(String raw) {
  final urls = <String>{};
  final buffer = StringBuffer();
  var index = 0;
  while (index < raw.length) {
    final start = raw.indexOf(_plainUrlStart, index);
    if (start < 0) {
      buffer.write(raw.substring(index));
      break;
    }
    buffer.write(raw.substring(index, start));
    final end = raw.indexOf(_plainUrlEnd, start + _plainUrlStart.length);
    if (end < 0) {
      buffer.write(raw.substring(start));
      break;
    }
    final url = raw.substring(start + _plainUrlStart.length, end);
    urls.add(url);
    buffer.write(url);
    index = end + _plainUrlEnd.length;
  }
  return _ParsedPlainUrls(text: buffer.toString(), urls: urls);
}

String _serializePlainUrlMarkers(String text, Set<String> plainUrls) {
  if (plainUrls.isEmpty) return text;
  final buffer = StringBuffer();
  var lastEnd = 0;
  for (final match in _urlRegex.allMatches(text)) {
    final url = match.group(0)!;
    buffer.write(text.substring(lastEnd, match.start));
    if (plainUrls.contains(url)) {
      buffer.write('$_plainUrlStart$url$_plainUrlEnd');
    } else {
      buffer.write(url);
    }
    lastEnd = match.end;
  }
  buffer.write(text.substring(lastEnd));
  return buffer.toString();
}

class _NoteLineData {
  _NoteLineData({
    required String text,
    this.isChecklist = false,
    this.isChecked = false,
    this.isImage = false,
    this.imagePath,
    this.imageHeight = 0.78, // width fraction; default = Large
    Set<String>? plainUrls,
  }) : controller = TextEditingController(text: text),
       focusNode = FocusNode(),
       plainUrls = plainUrls ?? <String>{};

  final TextEditingController controller;
  final FocusNode focusNode;
  bool isChecklist;
  bool isChecked;
  bool isImage;
  String? imagePath;
  double imageHeight;
  Set<String> plainUrls;

  void dispose() {
    controller.dispose();
    focusNode.dispose();
  }
}

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
    this.isImage = false,
    this.imagePath,
    this.imageHeight = 0.78, // width fraction; default = Large
    this.plainUrls = const <String>{},
  });
  final String text;
  final bool isChecklist;
  final bool isChecked;
  final bool isImage;
  final String? imagePath;
  final double imageHeight;
  final Set<String> plainUrls;
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
  OverlayEntry? _linkOverlay;

  final List<_NoteSnapshot> _undoStack = [];
  final List<_NoteSnapshot> _redoStack = [];
  _NoteSnapshot? _preTypingSnapshot;
  bool _isInTypingSession = false;
  Timer? _sessionEndTimer;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.existing?.title ?? '');
    _title.addListener(_onTitleChanged);
    _populateLinesFromDescription(widget.existing?.description ?? '');
  }

  // ── Undo / Redo ───────────────────────────────────────────────────────────

  _NoteSnapshot _captureSnapshot() => _NoteSnapshot(
    title: _title.text,
    lines: _lines
        .map(
          (l) => _SnapshotLine(
            text: l.isImage ? '' : l.controller.text,
            isChecklist: l.isChecklist,
            isChecked: l.isChecked,
            isImage: l.isImage,
            imagePath: l.imagePath,
            imageHeight: l.imageHeight,
            plainUrls: Set<String>.from(l.plainUrls),
          ),
        )
        .toList(),
  );

  bool _snapshotsEqual(_NoteSnapshot a, _NoteSnapshot b) {
    if (a.title != b.title) return false;
    if (a.lines.length != b.lines.length) return false;
    for (var i = 0; i < a.lines.length; i++) {
      if (a.lines[i].text != b.lines[i].text) return false;
      if (a.lines[i].isChecklist != b.lines[i].isChecklist) return false;
      if (a.lines[i].isChecked != b.lines[i].isChecked) return false;
      if (a.lines[i].isImage != b.lines[i].isImage) return false;
      if (a.lines[i].imagePath != b.lines[i].imagePath) return false;
      if (a.lines[i].imageHeight != b.lines[i].imageHeight) return false;
      if (a.lines[i].plainUrls.length != b.lines[i].plainUrls.length) {
        return false;
      }
      if (!a.lines[i].plainUrls.containsAll(b.lines[i].plainUrls)) {
        return false;
      }
    }
    return true;
  }

  void _pushToUndo(_NoteSnapshot snapshot) {
    if (_undoStack.isNotEmpty && _snapshotsEqual(_undoStack.last, snapshot)) {
      return;
    }
    _undoStack.add(snapshot);
    if (_undoStack.length > 100) _undoStack.removeAt(0);
    _redoStack.clear();
    if (mounted) setState(() {});
  }

  void _onTypingChange() {
    if (!_isInTypingSession) {
      _preTypingSnapshot = _captureSnapshot();
      _isInTypingSession = true;
    }
    _sessionEndTimer?.cancel();
    _sessionEndTimer = Timer(
      const Duration(milliseconds: 600),
      _endTypingSession,
    );
  }

  void _endTypingSession() {
    if (!_isInTypingSession) return;
    final before = _preTypingSnapshot;
    _preTypingSnapshot = null;
    _isInTypingSession = false;
    if (before != null) _pushToUndo(before);
  }

  void _commitBeforeStructuralChange() {
    _sessionEndTimer?.cancel();
    _endTypingSession();
    _pushToUndo(_captureSnapshot());
  }

  void _undo() {
    _sessionEndTimer?.cancel();
    if (_isInTypingSession && _preTypingSnapshot != null) {
      final before = _preTypingSnapshot!;
      _preTypingSnapshot = null;
      _isInTypingSession = false;
      final current = _captureSnapshot();
      if (!_snapshotsEqual(before, current)) {
        _undoStack.add(before);
        if (_undoStack.length > 100) _undoStack.removeAt(0);
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
          isImage: line.isImage,
          imagePath: line.imagePath,
          imageHeight: line.imageHeight,
          plainUrls: line.plainUrls,
          markDirty: false,
        );
      }
      if (_lines.isEmpty) _addLine(markDirty: false);
      _dirty = true;
    });
    _suppressTextListener = false;
  }

  // ── Core editor logic ─────────────────────────────────────────────────────

  void _onTitleChanged() {
    if (_suppressTextListener) return;
    _markDirty();
    _onTypingChange();
  }

  void _populateLinesFromDescription(String description) {
    _clearLines();
    final rawLines = description.isEmpty ? [''] : description.split('\n');
    for (final raw in rawLines) {
      // Image line: ![img:0.75](path) — scale is a width fraction 0–1.
      // Old format used pixel heights (≥10); treat those as Large (1.0).
      final imgMatch = RegExp(
        r'^!\[img(?::(\d+(?:\.\d+)?))?\]\((.+)\)$',
      ).firstMatch(raw);
      if (imgMatch != null) {
        final rawVal = double.tryParse(imgMatch.group(1) ?? '');
        final scale = (rawVal == null || rawVal >= 10)
            ? 1.0
            : rawVal.clamp(0.1, 1.0).toDouble();
        _addLine(
          isImage: true,
          imagePath: imgMatch.group(2),
          imageHeight: scale,
          markDirty: false,
        );
        continue;
      }
      final checkMatch = RegExp(r'^\[( |x|X)\]\s*').firstMatch(raw);
      final isChecklist = checkMatch != null;
      final isChecked =
          checkMatch != null && checkMatch.group(1)?.toLowerCase() == 'x';
      final textWithMarkers = checkMatch == null
          ? raw
          : raw.replaceFirst(checkMatch.group(0)!, '');
      final parsedText = _parsePlainUrlMarkers(textWithMarkers);
      _addLine(
        text: parsedText.text,
        isChecklist: isChecklist,
        isChecked: isChecked,
        plainUrls: parsedText.urls,
        markDirty: false,
      );
    }
    if (_lines.isEmpty) _addLine(markDirty: false);
    _activeLineIndex = null;
  }

  void _addLine({
    String text = '',
    bool isChecklist = false,
    bool isChecked = false,
    bool isImage = false,
    String? imagePath,
    double imageHeight = 0.78,
    Set<String>? plainUrls,
    bool markDirty = true,
    int? insertAt,
    bool requestFocus = false,
  }) {
    final line = _NoteLineData(
      text: text,
      isChecklist: isChecklist,
      isChecked: isChecked,
      isImage: isImage,
      imagePath: imagePath,
      imageHeight: imageHeight,
      plainUrls: plainUrls,
    );
    if (!isImage) {
      line.controller.addListener(() => _handleLineChanged(line));
    }
    line.focusNode.addListener(() {
      // Rebuild on every focus change so we switch between TextField and
      // RichText (URL highlighting) modes correctly.
      if (mounted) setState(() {});
      if (line.focusNode.hasFocus) {
        _activeLineIndex = _lines.indexOf(line);
      } else if (_activeLineIndex == _lines.indexOf(line)) {
        _activeLineIndex = null;
      }
    });
    if (insertAt == null || insertAt < 0 || insertAt > _lines.length) {
      _lines.add(line);
    } else {
      _lines.insert(insertAt, line);
    }
    if (markDirty) _markDirty();
    if (requestFocus && !isImage) {
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
      _onTypingChange();
      return;
    }
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
    if (_lines[i].isImage) return;
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

  void _deleteImageLine(int index) {
    if (index < 0 || index >= _lines.length) return;
    _commitBeforeStructuralChange();
    setState(() {
      _lines[index].dispose();
      _lines.removeAt(index);
      if (_lines.isEmpty) _addLine();
      _dirty = true;
    });
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  void _hideLinkOverlay() {
    _linkOverlay?.remove();
    _linkOverlay = null;
  }

  Future<void> _openRawUrl(String rawUrl) async {
    final uri = Uri.tryParse(_normalizeUrl(rawUrl));
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _makeUrlPlainText(_NoteLineData line, RegExpMatch match) {
    _hideLinkOverlay();
    _commitBeforeStructuralChange();
    line.plainUrls.add(match.group(0)!);
    _activeLineIndex = _lines.indexOf(line);
    line.focusNode.requestFocus();
    _markDirty();
  }

  void _makeUrlHyperlink(_NoteLineData line, RegExpMatch match) {
    _hideLinkOverlay();
    _commitBeforeStructuralChange();
    line.plainUrls.remove(match.group(0)!);
    _activeLineIndex = _lines.indexOf(line);
    line.focusNode.requestFocus();
    _markDirty();
  }

  void _showLinkOverlay({
    required BuildContext context,
    required _NoteLineData line,
    required RegExpMatch match,
    required Offset anchor,
    required bool isPlainText,
  }) {
    _hideLinkOverlay();
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    final rawUrl = match.group(0)!;
    final normalizedUrl = _normalizeUrl(rawUrl);
    final screenSize = MediaQuery.sizeOf(context);
    final left = anchor.dx
        .clamp(12.0, math.max(12.0, screenSize.width - 348))
        .toDouble();
    final top = (anchor.dy + 10)
        .clamp(12.0, math.max(12.0, screenSize.height - 76))
        .toDouble();

    _linkOverlay = OverlayEntry(
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _hideLinkOverlay,
            ),
          ),
          Positioned(
            left: left,
            top: top,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: math.min(326, screenSize.width - 24),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.18),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: const BoxDecoration(
                        color: Color(0xFFD0D5D6),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          _hideLinkOverlay();
                          unawaited(_openRawUrl(rawUrl));
                        },
                        child: Text(
                          normalizedUrl,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.blue[700],
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 19),
                      tooltip: 'Copy link',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: normalizedUrl));
                        _hideLinkOverlay();
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 19),
                      tooltip: 'Edit link text',
                      onPressed: _hideLinkOverlay,
                    ),
                    IconButton(
                      icon: Icon(
                        isPlainText ? Icons.link : Icons.link_off,
                        size: 19,
                      ),
                      tooltip: isPlainText
                          ? 'Make hyperlink'
                          : 'Make plain text',
                      onPressed: () => isPlainText
                          ? _makeUrlHyperlink(line, match)
                          : _makeUrlPlainText(line, match),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
    overlay.insert(_linkOverlay!);
  }

  void _focusLastTextLine() {
    final candidates = _lines.where((l) => !l.isImage).toList();
    if (candidates.isEmpty) return;
    final last = candidates.last;
    last.focusNode.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        last.controller.selection = TextSelection.collapsed(
          offset: last.controller.text.length,
        );
      }
    });
  }

  // ── Serialization ─────────────────────────────────────────────────────────

  String _serializeLines() {
    final serialized = _lines.map((line) {
      if (line.isImage && line.imagePath != null) {
        return '![img:${line.imageHeight.toStringAsFixed(2)}](${line.imagePath})';
      }
      final text = line.controller.text;
      final serializedText = _serializePlainUrlMarkers(text, line.plainUrls);
      if (!line.isChecklist) return serializedText;
      return '[${line.isChecked ? 'x' : ' '}] ${serializedText.trim()}';
    }).toList();
    while (serialized.isNotEmpty && serialized.last.trim().isEmpty) {
      serialized.removeLast();
    }
    return serialized.join('\n');
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

  // ── Image insertion ───────────────────────────────────────────────────────

  Future<void> _showImageSourceSheet() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source != null && mounted) await _pickImage(source);
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 85);
    if (picked == null || !mounted) return;
    final dir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory('${dir.path}/note_images');
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }
    final fileName = 'img_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final destPath = '${imagesDir.path}/$fileName';
    await File(picked.path).copy(destPath);
    final insertAt = (_activeLineIndex ?? _lines.length - 1) + 1;
    _commitBeforeStructuralChange();
    setState(() {
      _addLine(isImage: true, imagePath: destPath, insertAt: insertAt);
      _dirty = true;
    });
  }

  // ── URL-aware RichText rendering ──────────────────────────────────────────

  /// Builds a [RichText] for [line] when it is not focused.
  /// URLs appear in blue and are tappable; all other text refocuses the line
  /// for editing when tapped.
  Widget _buildRichTextLine(_NoteLineData line) {
    final text = line.controller.text;
    final baseStyle = TextStyle(
      fontSize: 16,
      height: 1.4,
      color: line.isChecklist && line.isChecked
          ? Colors.blueGrey
          : Colors.black87,
      decoration: line.isChecklist && line.isChecked
          ? TextDecoration.lineThrough
          : TextDecoration.none,
    );
    final linkStyle = baseStyle.copyWith(
      color: Colors.blue[700],
      decoration: TextDecoration.underline,
      decorationColor: Colors.blue[700],
    );

    void focusLine({int? offset}) {
      _activeLineIndex = _lines.indexOf(line);
      if (mounted) setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final selectionOffset = (offset ?? line.controller.text.length).clamp(
            0,
            line.controller.text.length,
          );
          line.focusNode.requestFocus();
          line.controller.selection = TextSelection.collapsed(
            offset: selectionOffset,
          );
        }
      });
    }

    // Collect all URL-shaped text. Plain URLs stay visually normal but remain
    // tappable so the user can turn them back into hyperlinks.
    final urlMatches = _urlRegex.allMatches(text).toList();

    // Build spans with URL styling only. Gesture handling below maps the tap
    // position to the touched text range so only URL text opens as a link.
    final spans = <InlineSpan>[];
    int lastEnd = 0;
    for (final match in urlMatches) {
      if (match.start > lastEnd) {
        spans.add(
          TextSpan(
            text: text.substring(lastEnd, match.start),
            style: baseStyle,
          ),
        );
      }
      final url = match.group(0)!;
      spans.add(
        TextSpan(
          text: url,
          style: line.plainUrls.contains(url) ? baseStyle : linkStyle,
        ),
      );
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd), style: baseStyle));
    }
    if (spans.isEmpty) {
      spans.add(TextSpan(text: text.isEmpty ? '' : text, style: baseStyle));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        int textOffsetForPosition(Offset position) {
          final painter = TextPainter(
            text: TextSpan(children: spans),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout(maxWidth: constraints.maxWidth);
          return painter.getPositionForOffset(position).offset;
        }

        RegExpMatch? urlMatchAt(int offset) {
          for (final match in urlMatches) {
            if (offset >= match.start && offset < match.end) return match;
          }
          return null;
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            final offset = textOffsetForPosition(details.localPosition);
            final match = urlMatchAt(offset);
            focusLine(offset: offset);
            if (match != null) {
              _showLinkOverlay(
                context: context,
                line: line,
                match: match,
                anchor: details.globalPosition,
                isPlainText: line.plainUrls.contains(match.group(0)!),
              );
            }
          },
          onLongPressStart: (details) {
            focusLine(offset: textOffsetForPosition(details.localPosition));
          },
          child: RichText(text: TextSpan(children: spans)),
        );
      },
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

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
              icon: Icon(Icons.undo, color: canUndo ? null : Colors.grey[300]),
              onPressed: canUndo ? _undo : null,
              tooltip: 'Undo',
            ),
            IconButton(
              icon: Icon(Icons.redo, color: canRedo ? null : Colors.grey[300]),
              onPressed: canRedo ? _redo : null,
              tooltip: 'Redo',
            ),
            IconButton(
              icon: const Icon(Icons.checklist_outlined),
              onPressed: _toggleChecklistLine,
              tooltip: 'Toggle checklist',
            ),
            IconButton(
              icon: const Icon(Icons.image_outlined),
              onPressed: _showImageSourceSheet,
              tooltip: 'Insert image',
            ),
            IconButton(icon: const Icon(Icons.check), onPressed: _close),
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
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 6),
              Expanded(child: _buildLinesEditor()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLinesEditor() {
    // +1 for the empty spacer at the bottom (tapping empty space focuses last line).
    final total = _lines.length + 1;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 12),
      itemCount: total,
      separatorBuilder: (_, index) => index < _lines.length - 1
          ? const SizedBox(height: 2)
          : const SizedBox.shrink(),
      itemBuilder: (context, index) {
        // Spacer at the bottom — tapping empty space focuses the last line.
        if (index == _lines.length) {
          return GestureDetector(
            onTap: _focusLastTextLine,
            behavior: HitTestBehavior.opaque,
            child: const SizedBox(height: 200),
          );
        }
        final line = _lines[index];

        // ── Image line ──────────────────────────────────────────────────────
        if (line.isImage && line.imagePath != null) {
          return _buildImageLine(index, line.imagePath!);
        }

        final hasFocus = line.focusNode.hasFocus || _activeLineIndex == index;
        final text = line.controller.text;
        final hasUrl = _urlRegex.hasMatch(text);

        // ── View mode: not focused AND contains URL → RichText ──────────────
        if (!hasFocus && hasUrl) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (line.isChecklist) ...[
                SizedBox(
                  width: 22,
                  height: 22,
                  child: Checkbox(
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: const VisualDensity(
                      horizontal: -4,
                      vertical: -4,
                    ),
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
                const SizedBox(width: 8),
              ],
              Expanded(child: _buildRichTextLine(line)),
            ],
          );
        }

        // ── Edit mode: focused OR no URL → normal TextField ─────────────────
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
              if (line.isChecklist) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: Checkbox(
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: const VisualDensity(
                        horizontal: -4,
                        vertical: -4,
                      ),
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
                const SizedBox(width: 8),
              ],
              Expanded(
                child: TextField(
                  controller: line.controller,
                  focusNode: line.focusNode,
                  decoration: InputDecoration(
                    hintText: index == 0 ? 'Start typing...' : null,
                    border: InputBorder.none,
                    isCollapsed: true,
                    // Minimum touch target height so empty lines are easy to tap.
                    constraints: const BoxConstraints(minHeight: 44),
                  ),
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.4,
                    color: line.isChecklist && line.isChecked
                        ? Colors.blueGrey
                        : Colors.black87,
                    decoration: line.isChecklist && line.isChecked
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                  ),
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  textCapitalization: TextCapitalization.sentences,
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

  void _showImageOptions(int index) {
    final line = _lines[index];
    HapticFeedback.mediumImpact();
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      backgroundColor: Colors.white,
      builder: (_) => _ImageOptionsSheet(
        currentHeight: line.imageHeight,
        onSizeSelected: (height) {
          Navigator.pop(context);
          setState(() {
            line.imageHeight = height;
            _dirty = true;
          });
        },
        onDelete: () {
          Navigator.pop(context);
          _deleteImageLine(index);
        },
      ),
    );
  }

  Widget _buildImageLine(int index, String imagePath) {
    final line = _lines[index];
    final file = File(imagePath);
    // imageHeight stores the width fraction preset (0.22 / 0.44 / 0.78).
    final fraction = line.imageHeight.clamp(0.1, 1.0).toDouble();

    return GestureDetector(
      onLongPress: () => _showImageOptions(index),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final targetW = constraints.maxWidth * fraction;
            // AnimatedSize smoothly transitions when fraction changes without
            // needing a known height (natural image height is preserved).
            return Align(
              alignment: Alignment.centerLeft,
              child: AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                child: SizedBox(
                  width: targetW,
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: file.existsSync()
                            ? Image.file(
                                file,
                                width: targetW,
                                // BoxFit.contain — natural aspect ratio,
                                // nothing cropped.
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) =>
                                    _brokenImagePlaceholder(),
                              )
                            : _brokenImagePlaceholder(),
                      ),
                      // "Hold" hint badge
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black45,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.touch_app_outlined,
                                color: Colors.white,
                                size: 12,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Hold',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _brokenImagePlaceholder() => Container(
    height: 120,
    decoration: BoxDecoration(
      color: Colors.grey[200],
      borderRadius: BorderRadius.circular(10),
    ),
    child: Center(
      child: Icon(
        Icons.broken_image_outlined,
        color: Colors.grey[400],
        size: 40,
      ),
    ),
  );

  @override
  void dispose() {
    _hideLinkOverlay();
    _sessionEndTimer?.cancel();
    _title.dispose();
    _clearLines();
    super.dispose();
  }
}

// ── Image options bottom sheet ────────────────────────────────────────────────

class _ImageOptionsSheet extends StatefulWidget {
  const _ImageOptionsSheet({
    required this.currentHeight,
    required this.onSizeSelected,
    required this.onDelete,
  });

  final double currentHeight;
  final void Function(double height) onSizeSelected;
  final VoidCallback onDelete;

  @override
  State<_ImageOptionsSheet> createState() => _ImageOptionsSheetState();
}

class _ImageOptionsSheetState extends State<_ImageOptionsSheet> {
  static const double _small = 0.22;
  static const double _medium = 0.44;
  static const double _large = 0.78;

  late double _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.currentHeight;
  }

  // Returns the preset that the current height is closest to, or null.
  String? get _activeLabel {
    final diffs = {
      'Small': (_selected - _small).abs(),
      'Medium': (_selected - _medium).abs(),
      'Large': (_selected - _large).abs(),
    };
    final closest = diffs.entries.reduce((a, b) => a.value < b.value ? a : b);
    return closest.value < 0.05 ? closest.key : null;
  }

  @override
  Widget build(BuildContext context) {
    final active = _activeLabel;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 18),

            // Title
            const Text(
              'Image options',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 22),

            // Section label
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'VIEW AS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.blueGrey[500],
                  letterSpacing: 0.9,
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Size options — bar width mirrors the screen-fraction preset
            Row(
              children: [
                _sizeCard(
                  label: 'Small',
                  height: _small,
                  barFraction: _small,
                  isActive: active == 'Small',
                ),
                const SizedBox(width: 10),
                _sizeCard(
                  label: 'Medium',
                  height: _medium,
                  barFraction: _medium,
                  isActive: active == 'Medium',
                ),
                const SizedBox(width: 10),
                _sizeCard(
                  label: 'Large',
                  height: _large,
                  barFraction: _large,
                  isActive: active == 'Large',
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Divider(height: 1),

            // Delete
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.red[600],
                  size: 20,
                ),
              ),
              title: Text(
                'Delete image',
                style: TextStyle(
                  color: Colors.red[600],
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: widget.onDelete,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sizeCard({
    required String label,
    required double height,
    required double barFraction, // 0–1: how wide the preview bar is
    required bool isActive,
  }) {
    // Max bar width inside the card
    const double maxBarW = 48;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _selected = height);
          widget.onSizeSelected(height);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: isActive ? Colors.blue[600] : const Color(0xFFF3F5FA),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isActive ? Colors.blue[700]! : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Proportional width bar — mirrors the screen-fraction preset
              Container(
                width: maxBarW * barFraction,
                height: 5,
                decoration: BoxDecoration(
                  color: isActive
                      ? Colors.white.withValues(alpha: 0.9)
                      : Colors.blueGrey[300],
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isActive ? Colors.white : Colors.blueGrey[700],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
