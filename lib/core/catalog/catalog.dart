/// The model catalog: which models exist, which subjects use them, and the
/// safety configuration. It is fetched as a signed manifest (see
/// catalog_service.dart) so models, prompts and safety rules can change
/// without an app release.
library;

/// A downloadable model file. Several interests can share one base file.
class BaseModel {
  const BaseModel({
    required this.id,
    required this.name,
    required this.maker,
    required this.license,
    required this.licenseText,
    required this.url,
    required this.bytes,
    required this.sha256,
    required this.minRamMb,
    required this.promptTemplate,
    this.runtime = ModelRuntime.llama,
    this.notice,
  });

  final String id;
  final String name;
  final String maker;
  final String license;
  final String licenseText;
  final String? notice;
  final String url;
  final int bytes;
  final String sha256;
  final int minRamMb;

  /// How to format a conversation for this model: `native` (the template
  /// embedded in the GGUF), `chatml` or `gemma`.
  final String promptTemplate;
  final ModelRuntime runtime;

  String get fileName => '$id.gguf';

  factory BaseModel.fromJson(Map<String, dynamic> j) => BaseModel(
        id: j['id'] as String,
        name: j['name'] as String,
        maker: j['maker'] as String,
        license: j['license'] as String,
        licenseText: (j['licenseText'] as String?) ?? '',
        notice: j['notice'] as String?,
        url: (j['file'] as Map<String, dynamic>)['url'] as String,
        bytes: ((j['file'] as Map<String, dynamic>)['bytes'] as num).toInt(),
        sha256: (j['file'] as Map<String, dynamic>)['sha256'] as String,
        minRamMb: (j['minRamMb'] as num?)?.toInt() ?? 0,
        promptTemplate: (j['promptTemplate'] as String?) ?? 'native',
        runtime: ModelRuntime.parse(j['runtime'] as String?),
      );
}

enum ModelRuntime {
  llama,
  onnx;

  static ModelRuntime parse(String? s) => s == 'onnx' ? ModelRuntime.onnx : ModelRuntime.llama;
}

class SamplingParams {
  const SamplingParams({this.temperature = 1.0, this.topP = 0.95, this.topK = 40, this.minP = 0, this.presencePenalty = 0});

  final double temperature;
  final double topP;
  final int topK;
  final double minP;
  final double presencePenalty;

  static const greedy = SamplingParams(temperature: 0, topP: 1, topK: 1);

  factory SamplingParams.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const SamplingParams();
    double d(String k, double fallback) => (j[k] as num?)?.toDouble() ?? fallback;
    return SamplingParams(
      temperature: d('temperature', 1.0),
      topP: d('topP', 0.95),
      topK: (j['topK'] as num?)?.toInt() ?? 40,
      minP: d('minP', 0),
      presencePenalty: d('presencePenalty', 0),
    );
  }
}

class ThinkingConfig {
  const ThinkingConfig({required this.enabled, this.maxTokens = 0});
  final bool enabled;

  /// Reasoning-token cap; once reached the app forces the final answer.
  final int maxTokens;

  factory ThinkingConfig.fromJson(Map<String, dynamic>? j) =>
      ThinkingConfig(enabled: (j?['enabled'] as bool?) ?? false, maxTokens: (j?['maxTokens'] as num?)?.toInt() ?? 0);
}

/// A LoRA subject add-on applied on top of a base model.
class AdapterFile {
  const AdapterFile({required this.id, required this.url, required this.bytes, required this.sha256, this.scale = 1.0});
  final String id;
  final String url;
  final int bytes;
  final String sha256;
  final double scale;

  String get fileName => '$id.lora.gguf';

  static AdapterFile? fromJson(Map<String, dynamic>? j) => j == null
      ? null
      : AdapterFile(
          id: j['id'] as String,
          url: (j['url'] as String?) ?? '',
          bytes: (j['bytes'] as num?)?.toInt() ?? 0,
          sha256: (j['sha256'] as String?) ?? '',
          scale: (j['scale'] as num?)?.toDouble() ?? 1.0,
        );
}

