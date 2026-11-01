import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/documents/document_index.dart';
import '../../core/documents/extractor.dart';

/// Opens the system file picker for PDF, DOCX, TXT or MD. The app lock is
/// paused meanwhile, so leaving for the picker doesn't lock Medha.
Future<PickedFile?> pickDocument(WidgetRef ref) async {
  final lock = ref.read(appLockProvider);
  final result = await lock.whileExternal(
    () => FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: UploadLimits.allowedExtensions),
  );
  final f = result?.files.singleOrNull;
  final path = f?.path;
  if (f == null || path == null) return null;
  return PickedFile(name: f.name, path: path, bytes: f.size);
}
