import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;

import 'catalog.dart';

/// Public keys allowed to sign the catalog, by key id (base64, Ed25519).
///
/// Release builds refuse every catalog until the production key is added
/// here, so an unsigned or tampered catalog can never ship.
const Map<String, String> kCatalogPublicKeys = <String, String>{
  // 'medha-2026-1': '<base64 Ed25519 public key>',
};

class CatalogSignatureException implements Exception {
  CatalogSignatureException(this.message);
  final String message;
  @override
  String toString() => 'CatalogSignatureException: $message';
}

/// Parses and verifies catalog documents.
///
/// Signed form: `{"keyId": "...", "payload": "<base64 JSON>", "signature": "<base64>"}`
/// where the signature is Ed25519 over the decoded payload bytes.
/// Unsigned form (development only): the catalog JSON itself.
class CatalogVerifier {
  CatalogVerifier({Map<String, String>? publicKeys, this.allowUnsigned = false})
      : _publicKeys = publicKeys ?? kCatalogPublicKeys;

  final Map<String, String> _publicKeys;
  final bool allowUnsigned;

  Future<Catalog> parse(String raw) async {
    final doc = jsonDecode(raw);
    if (doc is! Map<String, dynamic>) throw const FormatException('Catalog must be a JSON object');

    if (doc.containsKey('payload')) {
      final keyId = doc['keyId'] as String?;
      final key = keyId == null ? null : _publicKeys[keyId];
      if (key == null) throw CatalogSignatureException('Unknown signing key "$keyId"');

      final payload = base64Decode(doc['payload'] as String);
      final signature = base64Decode(doc['signature'] as String);
      final ok = await Ed25519().verify(
        payload,
        signature: Signature(signature, publicKey: SimplePublicKey(base64Decode(key), type: KeyPairType.ed25519)),
      );
      if (!ok) throw CatalogSignatureException('Signature does not match');
      return Catalog.fromJson(jsonDecode(utf8.decode(payload)) as Map<String, dynamic>);
    }

    if (!allowUnsigned) throw CatalogSignatureException('Catalog is not signed');
    return Catalog.fromJson(doc);
  }
}

/// Loads the catalog: cached copy first, then the bundled one, and refreshes
/// from the network when [remoteUrl] is set. A catalog that fails
/// verification is never used or cached.
class CatalogService {
  CatalogService({
    required this.verifier,
    required this.cacheFile,
    required this.loadBundled,
    this.remoteUrl,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final CatalogVerifier verifier;
  final File cacheFile;
  final Future<String> Function() loadBundled;
  final Uri? remoteUrl;
  final http.Client _client;

  Future<Catalog> load() async {
    if (await cacheFile.exists()) {
      try {
        return await verifier.parse(await cacheFile.readAsString());
      } on Object {
        // A corrupt or no-longer-trusted cache falls back to the bundled copy.
        await cacheFile.delete();
      }
    }
    return verifier.parse(await loadBundled());
  }

  /// Fetches a newer catalog. Returns it if it verified and is newer than
  /// [current], otherwise null.
  Future<Catalog?> refresh(Catalog current) async {
    final url = remoteUrl;
    if (url == null) return null;
    final res = await _client.get(url).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) return null;
    final raw = utf8.decode(res.bodyBytes);
    final next = await verifier.parse(raw);
    if (next.version <= current.version) return null;
    await cacheFile.parent.create(recursive: true);
    await cacheFile.writeAsString(raw, flush: true);
    return next;
  }
}
