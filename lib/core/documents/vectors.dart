import 'dart:math';
import 'dart:typed_data';

/// int8 vector plus the scale that maps it back to floats.
class QuantizedVector {
  const QuantizedVector(this.values, this.scale);
  final Int8List values;
  final double scale;
}

/// L2-normalises [v] and quantises it to int8 (ARCHITECTURE.md §8.1).
QuantizedVector quantize(List<double> v) {
  var norm = 0.0;
  for (final x in v) {
    norm += x * x;
  }
  norm = sqrt(norm);
  final out = Int8List(v.length);
  if (norm == 0) return QuantizedVector(out, 0);
  var maxAbs = 0.0;
  for (final x in v) {
    maxAbs = max(maxAbs, (x / norm).abs());
  }
  final scale = maxAbs / 127;
  for (var i = 0; i < v.length; i++) {
    out[i] = ((v[i] / norm) / scale).round().clamp(-127, 127).toInt();
  }
  return QuantizedVector(out, scale);
}

/// L2-normalised float copy of [v].
Float32List normalize(List<double> v) {
  var norm = 0.0;
  for (final x in v) {
    norm += x * x;
  }
  norm = sqrt(norm);
  final out = Float32List(v.length);
  if (norm == 0) return out;
  for (var i = 0; i < v.length; i++) {
    out[i] = v[i] / norm;
  }
  return out;
}

/// Cosine similarity between a normalised query and a quantised vector.
double cosine(Float32List query, List<int> q8, double scale) {
  if (q8.length != query.length) return -1;
  var dot = 0.0;
  for (var i = 0; i < q8.length; i++) {
    dot += query[i] * q8[i];
  }
  return dot * scale;
}

/// Reciprocal Rank Fusion of several ranked id lists: score = Σ 1/(k + rank).
List<int> reciprocalRankFusion(List<List<int>> rankings, {int k = 60}) {
  final scores = <int, double>{};
  for (final list in rankings) {
    for (var rank = 0; rank < list.length; rank++) {
      scores[list[rank]] = (scores[list[rank]] ?? 0) + 1 / (k + rank + 1);
    }
  }
  final ids = scores.keys.toList()..sort((a, b) => scores[b]!.compareTo(scores[a]!));
  return ids;
}
