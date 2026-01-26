class TtsChunker {
  TtsChunker({
    this.minStartChars = 3000,
    this.maxChunkChars = 5000,
  });

  final int minStartChars;
  final int maxChunkChars;
  String _buffer = '';
  bool _started = false;
  bool _inCodeBlock = false;

  void reset() {
    _buffer = '';
    _started = false;
    _inCodeBlock = false;
  }

  List<String> addText(String text) {
    if (text.isEmpty) {
      return const [];
    }
    _buffer += text;
    return _drainChunks(force: false);
  }

  List<String> flush() {
    if (_buffer.isEmpty) {
      return const [];
    }
    return _drainChunks(force: true);
  }

  List<String> _drainChunks({required bool force}) {
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
      final minIndex = force ? 0 : minStartChars;
      final boundary = _findSentenceBoundary(segment, minIndex);
      if (boundary != -1) {
        final chunk = segment.substring(0, boundary);
        if (chunk.trim().isNotEmpty) {
          chunks.add(chunk);
          _started = true;
        }
        buffer = buffer.substring(boundary);
        continue;
      }

      final threshold = _started ? maxChunkChars : minStartChars;
      if (segment.length >= threshold || force) {
        final cut = _fallbackCut(segment, maxChunkChars);
        final chunk = segment.substring(0, cut);
        if (chunk.trim().isNotEmpty) {
          chunks.add(chunk);
          _started = true;
        }
        buffer = buffer.substring(cut);
        continue;
      }

      break;
    }

    _buffer = buffer;
    return chunks;
  }

  int _findSentenceBoundary(String text, int startIndex) {
    if (text.isEmpty) {
      return -1;
    }
    final start = startIndex < 0 ? 0 : startIndex;
    for (var i = start; i < text.length; i++) {
      final char = text[i];
      if (_isSentenceBoundary(text, i, char)) {
        return i + 1;
      }
    }
    return -1;
  }

  bool _isSentenceBoundary(String text, int index, String char) {
    if (char == '.' && _isDecimalPoint(text, index)) {
      return false;
    }
    return char == '.' ||
        char == '!' ||
        char == '?' ||
        char == '。' ||
        char == '！' ||
        char == '？';
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

  int _fallbackCut(String text, int maxChars) {
    if (text.length <= maxChars) {
      return text.length;
    }
    for (var i = maxChars - 1; i >= 0; i--) {
      if (text[i].trim().isEmpty) {
        return i + 1;
      }
    }
    return maxChars;
  }
}
