import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:xml/xml.dart';

/// Upload limits (ARCHITECTURE.md §8).
abstract final class UploadLimits {
  static const allowedExtensions = ['pdf', 'docx', 'txt', 'md'];
  static const projectFileBytes = 10 * 1000 * 1000;
  static const projectFiles = 5;
  static const attachmentBytes = 5 * 1000 * 1000;
  static const maxChars = 200000;
}

class ExtractedText {
  const ExtractedText(this.text, {this.truncated = false});
  final String text;
  final bool truncated;
  bool get isEmpty => text.trim().isEmpty;
}

class UnsupportedFileException implements Exception {
  UnsupportedFileException(this.message);
  final String message;
  @override
  String toString() => message;
}

String extensionOf(String name) {
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}

ExtractedText _cap(String text) {
  final clean = text.replaceAll('\r\n', '\n').replaceAll(RegExp(r'[ \t]+\n'), '\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  if (clean.length <= UploadLimits.maxChars) return ExtractedText(clean);
  return ExtractedText(clean.substring(0, UploadLimits.maxChars), truncated: true);
}

/// Reads the text out of a DOCX file (word/document.xml), one line per paragraph.
String docxText(List<int> bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final entry = archive.findFile('word/document.xml');
  if (entry == null) throw UnsupportedFileException('This Word file has no readable text.');
  final xml = XmlDocument.parse(utf8.decode(entry.content as List<int>, allowMalformed: true));
  final paragraphs = <String>[];
  for (final p in xml.findAllElements('w:p')) {
    final b = StringBuffer();
    for (final node in p.descendants.whereType<XmlElement>()) {
      switch (node.name.qualified) {
        case 'w:t':
          b.write(node.innerText);
        case 'w:tab':
          b.write('\t');
        case 'w:br':
          b.write('\n');
      }
    }
    paragraphs.add(b.toString());
  }
  return paragraphs.join('\n');
}

/// Extracts plain text from PDF, DOCX, TXT and MD files.
class DocumentExtractor {
  const DocumentExtractor();

  Future<ExtractedText> extract(String path) async {
    final ext = extensionOf(path);
    switch (ext) {
      case 'txt':
      case 'md':
        return Isolate.run(() async => _cap(utf8.decode(await File(path).readAsBytes(), allowMalformed: true)));
      case 'docx':
        return Isolate.run(() async => _cap(docxText(await File(path).readAsBytes())));
      case 'pdf':
        return _cap(await _pdfText(path));
      default:
        throw UnsupportedFileException('Only PDF, DOCX, TXT or MD files can be added.');
    }
  }

  Future<String> _pdfText(String path) async {
    final doc = await PdfDocument.openFile(path);
    try {
      final b = StringBuffer();
      for (final page in doc.pages) {
        final PdfPageText? text = await page.loadText();
        b
          ..write(text?.fullText ?? '')
          ..write('\n\n');
        if (b.length > UploadLimits.maxChars) break;
      }
      return b.toString();
    } finally {
      await doc.dispose();
    }
  }
}
