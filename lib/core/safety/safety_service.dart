import '../catalog/catalog.dart';
import 'guard_classifier.dart';
import 'phrase_rules.dart';

/// What to do with a user message before the chat model runs.
sealed class InputDecision {
  const InputDecision();
}

/// Run the chat model normally. [controversial] replies still get output checks.
class AllowInput extends InputDecision {
  const AllowInput({this.controversial = false});
  final bool controversial;
}

/// Show the support card, then reply with the crisis prompt (never blocked).
class CrisisInput extends InputDecision {
  const CrisisInput();
}

/// Show a fixed refusal; the chat model never runs.
class BlockInput extends InputDecision {
  const BlockInput(this.category, this.message);
  final String category;
  final String message;
}

/// Too many blocked attempts recently; chat is paused briefly.
class CooldownInput extends InputDecision {
  const CooldownInput(this.message, this.remaining);
  final String message;
  final Duration remaining;
}

/// The safety model failed; fail closed rather than answer unchecked.
class UnavailableInput extends InputDecision {
  const UnavailableInput(this.message);
  final String message;
}

sealed class OutputDecision {
  const OutputDecision();
}

class AllowOutput extends OutputDecision {
  const AllowOutput();
}

/// Stop streaming and replace the visible reply with [message].
class BlockOutput extends OutputDecision {
  const BlockOutput(this.category, this.message);
  final String category;
  final String message;
}

/// Slows down repeated attempts: after [threshold] blocked requests in a
/// tracked category within [window], chat pauses for [cooldown].
/// Only timestamps are kept, in memory — never message text.
class AttemptLimiter {
  AttemptLimiter({
    this.threshold = 3,
    this.window = const Duration(minutes: 10),
    this.cooldown = const Duration(minutes: 2),
    this.trackedCategories = const {'weapons', 'explosives'},
  });

  final int threshold;
  final Duration window;
  final Duration cooldown;
  final Set<String> trackedCategories;

  final List<DateTime> _attempts = [];
  DateTime? _cooldownUntil;

  Duration? remaining(DateTime now) {
    final until = _cooldownUntil;
    if (until == null || !now.isBefore(until)) return null;
    return until.difference(now);
  }

  void record(String category, DateTime now) {
    if (!trackedCategories.contains(category)) return;
    _attempts
      ..add(now)
      ..removeWhere((t) => now.difference(t) > window);
    if (_attempts.length >= threshold) {
      _cooldownUntil = now.add(cooldown);
      _attempts.clear();
    }
  }
}

/// Guard categories mapped to Medha refusal keys. Unsafe results in these
/// categories are blocked; others are answered with output checks.
const Map<String, String> kGuardCategoryKeys = {
  'violent': 'weapons',
  'non-violent illegal acts': 'illegal',
  'sexual content or sexual acts': 'sexual',
  'unethical acts': 'hate',
  'jailbreak': 'jailbreak',
  'pii': 'privacy',
};

/// The four-layer safety pipeline from ARCHITECTURE.md §9.4, minus the
/// system prompt (applied by ContextBuilder).
class SafetyService {
  SafetyService({
    required this.config,
    required this.guard,
    PhraseRules? rules,
    AttemptLimiter? limiter,
    DateTime Function()? clock,
  })  : rules = rules ?? PhraseRules(config.phrases),
        limiter = limiter ?? AttemptLimiter(),
        _now = clock ?? DateTime.now;

  final SafetyConfig config;
  final GuardClassifier guard;
  final PhraseRules rules;
  final AttemptLimiter limiter;
  final DateTime Function() _now;

  String? _categoryKey(List<String> guardCategories) {
    for (final c in guardCategories) {
      final key = kGuardCategoryKeys[c.toLowerCase()];
      if (key != null) return key;
    }
    return null;
  }

  Future<InputDecision> checkInput(String text, {String? attachmentText}) async {
    final combined = attachmentText == null || attachmentText.isEmpty ? text : '$text\n\n$attachmentText';
    final now = _now();

    // Crisis is checked first and is exempt from cooldowns: someone in
    // distress is never told to wait.
    final rule = rules.strongestMatch(combined);
    if (rule?.category == PhraseRules.crisisCategory) return const CrisisInput();

    final wait = limiter.remaining(now);
    if (wait != null) return CooldownInput(config.refusalFor('cooldown'), wait);

    if (rule != null) {
      limiter.record(rule.category, now);
      return BlockInput(rule.category, config.refusalFor(rule.category));
    }

    final GuardResult g;
    try {
      g = await guard.checkPrompt(combined);
    } on Object {
      return UnavailableInput(config.refusalFor('unavailable'));
    }

    if (g.isSelfHarm && g.verdict != GuardVerdict.safe) return const CrisisInput();
    if (g.verdict == GuardVerdict.unsafe) {
      final key = _categoryKey(g.categories);
      if (key != null) {
        limiter.record(key, now);
        return BlockInput(key, config.refusalFor(key));
      }
    }
    return AllowInput(controversial: g.verdict == GuardVerdict.controversial);
  }

  /// Checks a (partial) reply. Phrase rules run first; then the guard model
  /// in response mode. Fails closed if the guard model errors.
  Future<OutputDecision> checkOutput(String userText, String reply) async {
    final rule = rules.strongestMatch(reply);
    if (rule != null && rule.category != PhraseRules.crisisCategory) {
      return BlockOutput(rule.category, config.refusalFor(rule.category));
    }
    final GuardResult g;
    try {
      g = await guard.checkResponse(userText, reply);
    } on Object {
      return BlockOutput('unavailable', config.refusalFor('unavailable'));
    }
    if (g.verdict == GuardVerdict.unsafe) {
      if (g.isSelfHarm) return BlockOutput('crisis', config.refusalFor('crisis'));
      final key = _categoryKey(g.categories);
      if (key != null) return BlockOutput(key, config.refusalFor(key));
    }
    return const AllowOutput();
  }
}