/// A subject + tier the user can pick, e.g. "Medha Math Lite".
class InterestEntry {
  const InterestEntry({
    required this.id,
    required this.interest,
    required this.name,
    required this.tier,
    required this.sizeLabel,
    required this.blurb,
    required this.color,
    required this.baseModelId,
    required this.systemPrompt,
    required this.sampling,
    required this.thinking,
    required this.contextTokens,
    required this.maxNewTokens,
    required this.prompts,
    required this.available,
    this.fallbackBaseModelId,
    this.adapter,
    this.tag,
  });

  final String id;
  final String interest;
  final String name;
  final String tier;
  final String sizeLabel;
  final String blurb;
  final int color;
  final String baseModelId;
  final String? fallbackBaseModelId;
  final String systemPrompt;
  final SamplingParams sampling;
  final ThinkingConfig thinking;
  final int contextTokens;
  final int maxNewTokens;
  final List<String> prompts;

  /// False for subjects listed in the catalog but not shipped yet.
  final bool available;

  /// Optional fine-tuned add-on (ARCHITECTURE.md §5.3).
  final AdapterFile? adapter;

  /// Short label on the subject card, e.g. "Best with voice".
  final String? tag;

  String get displayName => 'Medha $name $sizeLabel';

  factory InterestEntry.fromJson(Map<String, dynamic> j) => InterestEntry(
        id: j['id'] as String,
        interest: j['interest'] as String,
        name: j['name'] as String,
        tier: j['tier'] as String,
        sizeLabel: (j['sizeLabel'] as String?) ?? '',
        blurb: (j['blurb'] as String?) ?? '',
        color: int.parse(((j['color'] as String?) ?? '#F5A524').replaceFirst('#', 'FF'), radix: 16),
        baseModelId: j['baseModelId'] as String,
        fallbackBaseModelId: j['fallbackBaseModelId'] as String?,
        systemPrompt: j['systemPrompt'] as String,
        sampling: SamplingParams.fromJson(j['sampling'] as Map<String, dynamic>?),
        thinking: ThinkingConfig.fromJson(j['thinking'] as Map<String, dynamic>?),
        contextTokens: (j['contextTokens'] as num?)?.toInt() ?? 4096,
        maxNewTokens: (j['maxNewTokens'] as num?)?.toInt() ?? 768,
        prompts: ((j['prompts'] as List?) ?? const []).cast<String>(),
        available: (j['available'] as bool?) ?? true,
        adapter: AdapterFile.fromJson(j['adapter'] as Map<String, dynamic>?),
        tag: j['tag'] as String?,
      );
}

/// A crisis helpline shown on the support card.
class CrisisResource {
  const CrisisResource({required this.label, required this.number, required this.description});
  final String label;
  final String number;
  final String description;

  factory CrisisResource.fromJson(Map<String, dynamic> j) =>
      CrisisResource(label: j['label'] as String, number: j['number'] as String, description: j['description'] as String);
}

/// Safety configuration delivered with the catalog (ARCHITECTURE.md §9.4).
class SafetyConfig {
  const SafetyConfig({
    required this.guardModelId,
    required this.guardPromptTemplate,
    required this.guardResponseTemplate,
    required this.systemPromptBlock,
    required this.crisisSystemPrompt,
    required this.refusals,
    required this.crisisTitle,
    required this.crisisBody,
    required this.crisisResources,
    required this.phrases,
  });

  final String guardModelId;

  /// Raw guard prompt with a `{{user}}` placeholder (pre-rendered from the
  /// guard model's own chat template, since llama.cpp has no Jinja engine).
  final String guardPromptTemplate;

  /// Raw guard prompt for checking replies: `{{user}}` and `{{assistant}}`.
  final String guardResponseTemplate;

  /// Fixed safety rules prepended to every interest's system prompt.
  final String systemPromptBlock;

  /// Extra instructions used when a message shows distress.
  final String crisisSystemPrompt;

