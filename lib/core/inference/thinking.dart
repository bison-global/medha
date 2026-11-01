/// Splits a reasoning model's output into its hidden reasoning (`<think>…</think>`)
/// and the visible answer, as text streams in.
class ThinkingSplitter {
  ThinkingSplitter({this.open = '<think>', this.close = '</think>'});

  final String open;
  final String close;

  final StringBuffer _raw = StringBuffer();

  String get raw => _raw.toString();

  void add(String chunk) => _raw.write(chunk);

  /// True while the model is still inside its reasoning block.
  bool get inReasoning {
    final s = raw.trimLeft();
    return s.startsWith(open) && !s.contains(close);
  }

  /// Text that might still turn into the opening tag.
  bool get undecided {
    final s = raw.trimLeft();
    return s.length < open.length && open.startsWith(s);
  }

  String get reasoning {
    final s = raw.trimLeft();
    if (!s.startsWith(open)) return '';
    final end = s.indexOf(close);
    return (end < 0 ? s.substring(open.length) : s.substring(open.length, end)).trim();
  }

  String get answer {
    final s = raw.trimLeft();
    if (undecided) return '';
    if (!s.startsWith(open)) return s;
    final end = s.indexOf(close);
    return end < 0 ? '' : s.substring(end + close.length).trimLeft();
  }
}
