import 'text_normalizer.dart';

class PhraseMatch {
  const PhraseMatch(this.category, this.phrase);
  final String category;
  final String phrase;

  @override
  String toString() => 'PhraseMatch($category)';
}

/// Layer 1 of the safety pipeline: instant, deterministic phrase matching
/// against the signed phrase list from the catalog (ARCHITECTURE.md §9.4).
class PhraseRules {
  PhraseRules(Map<String, List<String>> phrases, {this.minSquashedLength = 6})
      : _entries = [
          for (final group in phrases.entries)
            for (final phrase in group.value)
              if (normalizeForMatch(phrase).isNotEmpty)
                _Entry(group.key, phrase, ' ${normalizeForMatch(phrase)} ', squashForMatch(phrase)),
        ];

  /// Spaced-out matching ("m a k e a b o m b") only applies to phrases at
  /// least this long once spaces are removed.
  final int minSquashedLength;
  final List<_Entry> _entries;

  static const String crisisCategory = 'crisis';

  /// Joins runs of three or more single-character words, which is how
  /// spaced-out text looks after normalisation. Normal words are left alone,
  /// so "cook methodically" never turns into "cookmeth…".
  static List<String> _spacedOutRuns(String normalized) {
    final runs = <String>[];
    final current = StringBuffer();
    var count = 0;
    void flush() {
      if (count >= 3) runs.add(current.toString());
      current.clear();
      count = 0;
    }

    for (final word in normalized.split(' ')) {
      if (word.runes.length == 1) {
        current.write(word);
        count++;
      } else {
        flush();
      }
    }
    flush();
    return runs;
  }

  List<PhraseMatch> matches(String text) {
    final normalized = normalizeForMatch(text);
    final spaced = ' $normalized ';
    final runs = _spacedOutRuns(normalized);
    final out = <PhraseMatch>[];
    for (final e in _entries) {
      final hit = spaced.contains(e.spaced) ||
          (e.squashed.length >= minSquashedLength && runs.any((r) => r.contains(e.squashed)));
      if (hit) out.add(PhraseMatch(e.category, e.phrase));
    }
    return out;
  }

  /// The most important match: crisis outranks every blocked category.
  PhraseMatch? strongestMatch(String text) {
    final all = matches(text);
    if (all.isEmpty) return null;
    return all.firstWhere((m) => m.category == crisisCategory, orElse: () => all.first);
  }
}

class _Entry {
  const _Entry(this.category, this.phrase, this.spaced, this.squashed);
  final String category;
  final String phrase;
  final String spaced;
  final String squashed;
}
