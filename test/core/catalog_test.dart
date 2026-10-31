import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medha/core/catalog/catalog.dart';
import 'package:medha/core/catalog/catalog_service.dart';

import '../helpers.dart';

void main() {
  group('Catalog', () {
    test('parses the development catalog', () {
      final c = devCatalog();
      expect(c.guardModel.name, 'Qwen3Guard-Gen-0.6B');
      final math = c.interestEntry('math-lite');
      expect(math.available, isTrue);
      expect(math.thinking.enabled, isTrue);
      expect(math.thinking.maxTokens, 1536);
      expect(c.baseModel(math.baseModelId).name, 'MiniCPM5-2B');
      expect(c.subjects.map((s) => s.interest), containsAll(['math', 'science', 'coding', 'wellness', 'farming']));
      expect(c.tiersFor('math').map((t) => t.tier), ['Lite', 'Pro']);
      expect(c.safety.crisisResources.map((r) => r.number), contains('14416'));
    });

    test('M1 ships Math Lite only', () {
      final available = devCatalog().interests.where((e) => e.available).map((e) => e.id);
      expect(available, ['math-lite']);
    });

    test('rejects an interest that points at a missing model', () {
      final j = devCatalogJson();
      ((j['interests'] as List).first as Map<String, dynamic>)['baseModelId'] = 'nope';
      expect(() => Catalog.fromJson(j), throwsFormatException);
    });

    test('rejects a missing guard model', () {
      final j = devCatalogJson();
      (j['safety'] as Map<String, dynamic>)['guardModelId'] = 'nope';
      expect(() => Catalog.fromJson(j), throwsFormatException);
    });
  });

  group('CatalogVerifier', () {
    late SimpleKeyPair keyPair;
    late String publicKeyB64;

    setUp(() async {
      keyPair = await Ed25519().newKeyPair();
      publicKeyB64 = base64Encode((await keyPair.extractPublicKey()).bytes);
    });

    Future<String> signed(List<int> payload, {String keyId = 'test'}) async {
      final sig = await Ed25519().sign(payload, keyPair: keyPair);
      return jsonEncode({'keyId': keyId, 'payload': base64Encode(payload), 'signature': base64Encode(sig.bytes)});
    }

    test('accepts a correctly signed catalog', () async {
      final payload = utf8.encode(jsonEncode(devCatalogJson()));
      final v = CatalogVerifier(publicKeys: {'test': publicKeyB64});
      final c = await v.parse(await signed(payload));
      expect(c.version, 1);
    });

    test('rejects a tampered payload', () async {
      final payload = utf8.encode(jsonEncode(devCatalogJson()));
      final doc = jsonDecode(await signed(payload)) as Map<String, dynamic>;
      final tampered = devCatalogJson()..['version'] = 99;
      doc['payload'] = base64Encode(utf8.encode(jsonEncode(tampered)));
      final v = CatalogVerifier(publicKeys: {'test': publicKeyB64});
      expect(() => v.parse(jsonEncode(doc)), throwsA(isA<CatalogSignatureException>()));
    });

    test('rejects an unknown key id', () async {
      final payload = utf8.encode(jsonEncode(devCatalogJson()));
      final v = CatalogVerifier(publicKeys: {'test': publicKeyB64});
      expect(() async => v.parse(await signed(payload, keyId: 'other')), throwsA(isA<CatalogSignatureException>()));
    });

    test('refuses unsigned catalogs unless allowed', () async {
      final raw = jsonEncode(devCatalogJson());
      expect(() => CatalogVerifier(publicKeys: const {}).parse(raw), throwsA(isA<CatalogSignatureException>()));
      final c = await CatalogVerifier(publicKeys: const {}, allowUnsigned: true).parse(raw);
      expect(c.interests, isNotEmpty);
    });
  });
}
