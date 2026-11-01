// Builds a catalog with real file sizes and SHA-256 checksums, and signs it.
//
//   # one-off: create a signing key (keep the seed file secret)
//   dart run tool/make_catalog.dart --gen-key --key-out catalog_signing.seed
//
//   # fill in sizes/checksums/URLs and sign
//   dart run tool/make_catalog.dart \
//     --template assets/catalog/catalog.dev.json \
//     --model minicpm5-2b-q4km=/path/MiniCPM5-2B-Q4_K_M.gguf=https://cdn.example.com/medha/minicpm5-2b-q4_k_m.gguf \
//     --model qwen3guard-gen-0_6b-q4km=/path/Qwen3Guard-Gen-0.6B-Q4_K_M.gguf=https://cdn.example.com/medha/qwen3guard.gguf \
//     --version 2 --key catalog_signing.seed --key-id medha-2026-1 --out catalog.json
//
// Without --key the output is unsigned (accepted by debug builds only).
// Add the printed public key to kCatalogPublicKeys in catalog_service.dart.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

Future<void> main(List<String> args) async {
  final opts = _parse(args);

  if (opts.flags.contains('gen-key')) {
    final out = opts.single('key-out') ?? 'catalog_signing.seed';
    final pair = await Ed25519().newKeyPair();
    final seed = await pair.extractPrivateKeyBytes();
    await File(out).writeAsString(base64Encode(seed));
    final pub = await pair.extractPublicKey();
    stdout
      ..writeln('Wrote private seed to $out (keep it secret, never commit it).')
      ..writeln('Public key (add to kCatalogPublicKeys): ${base64Encode(pub.bytes)}');
    return;
  }

  final templatePath = opts.single('template') ?? 'assets/catalog/catalog.dev.json';
  final catalog = jsonDecode(await File(templatePath).readAsString()) as Map<String, dynamic>;
  final version = opts.single('version');
  if (version != null) catalog['version'] = int.parse(version);

  final bases = {
    for (final b in (catalog['baseModels'] as List).cast<Map<String, dynamic>>()) b['id'] as String: b,
  };
  for (final spec in opts.multi('model')) {
    final parts = spec.split('=');
    if (parts.length < 2) throw ArgumentError('--model expects id=path[=url], got "$spec"');
    final id = parts[0];
    final file = File(parts[1]);
    final url = parts.length > 2 ? parts.sublist(2).join('=') : null;
    final base = bases[id] ?? (throw ArgumentError('No base model "$id" in $templatePath'));
    stderr.writeln('Hashing ${file.path} …');
    final digest = await sha256.bind(file.openRead()).first;
    base['file'] = {
      'url': url ?? (base['file'] as Map<String, dynamic>)['url'],
      'bytes': await file.length(),
      'sha256': digest.toString(),
    };
  }

  final payload = utf8.encode(const JsonEncoder.withIndent('  ').convert(catalog));
  final keyPath = opts.single('key');
  final String output;
  if (keyPath == null) {
    output = utf8.decode(payload);
    stderr.writeln('Warning: unsigned catalog (debug builds only).');
  } else {
    final keyId = opts.single('key-id') ?? (throw ArgumentError('--key-id is required with --key'));
    final seed = base64Decode((await File(keyPath).readAsString()).trim());
    final pair = await Ed25519().newKeyPairFromSeed(seed);
    final sig = await Ed25519().sign(payload, keyPair: pair);
    output = const JsonEncoder.withIndent('  ').convert({
      'keyId': keyId,
      'payload': base64Encode(payload),
      'signature': base64Encode(sig.bytes),
    });
  }

  final outPath = opts.single('out');
  if (outPath == null) {
    stdout.writeln(output);
  } else {
    await File(outPath).writeAsString(output);
    stderr.writeln('Wrote $outPath');
  }
}

class _Opts {
  final Map<String, List<String>> values = {};
  final Set<String> flags = {};
  String? single(String k) => values[k]?.last;
  List<String> multi(String k) => values[k] ?? const [];
}

_Opts _parse(List<String> args) {
  final o = _Opts();
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (!a.startsWith('--')) throw ArgumentError('Unexpected argument "$a"');
    final name = a.substring(2);
    if (i + 1 < args.length && !args[i + 1].startsWith('--')) {
      o.values.putIfAbsent(name, () => []).add(args[++i]);
    } else {
      o.flags.add(name);
    }
  }
  return o;
}
