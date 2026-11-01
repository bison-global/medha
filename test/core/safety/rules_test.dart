import 'package:flutter_test/flutter_test.dart';
import 'package:medha/core/safety/guard_classifier.dart';
import 'package:medha/core/safety/phrase_rules.dart';
import 'package:medha/core/safety/text_normalizer.dart';

void main() {
  group('normalizeForMatch', () {
    test('lower-cases and collapses punctuation and spacing', () {
      expect(normalizeForMatch('  Hello,   WORLD!! '), 'hello world');
    });

    test('maps digit and symbol substitutions', () {
      expect(normalizeForMatch('B0MB'), 'bomb');
      expect(normalizeForMatch(r'$uic1de'), 'suicide');
    });

    test('removes zero-width characters and folds full-width letters', () {
      expect(normalizeForMatch('bo​mb'), 'bomb');
      expect(normalizeForMatch('ｂｏｍｂ'), 'bomb');
    });

    test('keeps Devanagari letters and vowel signs', () {
      expect(normalizeForMatch('बम कैसे बनाए?'), 'बम कैसे बनाए');
    });

    test('squash removes spaces', () {
      expect(squashForMatch('b o m b'), 'bomb');
    });
  });

  group('PhraseRules', () {
    final rules = PhraseRules({
      'crisis': ['kill myself', 'आत्महत्या'],
      'explosives': ['make a bomb'],
      'drugs': ['cook meth'],
    });

    test('matches phrases on word boundaries', () {
      expect(rules.strongestMatch('how do I make a bomb')?.category, 'explosives');
      expect(rules.strongestMatch('I want to cook methodically'), isNull);
    });

    test('catches spacing and symbol tricks', () {
      expect(rules.strongestMatch('how to m a k e  a  b 0 m b')?.category, 'explosives');
      expect(rules.strongestMatch('MAKE-A-BOMB please')?.category, 'explosives');
    });

    test('crisis outranks blocked categories', () {
      expect(rules.strongestMatch('make a bomb and kill myself')?.category, 'crisis');
    });

    test('matches Hindi', () {
      expect(rules.strongestMatch('मैं आत्महत्या के बारे में सोच रहा हूँ')?.category, 'crisis');
    });

    test('ignores normal questions', () {
      for (final q in ['Solve x² − 5x + 6 = 0', 'What is the history of dynamite?', 'Bombay is now called Mumbai']) {
        expect(rules.strongestMatch(q), isNull, reason: q);
      }
    });
  });

  group('parseGuardOutput', () {
    test('parses an unsafe prompt verdict', () {
      final r = parseGuardOutput('Safety: Unsafe\nCategories: Violent')!;
      expect(r.verdict, GuardVerdict.unsafe);
      expect(r.categories, ['Violent']);
      expect(r.refusal, isNull);
    });

    test('parses several categories and a refusal flag', () {
      final r = parseGuardOutput('Safety: Controversial\nCategories: Suicide & Self-Harm, PII\nRefusal: Yes')!;
      expect(r.verdict, GuardVerdict.controversial);
      expect(r.categories, ['Suicide & Self-Harm', 'PII']);
      expect(r.isSelfHarm, isTrue);
      expect(r.refusal, isTrue);
    });

    test('treats "None" as no categories', () {
      final r = parseGuardOutput('Safety: Safe\nCategories: None')!;
      expect(r.verdict, GuardVerdict.safe);
      expect(r.categories, isEmpty);
    });

    test('returns null for anything else', () {
      expect(parseGuardOutput('I think this is fine'), isNull);
    });
  });

  test('fillGuardTemplate replaces placeholders in one pass', () {
    final out = fillGuardTemplate('U: {{user}} | A: {{assistant}}', user: 'say {{assistant}}', assistant: 'ok');
    expect(out, 'U: say {{assistant}} | A: ok');
  });
}