  /// Refusal text per category key (`weapons`, `drugs`, `sexual`, ...,
  /// `default`, `cooldown`, `unavailable`).
  final Map<String, String> refusals;
  final String crisisTitle;
  final String crisisBody;
  final List<CrisisResource> crisisResources;

  /// Phrase lists: `crisis` plus one list per blocked category.
  final Map<String, List<String>> phrases;

  String refusalFor(String category) => refusals[category] ?? refusals['default'] ?? "I can't help with that.";

  factory SafetyConfig.fromJson(Map<String, dynamic> j) => SafetyConfig(
        guardModelId: j['guardModelId'] as String,
        guardPromptTemplate: j['guardPromptTemplate'] as String,
        guardResponseTemplate: j['guardResponseTemplate'] as String,
        systemPromptBlock: j['systemPromptBlock'] as String,
        crisisSystemPrompt: j['crisisSystemPrompt'] as String,
        refusals: (j['refusals'] as Map<String, dynamic>).map((k, v) => MapEntry(k, v as String)),
        crisisTitle: j['crisisTitle'] as String,
        crisisBody: j['crisisBody'] as String,
        crisisResources: ((j['crisisResources'] as List?) ?? const [])
            .map((e) => CrisisResource.fromJson(e as Map<String, dynamic>))
            .toList(),
        phrases: (j['phrases'] as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, (v as List).cast<String>())),
      );
}

class Catalog {
  const Catalog({
    required this.version,
    required this.baseModels,
    required this.interests,
    required this.safety,
    this.embeddingModelId,
  });

  final int version;

  /// Model used to index documents for search, downloaded with the first upload.
  final String? embeddingModelId;

  BaseModel? get embeddingModel => embeddingModelId == null ? null : baseModels[embeddingModelId];
  final Map<String, BaseModel> baseModels;
  final List<InterestEntry> interests;
  final SafetyConfig safety;

  BaseModel baseModel(String id) {
    final m = baseModels[id];
    if (m == null) throw StateError('Catalog has no base model "$id"');
    return m;
  }

  InterestEntry interestEntry(String id) =>
      interests.firstWhere((e) => e.id == id, orElse: () => throw StateError('Catalog has no interest "$id"'));

  BaseModel get guardModel => baseModel(safety.guardModelId);

  /// Unique subjects in catalog order, for the picker.
  List<InterestEntry> get subjects {
    final seen = <String>{};
    final out = <InterestEntry>[];
    for (final e in interests) {
      if (seen.add(e.interest)) out.add(e);
    }
    return out;
  }

  List<InterestEntry> tiersFor(String interest) => interests.where((e) => e.interest == interest).toList();

  factory Catalog.fromJson(Map<String, dynamic> j) {
    final bases = <String, BaseModel>{
      for (final b in (j['baseModels'] as List<dynamic>).cast<Map<String, dynamic>>()) b['id'] as String: BaseModel.fromJson(b),
    };
    final interests = (j['interests'] as List).map((e) => InterestEntry.fromJson(e as Map<String, dynamic>)).toList();
    final catalog = Catalog(
      version: (j['version'] as num).toInt(),
      baseModels: bases,
      interests: interests,
      safety: SafetyConfig.fromJson(j['safety'] as Map<String, dynamic>),
      embeddingModelId: j['embeddingModelId'] as String?,
    );
    catalog._validate();
    return catalog;
  }

  void _validate() {
    final emb = embeddingModelId;
    if (emb != null && !baseModels.containsKey(emb)) {
      throw const FormatException('Catalog embeddingModelId does not match a base model');
    }
    if (!baseModels.containsKey(safety.guardModelId)) {
      throw const FormatException('Catalog safety.guardModelId does not match a base model');
    }
    for (final e in interests) {
      if (!baseModels.containsKey(e.baseModelId)) {
        throw FormatException('Interest ${e.id} points at unknown base model ${e.baseModelId}');
      }
      final fb = e.fallbackBaseModelId;
      if (fb != null && !baseModels.containsKey(fb)) {
        throw FormatException('Interest ${e.id} points at unknown fallback model $fb');
      }
    }
  }
}
