/// Splits text into overlapping chunks of about [size] characters
/// (≈ 500 tokens), breaking at paragraph, then sentence, then word boundaries.
List<String> chunkText(String text, {int size = 1750, int overlap = 280}) {
  final t = text.trim();
  if (t.isEmpty) return const [];
  if (t.length <= size) return [t];

  final chunks = <String>[];
  var start = 0;
  while (start < t.length) {
    var end = start + size;
    if (end >= t.length) {
      chunks.add(t.substring(start).trim());
      break;
    }
    end = _breakPoint(t, start + size ~/ 2, end);
    final piece = t.substring(start, end).trim();
    if (piece.isNotEmpty) chunks.add(piece);
    final next = end - overlap;
    // Start the next chunk on a word boundary inside the overlap.
    var s = next <= start ? end : next;
    while (s < end && s < t.length && t[s] != ' ' && t[s] != '\n') {
      s++;
    }
    start = s;
  }
  return chunks.where((c) => c.isNotEmpty).toList();
}

int _breakPoint(String t, int min, int max) {
  for (final sep in const ['\n\n', '\n', '. ', '? ', '! ', '। ', ' ']) {
    final i = t.lastIndexOf(sep, max);
    if (i >= min) return i + sep.length;
  }
  return max;
}
