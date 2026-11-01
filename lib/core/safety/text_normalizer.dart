/// Normalises text before phrase matching so spacing, symbol and case tricks
/// ("B 0 m b", full-width letters, zero-width spaces) don't slip past.
library;

final _zeroWidth = RegExp('[​-‏⁠﻿­]');
final _separators = RegExp(r'[^\p{L}\p{N}\p{M}]+', unicode: true);
final _spaces = RegExp(r'\s+');

const _leet = <String, String>{
  '0': 'o',
  '1': 'i',
  '3': 'e',
  '4': 'a',
  '5': 's',
  '7': 't',
  '@': 'a',
  r'$': 's',
};

/// Lower-cases, folds full-width ASCII, maps common digit/symbol substitutions
/// and turns every run of punctuation or spacing into a single space.
String normalizeForMatch(String input) {
  final b = StringBuffer();
  for (final rune in input.replaceAll(_zeroWidth, '').runes) {
    var c = rune;
    if (c >= 0xFF01 && c <= 0xFF5E) c -= 0xFEE0; // full-width → ASCII
    final ch = String.fromCharCode(c).toLowerCase();
    b.write(_leet[ch] ?? ch);
  }
  return b.toString().replaceAll(_separators, ' ').replaceAll(_spaces, ' ').trim();
}

/// [normalizeForMatch] with all spaces removed, to catch "b o m b".
String squashForMatch(String input) => normalizeForMatch(input).replaceAll(' ', '');
