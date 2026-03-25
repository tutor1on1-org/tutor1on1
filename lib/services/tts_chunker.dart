class TtsChunker {
  TtsChunker({
    this.minStartChars = 3000,
    this.maxChunkChars = 5000,
    this.minWordsFromEnd = 10,
  });

  final int minStartChars;
  final int maxChunkChars;
  final int minWordsFromEnd;
  String _buffer = '';
  bool _started = false;
  bool _inCodeBlock = false;

  void reset() {
    _buffer = '';
    _started = false;
    _inCodeBlock = false;
  }

  List<String> addText(String text, {bool allowCut = true}) {
    if (text.isEmpty) {
      return const [];
    }
    _buffer += text;
    if (!allowCut) {
      return const [];
    }
    return _drainChunks(ignoreThreshold: false, maxChunks: null);
  }

  List<String> flush() {
    if (_buffer.isEmpty) {
      return const [];
    }
    return _drainChunks(ignoreThreshold: false, maxChunks: null);
  }

  List<String> flushComplete() {
    if (_buffer.isEmpty) {
      return const [];
    }
    final chunk = _buffer;
    _buffer = '';
    _started = true;
    _inCodeBlock = false;
    return [chunk];
  }

  String? prefetchChunk() {
    final chunks = _drainChunks(ignoreThreshold: true, maxChunks: 1);
    if (chunks.isEmpty) {
      return null;
    }
    return chunks.first;
  }

  List<String> _drainChunks({
    required bool ignoreThreshold,
    int? maxChunks,
  }) {
    final chunks = <String>[];
    var buffer = _buffer;
    while (buffer.isNotEmpty) {
      if (_inCodeBlock) {
        final end = buffer.indexOf('```');
        if (end == -1) {
          break;
        }
        buffer = buffer.substring(end + 3);
        _inCodeBlock = false;
        continue;
      }

      final codeStart = buffer.indexOf('```');
      final searchEnd = codeStart == -1 ? buffer.length : codeStart;
      if (searchEnd == 0) {
        _inCodeBlock = true;
        buffer = buffer.substring(3);
        continue;
      }

      final segment = buffer.substring(0, searchEnd);
      final threshold = _started ? maxChunkChars : minStartChars;
      if (!ignoreThreshold && segment.length < threshold) {
        break;
      }

      final boundary = _findSentenceBoundaryNearEnd(segment);
      if (boundary != -1) {
        final chunk = segment.substring(0, boundary);
        if (chunk.trim().isNotEmpty) {
          chunks.add(chunk);
          _started = true;
        }
        buffer = buffer.substring(boundary);
        if (maxChunks != null && chunks.length >= maxChunks) {
          break;
        }
        continue;
      }

      break;
    }

    _buffer = buffer;
    return chunks;
  }

  int _findSentenceBoundaryNearEnd(String text) {
    if (text.isEmpty) {
      return -1;
    }
    for (var i = text.length - 1; i >= 0; i--) {
      int? candidate;
      if (text[i] == '。') {
        candidate = i + 1;
      } else if (text[i] == '\t') {
        candidate = i + 1;
      } else if (i >= 1 && text[i - 1] == '.' && text[i] == ' ') {
        if (!_isDecimalPoint(text, i - 1)) {
          candidate = i + 1;
        }
      } else if (i >= 1 && text[i - 1] == ' ' && text[i] == ' ') {
        candidate = i + 1;
      }
      if (candidate != null) {
        final wordsAfter = _countWords(text.substring(candidate));
        if (wordsAfter <= minWordsFromEnd) {
          return candidate;
        }
      }
    }
    return -1;
  }

  bool _isDecimalPoint(String text, int index) {
    if (index <= 0 || index >= text.length - 1) {
      return false;
    }
    final before = text[index - 1];
    final after = text[index + 1];
    return _isDigit(before) && _isDigit(after);
  }

  bool _isDigit(String char) {
    return char.codeUnitAt(0) >= 48 && char.codeUnitAt(0) <= 57;
  }

  int _countWords(String text) {
    if (text.trim().isEmpty) {
      return 0;
    }
    final parts = text.trim().split(RegExp(r'\s+'));
    return parts.where((part) => part.isNotEmpty).length;
  }
}
